-- tests/kernel/test_plugin_require_audit.lua
-- THE Phase 4 exit criterion, enforced mechanically rather than by inspection.
--
-- ADR 08 §8.1: "Promotion later is mechanical IF AND ONLY IF no plugin ever reaches past the public
-- API. That discipline is the thing to enforce now."
--
-- §3.3 says the same from the other side: the kernel ships zero behaviour not expressible through
-- the public API, because "if the kernel can privilege itself, the public API silently rots". A
-- rotation that reaches into `modules/combat/...` proves nothing about the API's adequacy -- it just
-- proves the old module still works, which was never in question.
--
-- THE RULE: a plugin may require files inside its OWN package and nothing else. Everything it needs
-- from the kernel arrives through `_G.Sentinel`. Intra-package requires are allowed because a
-- 2,000-line rotation is not one file; cross-package requires are not, because that is the exact
-- move that would make this phase worthless.
--
-- If a plugin needs something the public API lacks, the fix is to ADD IT TO THE API and log the gap
-- in 08a_API_GAPS.md -- never to import the internal module.

-- SCOPE (Phase 4b Deliverable 3). This audit used to discover its own packages by globbing
-- `sentinel/rotations`. It now shares `tests/kernel/audit_scope`, because a per-audit scope is
-- how the `core.input` count in rotations/ came to be reported as ONE when the real number was
-- an order of magnitude higher: the audit was not wrong about what it saw, it was wrong about
-- what it looked at. One scope, asserted non-empty once, consumed by all three audits.

local T = require("tests/test_util")
local Scope = require("tests/kernel/audit_scope")

local M = {}

-- ---------------------------------------------------------------------------
-- The audit itself
-- ---------------------------------------------------------------------------

local read_file = Scope.read_file
local list_lua_files = Scope.lua_files

--- Extract every `require("...")` target from a source string, with its line number.
--- Whole-line comments are skipped, so prose about `require("modules/...")` is not a violation.
local function requires_in(source)
    local found = {}
    Scope.each_code_line(source, function(line, line_number)
        for target in line:gmatch('require%s*%(?%s*"([^"]+)"') do
            found[#found + 1] = { target = target, line = line_number }
        end
    end)
    return found
end

---Audit one plugin package.
---@param package_dir string e.g. "sentinel/rotations/mage_frost"
---@param package_prefix string the require prefix its own files use, e.g. "rotations/mage_frost"
---@return table violations { {file, line, target} }
local function audit(package_dir, package_prefix)
    local violations = {}
    for _, path in ipairs(list_lua_files(package_dir)) do
        local source = read_file(path)
        if source then
            for _, r in ipairs(requires_in(source)) do
                if r.target:sub(1, #package_prefix) ~= package_prefix then
                    violations[#violations + 1] =
                        { file = path, line = r.line, target = r.target }
                end
            end
        end
    end
    return violations
end

M._audit = audit

local function describe(violations)
    local out = {}
    for _, v in ipairs(violations) do
        out[#out + 1] = v.file .. ":" .. v.line .. ' require("' .. v.target .. '")'
    end
    return table.concat(out, "\n  ")
end

-- ---------------------------------------------------------------------------
-- The audit must not be vacuous
-- ---------------------------------------------------------------------------

--- An audit with nothing to audit passes for free, which is indistinguishable from an audit that
--- works. This is the guard against the whole file becoming decorative.
function M.test_there_is_at_least_one_plugin_package_to_audit()
    T.assert_true(#Scope.PACKAGES > 0, "no packages in scope -- the require audit would be vacuous")

    local requires_seen = 0
    for _, pkg in ipairs(Scope.PACKAGES) do
        T.assert_true(Scope.dir_exists(pkg.dir), "package dir missing: " .. pkg.dir)
        for _, path in ipairs(list_lua_files(pkg.dir)) do
            local source = read_file(path)
            if source then requires_seen = requires_seen + #requires_in(source) end
        end
    end
    -- Scanning files is not the same as scanning requires. A pattern that matched nothing
    -- would still see files and still report zero violations.
    T.assert_true(requires_seen > 0,
        "no require() calls found anywhere in scope -- the extraction pattern is broken")
end

--- Proves the audit actually catches the thing it exists to catch. Without this, a bug in the
--- pattern match would make every plugin "clean" forever.
function M.test_the_audit_detects_a_reach_past_the_api()
    local dir = "/tmp/sentinel_require_audit_probe"
    os.execute('rm -rf "' .. dir .. '" && mkdir -p "' .. dir .. '"')
    local handle = io.open(dir .. "/offender.lua", "w")
    handle:write([[
-- a doc comment mentioning require("modules/combat/spell_catalog") must NOT count
local Own = require("rotations/probe/helper")
local Reached = require("modules/combat/spell_catalog")
return { Own, Reached }
]])
    handle:close()

    local violations = audit(dir, "rotations/probe")
    os.execute('rm -rf "' .. dir .. '"')

    T.assert_equal(#violations, 1, "exactly the cross-package require must be flagged")
    T.assert_equal(violations[1].target, "modules/combat/spell_catalog")
    T.assert_equal(violations[1].line, 3, "and the comment on line 2 must be ignored")
end

-- ---------------------------------------------------------------------------
-- THE EXIT CRITERION
-- ---------------------------------------------------------------------------

--- ADR §12's Phase 4 exit criterion: the ported rotation uses only the public API.
---
--- Packages marked `migrating` are exempt from the assertion but NOT from the scan -- combat
--- is still a `ModuleRegistry` module and legitimately requires `core/*` until Phase 4b
--- Deliverable 4 moves it. Its count is reported so the migration knows its own size.
function M.test_every_plugin_requires_nothing_outside_its_own_package()
    for _, pkg in ipairs(Scope.PACKAGES) do
        local violations = audit(pkg.dir, pkg.require_prefix)
        if not pkg.migrating then
            T.assert_equal(#violations, 0,
                "plugin '" .. pkg.name .. "' reached past the public API:\n  "
                .. describe(violations)
                .. "\nAdd what it needs to the API and log the gap in 08a_API_GAPS.md; do not "
                .. "import the internal module.")
        end
    end
end

--- The scope must not silently miss a plugin that exists on disk. This is the exact failure
--- mode that under-reported the SDK-access count.
function M.test_no_plugin_package_on_disk_escapes_the_scope()
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

return M
