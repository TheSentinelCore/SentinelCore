local Schema = require("core/blackboard_schema")

local Blackboard = {}
Blackboard.__index = Blackboard

-- ===========================================================================
-- NO KEY MAY HOLD A LIVE SDK HANDLE (ADR 08 §2.7)
-- ===========================================================================
--
-- "Every game_object is a raw 8-byte pointer into game memory that can become invalid
--  BETWEEN USES." A handle parked in shared state is therefore not stale data one tick
-- later, it is undefined behaviour -- and the read that uses it looks exactly like an
-- ordinary blackboard read.
--
-- WHY THIS IS A GUARD AND NOT A LINT.
-- The audit in tests/kernel/test_blackboard_namespace_audit.lua detected handles by matching
-- keys ending in `.object`. That is a rule about SPELLING, and `combat.target`,
-- `player.target` and `combat.low_health_add` held live handles under names it had never
-- agreed to look at. Widening the pattern only moves the blind spot to the next name nobody
-- thought of. So the check no longer asks what a key is CALLED -- it asks what the value
-- CONTAINS, and refuses anything carrying behaviour: userdata, functions, threads, or a
-- table holding one at any depth. That is what every handle looks like, in the client and in
-- the offline mocks alike, and it cannot be evaded by renaming.
--
-- DELIBERATELY NOT A COPY, UNLIKE kernel/snapshot.lua.
-- `snapshot.lua:copy_value` runs the same taxonomy but deep-copies what it accepts, because a
-- snapshot must own its data for the tick. The blackboard is the opposite thing: LIVE,
-- mutable, read-through state that callers legitimately mutate in place. Copying here would
-- make every `bb:get(k).field = v` in the codebase silently write to a discarded table. So
-- this INSPECTS and stores the original, and it tolerates cycles in plain data -- the
-- snapshot refuses those only because it has to walk them twice.
--
-- The two implementations are kept separate because `core/` may not require `kernel/` (the
-- dependency runs one way only, kernel -> core). They are pinned against drift by a
-- conformance test in tests/kernel/test_blackboard_handle_guard.lua rather than by sharing
-- code across that boundary.

local MAX_DEPTH = 8

--- Keys still permitted to hold a handle, and the worklist for removing them.
---
--- SHRINK-ONLY. An entry whose writer no longer sets the key fails exactly as loudly as a key
--- that holds a handle without being listed -- see `test_the_ledger_is_shrink_only`. A ledger
--- that only catches new violations is a list, not a ratchet; the staleness direction is what
--- makes the exception expire with its reason.
---
--- `writers` is evidence, not documentation: the ratchet reads those files back and fails if
--- none of them still names the key. A key is retired when NO writer names it, so a package
--- dropping one of two writers correctly does NOT retire the entry.
---
--- `kind` separates two populations the guard cannot tell apart, because both "carry
--- behaviour":
---
---   sdk_handle   -- a live game_object. ADR 08 §2.7: the pointer can become invalid BETWEEN
---                   USES, so a read one tick later is undefined behaviour, not stale data.
---                   These are the dangerous ones and the reason the guard exists.
---   collaborator -- a pure-Lua service object or behaviour tree. It does not die between
---                   ticks, so it is not unsound -- it is shared-state coupling: a module
---                   handing another module a live reference through a global side channel
---                   rather than through the public API. Lower risk, still on the worklist.
Blackboard.HANDLE_LEDGER = {
    -- =======================================================================
    -- sdk_handle -- live game pointers. Retiring these is the safety work.
    -- =======================================================================
    ["player.object"] = {
        kind = "sdk_handle",
        writers = { "sentinel/runtime/sensors/player_sensor.lua" },
        readers = {
            "sentinel/runtime/sensors/aura_sensor.lua",
            "sentinel/runtime/app.lua",
            "sentinel/modules/combat/action_library.lua",
            "sentinel/modules/combat/condition_library.lua",
            "sentinel/modules/combat/strategies/default_target_strategy.lua",
            "sentinel/modules/combat/strategies/grind_target_strategy.lua",
            "sentinel/modules/combat/profiles/paladin/retribution_actions.lua",
        },
        retire = "app.lua already feeds SnapshotSource.capture_player() FROM this key, so the "
            .. "snapshot path exists -- readers move to snapshot player fields and the sensor "
            .. "stops publishing the handle. Largest reader set; retire last.",
    },
    ["player.target"] = {
        kind = "sdk_handle",
        writers = { "sentinel/runtime/sensors/player_sensor.lua" },
        readers = {
            "sentinel/runtime/sensor_hub.lua",
            "sentinel/modules/combat/action_library.lua",
            "sentinel/modules/combat/context_builder.lua",
            "sentinel/modules/combat/strategies/default_target_strategy.lua",
            "sentinel/modules/combat/strategies/grind_target_strategy.lua",
            "sentinel/rotations/mage_frost/kite_controller.lua",
        },
        retire = "Snapshot target fields plus the symbolic UNIT_TARGET ref. Every reader is a "
            .. "`get(\"combat.target\") or get(\"player.target\")` fallback pair, so this "
            .. "retires together with combat.target or not at all.",
    },
    ["combat.target"] = {
        kind = "sdk_handle",
        writers = { "sentinel/modules/combat/module.lua" },
        readers = {
            "sentinel/modules/combat/action_library.lua",
            "sentinel/modules/combat/context_builder.lua",
            "sentinel/modules/combat/strategies/default_target_strategy.lua",
            "sentinel/modules/combat/strategies/grind_target_strategy.lua",
            "sentinel/rotations/mage_frost/frost_actions.lua",
            "sentinel/rotations/mage_frost/frost_combat_state.lua",
            "sentinel/rotations/mage_frost/frost_conditions.lua",
            "sentinel/rotations/mage_frost/frost_support.lua",
            "sentinel/rotations/mage_frost/frost_tbc.lua",
        },
        retire = "The selected target becomes a snapshot-derived record (guid + scalars) plus "
            .. "UNIT_TARGET for intents. Paired with player.target above.",
    },
    ["combat.low_health_add"] = {
        kind = "sdk_handle",
        writers = { "sentinel/rotations/mage_frost/frost_combat_state.lua" },
        readers = {
            "sentinel/rotations/mage_frost/frost_actions.lua",
            "sentinel/rotations/mage_frost/frost_conditions.lua",
        },
        -- THIS ENTRY IS WHY THE LEDGER CANNOT BE BUILT FROM TEST RUNS ALONE. The offline
        -- suite sets this key 32 times and NEVER with a handle -- its mock adds are plain
        -- tables. In the client `best_add = enemy`, a live unit from the enemy scan. A ledger
        -- harvested only from what the suite executes would have omitted it, and the guard
        -- would have thrown in-game on a path no test covers.
        retire = "Smallest reader set of the four -- retire FIRST. frost_conditions only asks "
            .. "`~= nil` and frost_actions only needs a cast target, so a guid plus a health "
            .. "percentage replaces the handle outright.",
    },

    -- =======================================================================
    -- collaborator -- pure-Lua objects. Coupling, not undefined behaviour.
    -- =======================================================================
    ["module.combat.catalog"] = {
        kind = "collaborator",
        writers = { "sentinel/modules/combat/module.lua" },
        readers = {
            "sentinel/modules/combat/context_builder.lua",
            "sentinel/modules/combat/condition_library.lua",
            "sentinel/modules/combat/spell_dispatcher.lua",
            "sentinel/modules/combat/profiles/warlock/affliction_conditions.lua",
            "sentinel/rotations/mage_frost/frost_combat_state.lua",
            "sentinel/rotations/mage_frost/frost_conditions.lua",
            "sentinel/rotations/mage_frost/frost_support.lua",
            "sentinel/rotations/mage_frost/frost_tbc.lua",
            "sentinel/shared/combat_helpers.lua",
        },
        retire = "kernel/catalogs/spell already exists. Rotations reach it through the plugin "
            .. "API surface instead of a blackboard key.",
    },
    ["module.combat.cooldowns"] = {
        kind = "collaborator",
        writers = { "sentinel/modules/combat/module.lua" },
        readers = {
            "sentinel/modules/combat/condition_library.lua",
            "sentinel/modules/combat/profiles/paladin/retribution_conditions.lua",
            "sentinel/rotations/mage_frost/frost_combat_state.lua",
            "sentinel/rotations/mage_frost/frost_conditions.lua",
        },
        retire = "Pass the cooldown service on the rotation context the kernel already builds, "
            .. "rather than parking it in shared state for anyone to find.",
    },
    ["module.combat.dispatcher"] = {
        kind = "collaborator",
        writers = { "sentinel/modules/combat/module.lua" },
        readers = {
            "sentinel/shared/combat_helpers.lua",
            "sentinel/rotations/mage_frost/frost_support.lua",
        },
        retire = "Only two readers, and both are already thin accessors that do nothing but "
            .. "return it -- the cheapest collaborator to retire.",
    },
    ["module.combat.pet_controller"] = {
        kind = "collaborator",
        writers = {
            "sentinel/rotations/mage_frost/frost_tbc.lua",
            "sentinel/modules/combat/profiles/warlock/affliction_tbc.lua",
        },
        readers = {
            "sentinel/modules/combat/action_library.lua",
            "sentinel/modules/combat/condition_library.lua",
            "sentinel/modules/combat/module.lua",
            "sentinel/rotations/mage_frost/frost_actions.lua",
            "sentinel/rotations/mage_frost/frost_combat_state.lua",
            "sentinel/rotations/mage_frost/frost_conditions.lua",
        },
        retire = "A rotation publishes its controller for the shared action library to call "
            .. "back into -- an inverted dependency. Belongs on the pet capability the control "
            .. "broker now owns.",
    },
    ["module.combat.profile"] = {
        kind = "collaborator",
        writers = { "sentinel/modules/combat/module.lua" },
        readers = {},
        -- Also the only entry that trips the depth limit rather than the behaviour check: a
        -- compiled behaviour tree nests past MAX_DEPTH before any closure is reached.
        retire = "WRITE-ONLY: `module.combat.profile` has ZERO readers anywhere in the repo, "
            .. "tests included. Deleting the three set() calls in modules/combat/module.lua "
            .. "retires this entry with no reader migration at all. Retire first of all nine.",
    },
}

local function describe_path(key, path)
    if #path == 0 then return "'" .. tostring(key) .. "'" end
    return "'" .. tostring(key) .. "' at ." .. table.concat(path, ".")
end

--- Refuse any value carrying behaviour, at any depth. Inspects only -- never copies.
--- @error string when the value is (or contains) a handle
local function assert_pure(value, key, depth, seen, path)
    local t = type(value)

    if t == "nil" or t == "number" or t == "string" or t == "boolean" then
        return
    end

    if t == "function" or t == "userdata" or t == "thread" then
        error(string.format(
            "blackboard set refused %s: a %s carries behaviour, and the blackboard stores "
            .. "VALUES only (ADR 08 §2.7 -- a game_object pointer can become invalid between "
            .. "uses, so a handle read from shared state is undefined behaviour, not stale "
            .. "data). Store a snapshot-derived scalar, or add the key to "
            .. "Blackboard.HANDLE_LEDGER with a writer, a reader and a retirement plan.",
            describe_path(key, path), t), 0)
    end

    if t ~= "table" then
        error(string.format("blackboard set refused %s: unsupported type '%s'",
            describe_path(key, path), t), 0)
    end

    if depth > MAX_DEPTH then
        error(string.format("blackboard set refused %s: nested deeper than %d levels, so the "
            .. "guard cannot prove it holds no handle", describe_path(key, path), MAX_DEPTH), 0)
    end

    -- A cycle in plain data is not a handle, and nothing is copied here, so it is safe to
    -- store -- it only has to be walked once.
    if seen[value] then return end
    seen[value] = true

    for k, v in pairs(value) do
        path[#path + 1] = tostring(k)
        assert_pure(v, key, depth + 1, seen, path)
        path[#path] = nil
    end
end

Blackboard._assert_pure = assert_pure

function Blackboard:new()
    local o = setmetatable({}, Blackboard)
    o._data = {}
    return o
end

function Blackboard:get(key, default)
    local value = self._data[key]
    if value == nil then
        return default
    end
    return value
end

function Blackboard:set(key, value)
    local ok, err = Schema.validate_key(key)
    if not ok then
        error("blackboard set rejected: " .. tostring(err) .. " for key " .. tostring(key))
    end
    if not Blackboard.HANDLE_LEDGER[key] then
        assert_pure(value, key, 0, {}, {})
    end
    self._data[key] = value
end

function Blackboard:clear(key)
    self._data[key] = nil
end

function Blackboard:has(key)
    return self._data[key] ~= nil
end

-- `Blackboard:snapshot(prefix)` was REMOVED in Phase 1 and superseded by
-- `kernel/snapshot.lua`. ADR 08 §5.1 already recorded that it had zero callers, but dead
-- code was not the reason it had to go: it returned a SHALLOW copy of live blackboard
-- state, and this blackboard holds `player.object` -- a raw game_object handle written by
-- runtime/sensors/player_sensor.lua. It therefore produced precisely the artefact ADR 08
-- §2.7 forbids (a "snapshot" holding a pointer that can die inside the tick that froze it),
-- under a name that invited exactly the trust it could not honour.
--
-- The blackboard remains what it is: LIVE, mutable, read-through state. Anything that needs
-- a consistent view for the duration of a tick uses kernel/snapshot.lua.

return Blackboard
