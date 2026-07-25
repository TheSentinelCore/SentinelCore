-- rotations/mage_frost/frost_support.lua
-- The plugin's own utilities. Requires nothing but `sentinel_api`.
--
-- ================================================================================
-- WHAT BELONGS HERE AND WHAT DOES NOT
-- ================================================================================
-- This file exists because the port found that `shared/combat_helpers.lua` was two different things
-- wearing one name:
--
--   1. PURE UTILITIES -- `num`, `safe_call`, `player_and_target`. Three lines each, no engine
--      coupling, no shared state. Copying them into the plugin is correct: they are not an API gap,
--      and putting them on the kernel surface would make `Sentinel.num` a thing, which is absurd.
--
--   2. THE CAST PATH -- `queue_target`, `queue_position`, `dispatcher`. These reach the combat
--      module's SpellDispatcher through the BLACKBOARD. See the warning below.
--
-- ================================================================================
-- KNOWN COUPLING THE REQUIRE AUDIT CANNOT SEE
-- ================================================================================
-- `queue_target` below reads `module.combat.dispatcher` off the blackboard. That is a live
-- dependency on the combat module -- and `tests/kernel/test_plugin_require_audit.lua` will NOT catch
-- it, because it is not a `require`. The audit inspects import statements; this coupling travels
-- through a string key at runtime.
--
-- This is recorded as a finding rather than hidden: the audit has a blind spot, and a plugin can
-- reach the entire combat engine through `blackboard:get("module.combat.*")` while auditing clean.
-- See 08a_API_GAPS.md.
--
-- It is left in place DELIBERATELY for this step. ADR §13 risk 5: "Port them; do not rewrite them."
-- Moving 38 cast sites onto `Sentinel.intent` in the same change that relocates the files would make
-- any resulting behaviour difference impossible to attribute -- was it the move, or the rewrite? The
-- files move first, with the 132 existing assertions still green, and the cast path converts second
-- as its own test-first pass.

local API = require("rotations/mage_frost/sentinel_api")

local Support = {}

--- ADR §6.3's mapping, as the two values this rotation actually uses. `1` is "everything you
--- author", `7` is the documented interrupt slot -- Counterspell is the only user of INTERRUPT here.
Support.QueuePriorities = { DEFAULT = 1, INTERRUPT = 7 }

---BT status strings, resolved live so this file does not capture nil at load time.
function Support.status()
    local bt = API.bt
    return bt and bt.Status or nil
end

-- ---------------------------------------------------------------------------
-- Pure utilities (category 1 above)
-- ---------------------------------------------------------------------------

function Support.num(value)
    return tonumber(value) or 0
end

---Safe method call, returning (ok, result). Mirrors the pattern used across the combat engine.
function Support.safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

---@return table|nil player, table|nil target
function Support.player_and_target(blackboard)
    return blackboard:get("player.object"),
        blackboard:get("combat.target") or blackboard:get("player.target")
end

-- ---------------------------------------------------------------------------
-- Action combinators
-- ---------------------------------------------------------------------------
-- Ported from `modules/combat/action_library.lua`, which the profile required for exactly these two
-- functions. They are NOT BT composites despite the names -- they compose ACTION FUNCTIONS
-- (`fn(blackboard) -> Status`) into another action function, and never build a node. So
-- `Sentinel.bt.sequence` is not a substitute, and this is not an API gap: ten lines of pure control
-- flow over the plugin's own actions belongs in the plugin.

---Run actions in order; stop at the first that does not SUCCEED, returning its status.
function Support.sequence(actions)
    return function(blackboard)
        local Status = Support.status()
        for _, action in ipairs(actions) do
            local status = action(blackboard)
            if status ~= Status.SUCCESS then
                return status
            end
        end
        return Status.SUCCESS
    end
end

---Try actions in order until one succeeds. RUNNING short-circuits so the action can continue next
---frame rather than the next alternative firing on top of it.
function Support.selector(actions)
    return function(blackboard)
        local Status = Support.status()
        for _, action in ipairs(actions) do
            local status = action(blackboard)
            if status == Status.SUCCESS then
                return Status.SUCCESS
            end
            if status == Status.RUNNING then
                return Status.RUNNING
            end
        end
        return Status.FAILURE
    end
end

-- ---------------------------------------------------------------------------
-- Catalog access
-- ---------------------------------------------------------------------------

---Resolve a spell key to the best rank the character actually knows.
---
---Prefers the kernel's shared catalog (`Sentinel.catalogs.spell`) and falls back to the blackboard's
---`module.combat.catalog` only because the existing rotation tests inject a catalog stub there. Both
---reach the same DB-baked rank data; the kernel one is authoritative once the app is up.
function Support.spell_id_for(blackboard, spell_key, mode)
    -- The BLACKBOARD catalog only. Falling back to `Sentinel.catalogs.spell` when the blackboard
    -- has none looked like an improvement and was a behaviour change: the ported code returns nil
    -- (and the action returns FAILURE) when no catalog is present, and a test pins exactly that.
    -- ADR §6.3 forbids fallback logic on the cast path for this reason -- it turns a loud failure
    -- into a quiet different behaviour.
    local catalog = blackboard:get("module.combat.catalog")
    if not catalog then return nil end
    if mode == "lowest" then
        return catalog:resolve_lowest_rank(spell_key)
    end
    return catalog:resolve_best_rank(spell_key)
end

-- ---------------------------------------------------------------------------
-- The cast path (category 2 -- see the warning in the header)
-- ---------------------------------------------------------------------------

function Support.dispatcher(blackboard)
    return blackboard:get("module.combat.dispatcher")
end

function Support.queue_target(blackboard, action_id, spell_key, target, priority, opts, mode)
    local Status = Support.status()
    local d = Support.dispatcher(blackboard)
    if not d then return Status and Status.FAILURE end
    priority = priority or Support.QueuePriorities.DEFAULT
    if d.queue_spell then
        if d:queue_spell(spell_key, target, priority, action_id, opts, mode) then
            return Status.SUCCESS
        end
        return Status.FAILURE
    end
    local spell_id = Support.spell_id_for(blackboard, spell_key, mode)
    if not spell_id then return Status.FAILURE end
    if d:queue_target(action_id, spell_id, target, priority, action_id, opts) then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

function Support.queue_position(blackboard, action_id, spell_key, position, priority, mode)
    local Status = Support.status()
    local d = Support.dispatcher(blackboard)
    if not d or type(position) ~= "table" then return Status and Status.FAILURE end
    priority = priority or Support.QueuePriorities.DEFAULT
    if d.queue_position_spell then
        if d:queue_position_spell(spell_key, position, priority, action_id, mode) then
            return Status.SUCCESS
        end
        return Status.FAILURE
    end
    local spell_id = Support.spell_id_for(blackboard, spell_key, mode)
    if not spell_id then return Status.FAILURE end
    if d:queue_position(action_id, spell_id, position, priority, action_id) then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

return Support
