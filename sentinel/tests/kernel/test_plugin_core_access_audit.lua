-- tests/kernel/test_plugin_core_access_audit.lua
-- AUDIT 3: a plugin never touches the Sylvannas SDK directly, and never truthiness-tests a
-- Truth value.
--
-- ADR 08 §3.3: the kernel ships zero behaviour not expressible through the public API. A
-- rotation that calls `core.input.pet_attack` has not been ported to the kernel -- it has been
-- moved into a directory the kernel happens to own. Every game-affecting action must leave a
-- plugin as an intent, so that arbitration, banding and the control broker actually see it.
--
-- ============================================================================
-- CHECK 4 (the truthiness lint) IS A LINT, NOT A PROOF. READ THIS.
-- ============================================================================
-- ADR 08 §9.2 / kernel/truth.lua: Lua has no `__toboolean`. `if t then` cannot be intercepted
-- for ANY table value, so the Truth type CANNOT make a careless truthiness test raise. Every
-- Truth value is a table precisely so that `if truth_value then` is wrong on the FIRST case
-- rather than the rare one -- but that is detection by test, not prevention by type.
--
-- This check is the static half of that mitigation, and it is deliberately partial:
--
--   * SINGLE-FILE, LOCAL DATAFLOW ONLY. It knows a local was assigned from `Sentinel.cond.*`
--     in the same file. It does NOT follow values across function boundaries, into or out of
--     tables, through varargs, or through a returned closure. A Truth value handed to a
--     helper and tested there WILL NOT BE CAUGHT.
--   * NAME-SCOPED AT FILE LEVEL, not block level. A local named `ready` assigned from a cond
--     call in one function makes `if ready then` suspicious in every function in that file.
--     That is an over-approximation, and the direction is deliberate: a false positive gets
--     argued about and fixed, a false negative gets trusted.
--   * TEXTUAL. It reads lines, not an AST. Multi-line boolean expressions are seen one line
--     at a time.
--
-- So: passing this check does not mean a file is free of truthiness bugs. It means the
-- obvious ones are gone. Anything that claims more than that is worse than no check, because
-- it licenses carelessness everywhere it cannot see.

local T = require("tests/test_util")
local Scope = require("tests/kernel/audit_scope")

local M = {}

-- ---------------------------------------------------------------------------
-- Check 1-3: direct SDK access
-- ---------------------------------------------------------------------------

--- Any mention of the `core` global. Guards (`if core and core.input then`) count: they exist
--- only to reach the call underneath them, and converting the call removes the guard with it.
--- The frontier pattern keeps `_core.x` and `mycore.x` from matching.
local CORE_REFERENCE = "%f[%w_]core%s*%."

---@param package_dir string
---@return table[] violations
local function audit_core_access(package_dir)
    local violations = {}
    Scope.each_package_line(package_dir, function(path, line, line_number)
        local hit = line:match(CORE_REFERENCE .. "[%w_%.]*")
        if hit then
            violations[#violations + 1] = {
                file = path,
                line = line_number,
                detail = "direct SDK access: " .. hit:gsub("%s+", ""),
            }
        end
    end)
    return violations
end

M._audit_core_access = audit_core_access

-- ---------------------------------------------------------------------------
-- Check 4: truthiness-testing a Truth value
-- ---------------------------------------------------------------------------

--- Calls that legitimately CONSUME a Truth value. Their arguments are blanked before the
--- boolean-position scan, so `if Truth.resolve(Sentinel.cond.x(), policy) then` stays clean.
local CONSUMERS = { "resolve", "decide", "is" }

---Blank out the argument list of every legitimate consumer call on a line.
---@param line string
---@return string
local function neutralize_consumers(line)
    for _, name in ipairs(CONSUMERS) do
        -- `%b()` matches a balanced parenthesis span, so nested calls are consumed whole.
        line = line:gsub("[%w_%.:]*%f[%w_]" .. name .. "%s*(%b())", function(args)
            return "CONSUMED" .. string.rep("_", #args - 2)
        end)
    end
    return line
end

---Collect the local names in a file that hold a Truth value, and any alias for `Sentinel.cond`.
---@param source string
---@return table<string, boolean> truth_locals, string[] cond_prefixes
local function collect_truth_locals(source)
    local cond_prefixes = { "Sentinel%s*%.%s*cond%s*%." }
    local truth_locals = {}

    -- Pass 1: aliases. `local C = Sentinel.cond` makes `C.foo()` a cond call.
    Scope.each_code_line(source, function(line)
        local alias = line:match("local%s+([%w_]+)%s*=%s*Sentinel%s*%.%s*cond%s*[^%.%w_]")
            or line:match("local%s+([%w_]+)%s*=%s*Sentinel%s*%.%s*cond%s*$")
        if alias then cond_prefixes[#cond_prefixes + 1] = alias .. "%s*%." end
    end)

    -- Pass 2: locals assigned from a cond call through any known prefix.
    Scope.each_code_line(source, function(line)
        for _, prefix in ipairs(cond_prefixes) do
            local name = line:match("local%s+([%w_]+)%s*=%s*" .. prefix .. "[%w_]+%s*%(")
            if name then truth_locals[name] = true end
        end
    end)

    return truth_locals, cond_prefixes
end

---Is `expr` (a Lua pattern matching some expression) in a boolean position on this line?
---@param line string
---@param expr string Lua pattern
---@return string|nil the offending fragment
local function boolean_position(line, expr)
    local shapes = {
        "if%s+" .. expr,
        "elseif%s+" .. expr,
        "while%s+" .. expr,
        "until%s+" .. expr,
        "not%s+" .. expr,
        "and%s+" .. expr,
        "or%s+" .. expr,
        expr .. "[%w_%.%(%)]*%s+and%f[%s]",
        expr .. "[%w_%.%(%)]*%s+or%f[%s]",
    }
    for _, shape in ipairs(shapes) do
        local hit = line:match(shape)
        if hit then return hit end
    end
    return nil
end

---@param package_dir string
---@return table[] violations
local function audit_truthiness(package_dir)
    local violations = {}
    for _, path in ipairs(Scope.lua_files(package_dir)) do
        local source = Scope.read_file(path)
        if source then
            local truth_locals, cond_prefixes = collect_truth_locals(source)

            local exprs = {}
            for _, prefix in ipairs(cond_prefixes) do
                exprs[#exprs + 1] = prefix .. "[%w_]+"
            end
            for name in pairs(truth_locals) do
                exprs[#exprs + 1] = "%f[%w_]" .. name .. "%f[^%w_]"
            end

            Scope.each_code_line(source, function(line, line_number)
                local scannable = neutralize_consumers(line)
                for _, expr in ipairs(exprs) do
                    local hit = boolean_position(scannable, expr)
                    if hit then
                        violations[#violations + 1] = {
                            file = path,
                            line = line_number,
                            detail = "Truth value in a boolean position: " .. hit
                                .. "  -- resolve it with an explicit UnknownPolicy",
                        }
                        break
                    end
                end
            end)
        end
    end
    return violations
end

M._audit_truthiness = audit_truthiness

-- ---------------------------------------------------------------------------
-- Vacuity guards
-- ---------------------------------------------------------------------------

--- An audit with nothing to audit passes for free, which is indistinguishable from an audit
--- that works.
function M.test_the_scope_is_not_empty()
    T.assert_true(#Scope.PACKAGES > 0, "no packages in scope -- every audit would be vacuous")
    local scanned = 0
    for _, pkg in ipairs(Scope.PACKAGES) do
        T.assert_true(Scope.dir_exists(pkg.dir), "package dir missing: " .. pkg.dir)
        scanned = scanned + #Scope.lua_files(pkg.dir)
    end
    T.assert_true(scanned > 0, "scope contains no .lua files -- the audits would be vacuous")
end

--- The scope must not silently miss a package that exists on disk. This is the exact failure
--- that reported the `core.input` count as one.
function M.test_every_package_on_disk_is_in_scope()
    local registered = {}
    for _, pkg in ipairs(Scope.PACKAGES) do registered[pkg.dir] = true end

    for _, root in ipairs(Scope.PACKAGE_ROOTS) do
        for _, dir in ipairs(Scope.subdirs(root)) do
            T.assert_true(registered[dir],
                "package '" .. dir .. "' exists on disk but is not in Scope.PACKAGES -- "
                .. "it is invisible to all three audits")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Control tests: point each check at a tree that is known to violate it
-- ---------------------------------------------------------------------------

local PROBE = "/tmp/sentinel_core_access_probe"

local function write_probe(contents)
    os.execute('rm -rf "' .. PROBE .. '" && mkdir -p "' .. PROBE .. '"')
    local handle = io.open(PROBE .. "/offender.lua", "w")
    handle:write(contents)
    handle:close()
end

local function clear_probe()
    os.execute('rm -rf "' .. PROBE .. '"')
end

function M.test_the_core_access_check_detects_a_direct_sdk_call()
    write_probe([[
-- a comment mentioning core.input.pet_attack must NOT count
local function attack(target)
    pcall(core.input.pet_attack, target)
end
local score = record.score
local other = mycore.thing
return attack, score, other
]])
    local violations = audit_core_access(PROBE)
    clear_probe()

    T.assert_equal(#violations, 1, "exactly the real SDK call must be flagged")
    T.assert_equal(violations[1].line, 3, "the comment on line 2 must be ignored")
    T.assert_true(violations[1].detail:match("core%.input%.pet_attack") ~= nil,
        "the report must name the call: " .. violations[1].detail)
end

function M.test_the_truthiness_check_detects_a_bare_if_on_a_cond_call()
    write_probe([[
local function run()
    if Sentinel.cond.health_below(0.3) then return "bad" end
end
return run
]])
    local violations = audit_truthiness(PROBE)
    clear_probe()
    T.assert_equal(#violations, 1, "the bare `if` on a cond call must be flagged")
    T.assert_equal(violations[1].line, 2)
end

function M.test_the_truthiness_check_follows_a_local_within_the_file()
    write_probe([[
local function run()
    local low = Sentinel.cond.health_below(0.3)
    if low then return "bad" end
end
return run
]])
    local violations = audit_truthiness(PROBE)
    clear_probe()
    T.assert_equal(#violations, 1, "the local assigned from a cond call must be tracked")
    T.assert_equal(violations[1].line, 3, "the flag belongs on the truthiness test, not the assignment")
end

function M.test_the_truthiness_check_flags_and_or_composition()
    write_probe([[
local function run()
    local a = Sentinel.cond.in_combat()
    return a and other_thing()
end
return run
]])
    local violations = audit_truthiness(PROBE)
    clear_probe()
    T.assert_equal(#violations, 1, "`and` on a Truth value must be flagged -- use Truth.and_")
    T.assert_equal(violations[1].line, 3)
end

--- The check must NOT fire on the correct pattern, or nobody will keep it.
function M.test_the_truthiness_check_accepts_a_properly_resolved_value()
    write_probe([[
local Truth = Sentinel.truth
local function run(policy)
    if Truth.resolve(Sentinel.cond.health_below(0.3), policy) then return "act" end
    local low = Sentinel.cond.in_combat()
    local decided = gate:decide(low)
    if decided then return "act" end
    return Truth.and_(low, Sentinel.cond.has_target())
end
return run
]])
    local violations = audit_truthiness(PROBE)
    clear_probe()
    T.assert_equal(#violations, 0,
        "resolved and combinator-composed values are correct usage:\n  " .. Scope.describe(violations))
end

--- Proves the lint states its own limit honestly: a Truth value passed to a helper escapes it.
--- If this ever starts failing, the lint got stronger and the header must be rewritten.
function M.test_the_truthiness_check_admits_it_cannot_cross_a_function_boundary()
    write_probe([[
local function helper(value)
    if value then return "unsafe" end
end
local function run()
    return helper(Sentinel.cond.in_combat())
end
return run
]])
    local violations = audit_truthiness(PROBE)
    clear_probe()
    T.assert_equal(#violations, 0,
        "documented limitation: single-file LOCAL dataflow does not cross function boundaries")
end

-- ---------------------------------------------------------------------------
-- THE EXIT CRITERION (ratcheted)
-- ---------------------------------------------------------------------------

--- Known direct-SDK violations, `file:line` -> the deliverable that removes each one.
--- Phase 4b Deliverable 2 converts these onto intents. The ledger may only shrink; a new
--- violation fails immediately, and a fixed one must be deleted from here.
local CORE_ACCESS_LEDGER = {
    -- kite_controller: FACING + MOVEMENT. No intent type exists for either yet.
    ["sentinel/rotations/mage_frost/kite_controller.lua:164"] = "D2: guard for look_at/move",
    ["sentinel/rotations/mage_frost/kite_controller.lua:165"] = "D2: core.input.look_at",
    ["sentinel/rotations/mage_frost/kite_controller.lua:167"] = "D2: core.input.move_forward_start",
    ["sentinel/rotations/mage_frost/kite_controller.lua:174"] = "D2: guard for move_forward_stop",
    ["sentinel/rotations/mage_frost/kite_controller.lua:175"] = "D2: core.input.move_forward_stop",
    ["sentinel/rotations/mage_frost/kite_controller.lua:182"] = "D2: guard for look_at",
    ["sentinel/rotations/mage_frost/kite_controller.lua:183"] = "D2: core.input.look_at",

    -- frost_actions: ITEMS + MOVEMENT.
    ["sentinel/rotations/mage_frost/frost_actions.lua:396"] = "D2: guard for use_item",
    ["sentinel/rotations/mage_frost/frost_actions.lua:397"] = "D2: core.input.use_item",
    ["sentinel/rotations/mage_frost/frost_actions.lua:410"] = "D2: guard for use_item",
    ["sentinel/rotations/mage_frost/frost_actions.lua:411"] = "D2: core.input.use_item",
    ["sentinel/rotations/mage_frost/frost_actions.lua:484"] = "D2: guard for move_forward_start",
    ["sentinel/rotations/mage_frost/frost_actions.lua:485"] = "D2: core.input.move_forward_start",

    -- pet_controller's four calls and their guards are GONE (Phase 4b D3): every command now
    -- leaves as a `pet_command` intent under a PET lease.

    -- frost_tbc's `core.log` is GONE (Phase 4b D3): §10's `Sentinel.log` now carries the GCD
    -- diagnostic, attributed from the call site. Logging was never an intent -- it contends
    -- for no channel -- so it needed a facility on the public API, and kernel/log.lua is it.
}

function M.test_no_plugin_touches_the_sdk_directly()
    local all = {}
    for _, pkg in ipairs(Scope.PACKAGES) do
        if not pkg.migrating then
            for _, v in ipairs(audit_core_access(pkg.dir)) do all[#all + 1] = v end
        end
    end

    local unexpected, stale = Scope.ratchet(all, CORE_ACCESS_LEDGER)

    T.assert_equal(#unexpected, 0,
        "NEW direct SDK access in a plugin:\n  " .. Scope.describe(unexpected)
        .. "\nEvery game-affecting action must leave the plugin as an intent.")

    T.assert_equal(#stale, 0,
        "these ledger entries are fixed and must be DELETED from CORE_ACCESS_LEDGER:\n  "
        .. table.concat(stale, "\n  ")
        .. "\nA ledger that outlives its violations stops being a worklist.")
end

function M.test_no_plugin_truthiness_tests_a_truth_value()
    local all = {}
    for _, pkg in ipairs(Scope.PACKAGES) do
        for _, v in ipairs(audit_truthiness(pkg.dir)) do all[#all + 1] = v end
    end
    T.assert_equal(#all, 0,
        "a Truth value was used where Lua expects a boolean:\n  " .. Scope.describe(all)
        .. "\nLua has no __toboolean -- `if t then` is TRUE for Truth.False too. "
        .. "Resolve it with an explicit UnknownPolicy.")
end

return M
