-- tests/kernel/test_blackboard_namespace_audit.lua
-- AUDIT 2: a plugin owns exactly one blackboard namespace, and no raw SDK handle crosses the
-- blackboard.
--
-- ADR 08 §2.7 / CLAUDE.md: blackboard state is scoped by domain -- `player.*`, `combat.*`, and
-- `module.<module_name>.*` for module-owned state. A plugin that reads `module.<other>.*` has
-- made a private key into a public one by using it, without either side agreeing to that.
-- Deleting or retyping such a key then breaks a package that never declared the dependency.
--
-- TWO DISTINCT FAILURES, KEPT SEPARATE BECAUSE THEY HAVE DIFFERENT FIXES.
--
--   CROSS-NAMESPACE -- reading `module.<other>.*`. Fix: the owner publishes it through the
--   public API, or the reader stops needing it. A rename, not a rewrite.
--
--   RAW HANDLE -- putting a live SDK object (`player.object`) on the blackboard and calling
--   methods off it. Fix: a snapshot field. This one is worse than it looks: a handle is only
--   valid for the tick that produced it, so a stale read is not "old data", it is undefined
--   behaviour. `condition_library.lua:474` calls `player:get_max_health()` straight off the
--   handle -- that is a live SDK call wearing a blackboard read's clothes, and it is exactly
--   what ADR 08 §9.3's "every unreadable field silently becomes a plausible-looking zero"
--   describes.
--
-- ===========================================================================================
-- THE RAW-HANDLE CHECK IS NOW A BACKSTOP, NOT THE PRIMARY DEFENCE.
-- ===========================================================================================
-- `HANDLE_KEY` below matches keys ending in `.object`. That is a rule about SPELLING, and it
-- was wrong about what it looked at: `combat.target`, `player.target` and
-- `combat.low_health_add` all hold live handles under names it never agreed to inspect, so it
-- reported a clean bill of health for the majority of the problem. Widening the pattern would
-- only move the blind spot to the next name nobody thought of.
--
-- The primary defence is now `Blackboard:set` itself (core/blackboard.lua), which refuses any
-- value carrying behaviour at any depth without ever reading the key, plus its shrink-only
-- HANDLE_LEDGER. See tests/kernel/test_blackboard_handle_guard.lua.
--
-- THIS AUDIT IS KEPT ANYWAY, BECAUSE THE TWO ARE BLIND IN OPPOSITE DIRECTIONS.
--   The runtime guard sees only code the offline suite actually EXECUTES. Measured: the suite
--   sets `combat.low_health_add` 32 times and never once with a handle, because its mock adds
--   are plain tables -- in the client that key holds a live unit. A guard alone would have
--   missed it.
--   This audit reads SOURCE TEXT, so it sees keys on paths no test covers -- but only the ones
--   spelled `.object`.
-- Neither is complete. The ledger in core/blackboard.lua is the union, maintained by hand, and
-- that is precisely why it has to be justified per entry rather than harvested from a run.
--
-- LEDGER GRANULARITY -- WHY COUNTS AND NOT LINES HERE.
-- Audit 3 ledgers `file:line` because it has 22 violations. This audit has ~110, and a
-- hand-maintained 110-entry line ledger rots into noise that gets bulk-edited rather than
-- read. So the LEDGER is per-file counts (which may only decrease) while the REPORT still
-- names every `file:line`. The tradeoff, stated plainly: swapping one violation for another
-- inside an already-dirty file is not caught. Adding one to a clean file, or increasing any
-- file's count, is.

local T = require("tests/test_util")
local Scope = require("tests/kernel/audit_scope")

local M = {}

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

--- A blackboard key literal naming a module namespace: `"module.<ns>.…"`.
--- Anchored on the opening quote so a require path (`"modules/combat/module.lua"`) or a field
--- access (`module.build`) cannot masquerade as a namespaced key.
local MODULE_KEY = '"module%.([%w_]+)%.'

--- A raw SDK handle parked on the blackboard, IF it happens to be spelled `.object`. See the
--- header: this is the backstop's known limit, not a definition of what a handle is. The
--- definition lives in `Blackboard._assert_pure`, which never reads the key at all.
local HANDLE_KEY = '"([%w_%.]-)%.object"'

---Cross-namespace reads and writes for one package.
---@param pkg table an entry from Scope.PACKAGES
---@return table[] violations
local function audit_cross_namespace(pkg)
    local violations = {}
    Scope.each_package_line(pkg.dir, function(path, line, line_number)
        for namespace in line:gmatch(MODULE_KEY) do
            if namespace ~= pkg.namespace then
                violations[#violations + 1] = {
                    file = path,
                    line = line_number,
                    detail = "reads module." .. namespace .. ".* but owns module."
                        .. pkg.namespace,
                }
            end
        end
    end)
    return violations
end

---Raw SDK handles crossing the blackboard.
---@param dir string
---@return table[] violations
local function audit_raw_handles(dir)
    local violations = {}
    Scope.each_package_line(dir, function(path, line, line_number)
        for prefix in line:gmatch(HANDLE_KEY) do
            violations[#violations + 1] = {
                file = path,
                line = line_number,
                detail = "raw SDK handle on the blackboard: \"" .. prefix
                    .. ".object\" -- use a snapshot field",
            }
        end
    end)
    return violations
end

---Every `module.*` key a promotion candidate touches, own namespace included.
---@param path string
---@return table[] violations
local function audit_promotion_blockers(path)
    local violations = {}
    local source = Scope.read_file(path)
    if not source then return violations end
    Scope.each_code_line(source, function(line, line_number)
        for namespace in line:gmatch(MODULE_KEY) do
            violations[#violations + 1] = {
                file = path,
                line = line_number,
                detail = "promotion blocker: touches module." .. namespace
                    .. ".* -- kernel code owns no module namespace",
            }
        end
    end)
    return violations
end

M._audit_cross_namespace = audit_cross_namespace
M._audit_raw_handles = audit_raw_handles
M._audit_promotion_blockers = audit_promotion_blockers

-- ---------------------------------------------------------------------------
-- Vacuity guard
-- ---------------------------------------------------------------------------

--- Both checks must have something to look at. Audit 3 guards the shared scope; this guards
--- that the scope actually contains blackboard traffic, so a refactor that moved every key
--- somewhere unscanned would fail here rather than report a clean bill of health.
function M.test_the_audit_has_blackboard_traffic_to_scan()
    local keys = 0
    for _, pkg in ipairs(Scope.PACKAGES) do
        Scope.each_package_line(pkg.dir, function(_, line)
            if line:match('"module%.') or line:match('"player%.') then keys = keys + 1 end
        end)
    end
    T.assert_true(keys > 0,
        "no blackboard keys found anywhere in scope -- this audit would be vacuous")
end

-- ---------------------------------------------------------------------------
-- Control tests
-- ---------------------------------------------------------------------------

local PROBE = "/tmp/sentinel_blackboard_audit_probe"

local function write_probe(contents)
    os.execute('rm -rf "' .. PROBE .. '" && mkdir -p "' .. PROBE .. '"')
    local handle = io.open(PROBE .. "/offender.lua", "w")
    handle:write(contents)
    handle:close()
end

local function clear_probe() os.execute('rm -rf "' .. PROBE .. '"') end

function M.test_the_cross_namespace_check_detects_a_foreign_read()
    write_probe([[
-- a comment about blackboard:get("module.grind.needs_food") must NOT count
local function read(bb)
    local own = bb:get("module.probe.state")
    local foreign = bb:get("module.grind.needs_food")
    return own, foreign
end
return read
]])
    local violations = audit_cross_namespace(
        { dir = PROBE, namespace = "probe" })
    clear_probe()

    T.assert_equal(#violations, 1, "exactly the foreign namespace must be flagged")
    -- Lua drops the newline immediately after `[[`, so the comment is line 1.
    T.assert_equal(violations[1].line, 4, "the comment on line 1 must be ignored")
    T.assert_true(violations[1].detail:match("module%.grind") ~= nil, violations[1].detail)
end

--- A require path and a plain field access must not be mistaken for a namespaced key.
function M.test_the_cross_namespace_check_ignores_paths_and_field_access()
    write_probe([[
local Mod = require("modules/combat/module")
local name = "modules/combat/module.lua"
local built = module.build()
return Mod, name, built
]])
    local violations = audit_cross_namespace({ dir = PROBE, namespace = "probe" })
    clear_probe()
    T.assert_equal(#violations, 0,
        "only quoted `\"module.<ns>.` keys are namespace reads:\n  " .. Scope.describe(violations))
end

function M.test_the_raw_handle_check_detects_a_handle_read()
    write_probe([[
local function read(bb)
    local player = bb:get("player.object")
    return player:get_max_health()
end
return read
]])
    local violations = audit_raw_handles(PROBE)
    clear_probe()
    T.assert_equal(#violations, 1)
    T.assert_equal(violations[1].line, 2)
end

function M.test_the_raw_handle_check_accepts_a_snapshot_field()
    write_probe([[
local function read(bb)
    return bb:get("player.health_pct"), bb:get("player.position")
end
return read
]])
    local violations = audit_raw_handles(PROBE)
    clear_probe()
    T.assert_equal(#violations, 0, "snapshot fields are the correct pattern")
end

-- ---------------------------------------------------------------------------
-- THE EXIT CRITERION (ratcheted per file)
-- ---------------------------------------------------------------------------

--- `file` -> number of cross-namespace accesses still tolerated. Burned down by Phase 4b
--- Deliverable 4 (combat becomes a plugin) and by publishing what mage_frost needs through
--- the public API.
local CROSS_NAMESPACE_LEDGER = {
    ["sentinel/rotations/mage_frost/aoe_tree.lua"] = 2,
    ["sentinel/rotations/mage_frost/frost_actions.lua"] = 3,
    -- 7 -> 6 and 6 -> 5 in Phase 4d D1. Both files read `module.combat.izi_bridge` to reach the IZI
    -- adapter across the package boundary; that key is gone and the adapter is published as
    -- `Sentinel.forecast`, so the read left through the front door rather than being renamed.
    ["sentinel/rotations/mage_frost/frost_combat_state.lua"] = 6,
    ["sentinel/rotations/mage_frost/frost_conditions.lua"] = 5,
    -- 2 -> 1 in Phase 4c. `Support.dispatcher` read `module.combat.dispatcher` -- the coupling this
    -- file's own header called out as one the require audit could not see, because it travelled
    -- through a string key rather than an import. Casts now leave as intents, so the read is gone
    -- and there is no dispatcher reference left in the package. The remaining 1 is
    -- `module.combat.catalog`, which rank resolution still needs.
    ["sentinel/rotations/mage_frost/frost_support.lua"] = 1,
    ["sentinel/rotations/mage_frost/frost_tbc.lua"] = 4,
    ["sentinel/rotations/mage_frost/maintenance_tree.lua"] = 4,
    -- combat's own `module.combat.*` traffic is legal today; only its reach into
    -- `module.grind.*` is not.
    ["sentinel/modules/combat/strategies/grind_target_strategy.lua"] = 2,
}

--- `file` -> `module.*` accesses a promotion candidate may still carry. ADR 08 §11.4's
--- "rework". These are legal TODAY -- `module.combat.*` is combat's own namespace -- and
--- become violations the moment the file lands in the kernel, which is the point of counting
--- them before the move rather than during it.
local PROMOTION_BLOCKER_LEDGER = {
    -- 10 -> 7 in Phase 4d D1. Three of the ten were `module.combat.izi_bridge` reads
    -- (`time_to_die_below`, `incoming_damage_above`, `health_prediction_below`). They now read
    -- `Sentinel.forecast`, which is kernel-owned and therefore survives the promotion this ledger
    -- counts down to.
    ["sentinel/modules/combat/condition_library.lua"] = 7,
}

--- `file` -> number of raw handle reads still tolerated. `condition_library.lua`'s 7 are the
--- "rework" half of ADR 08 §11.4's PROMOTE-with-rework verdict: the file cannot be promoted
--- into the kernel while it calls methods off a live handle it pulled from shared state.
local RAW_HANDLE_LEDGER = {
    ["sentinel/rotations/mage_frost/frost_actions.lua"] = 22,
    ["sentinel/rotations/mage_frost/frost_combat_state.lua"] = 1,
    ["sentinel/rotations/mage_frost/frost_conditions.lua"] = 6,
    ["sentinel/rotations/mage_frost/frost_support.lua"] = 1,
    ["sentinel/rotations/mage_frost/frost_tbc.lua"] = 1,
    ["sentinel/rotations/mage_frost/kite_controller.lua"] = 1,
    ["sentinel/rotations/mage_frost/pet_controller.lua"] = 1,
    ["sentinel/modules/combat/action_library.lua"] = 4,
    ["sentinel/modules/combat/combat_zone_detector.lua"] = 1,
    ["sentinel/modules/combat/condition_library.lua"] = 7,
    ["sentinel/modules/combat/context_builder.lua"] = 1,
    ["sentinel/modules/combat/module.lua"] = 4,
    ["sentinel/modules/combat/profiles/paladin/retribution_actions.lua"] = 10,
    ["sentinel/modules/combat/profiles/paladin/retribution_conditions.lua"] = 3,
    ["sentinel/modules/combat/profiles/warlock/pet_controller.lua"] = 1,
    ["sentinel/modules/combat/shared_subtrees.lua"] = 4,
    ["sentinel/modules/combat/strategies/default_target_strategy.lua"] = 3,
    ["sentinel/modules/combat/strategies/grind_target_strategy.lua"] = 3,
    ["sentinel/modules/combat/swing_tracker.lua"] = 1,
}

---Fail if any file exceeds its allowance, or appears without one.
---@param violations table[]
---@param ledger table<string, integer>
---@param what string
local function assert_within_ledger(violations, ledger, what)
    local counts = {}
    for _, v in ipairs(violations) do counts[v.file] = (counts[v.file] or 0) + 1 end

    local regressions = {}
    for file, count in pairs(counts) do
        local allowed = ledger[file]
        if not allowed then
            regressions[#regressions + 1] = file .. ": " .. count .. " (file was clean)"
        elseif count > allowed then
            regressions[#regressions + 1] =
                file .. ": " .. count .. " > " .. allowed .. " allowed"
        end
    end

    -- The ratchet only ratchets if a fixed file is removed from the ledger.
    for file, allowed in pairs(ledger) do
        local count = counts[file] or 0
        if count < allowed then
            regressions[#regressions + 1] = file .. ": down to " .. count .. " -- lower the "
                .. "ledger to " .. count .. (count == 0 and " (or delete the entry)" or "")
        end
    end
    table.sort(regressions)

    T.assert_equal(#regressions, 0, what .. " ledger is out of date:\n  "
        .. table.concat(regressions, "\n  ")
        .. "\n\nfull findings:\n  " .. Scope.describe(violations))
end

function M.test_no_package_reads_another_packages_namespace()
    local all = {}
    for _, pkg in ipairs(Scope.PACKAGES) do
        for _, v in ipairs(audit_cross_namespace(pkg)) do all[#all + 1] = v end
    end
    assert_within_ledger(all, CROSS_NAMESPACE_LEDGER, "cross-namespace")
end

function M.test_no_raw_sdk_handle_crosses_the_blackboard()
    local all = {}
    for _, pkg in ipairs(Scope.PACKAGES) do
        for _, v in ipairs(audit_raw_handles(pkg.dir)) do all[#all + 1] = v end
    end
    assert_within_ledger(all, RAW_HANDLE_LEDGER, "raw-handle")
end

function M.test_promotion_candidates_are_tracked_toward_a_module_free_kernel()
    T.assert_true(#Scope.PROMOTION_CANDIDATES > 0,
        "no promotion candidates listed -- this check would be vacuous")

    local all = {}
    for _, path in ipairs(Scope.PROMOTION_CANDIDATES) do
        for _, v in ipairs(audit_promotion_blockers(path)) do all[#all + 1] = v end
    end
    assert_within_ledger(all, PROMOTION_BLOCKER_LEDGER, "promotion-blocker")
end

return M
