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
--
-- ===========================================================================================
-- WHAT THIS GUARD CANNOT SEE. Stated because the last three defects in this phase were each
-- RIGHT ABOUT WHAT THEY SAW AND WRONG ABOUT WHAT THEY LOOKED AT. Every item below is measured,
-- not assumed.
-- ===========================================================================================
--
--   1. WRITES THAT DO NOT GO THROUGH `set`. `bb._data[key] = handle` stores it. `_data` is a
--      plain field on a plain table and nothing seals it. This guard is a front door, not a
--      wall.
--
--   2. MUTATION AFTER ACCEPTANCE -- the direct price of not copying. `local t = {}` accepted
--      clean, then `t.unit = handle` a line later, and the blackboard now holds a handle it
--      approved when it did not. Closing this needs a read-side proxy, and LuaJIT's
--      `__newindex` fires only for ABSENT keys, so on 5.1 that proxy breaks `pairs()`. Same
--      wall snapshot.lua documents.
--
--   3. LEDGERED KEYS ARE NOT SCANNED AT ALL. An exception is total, not partial: while
--      `player.object` is ledgered it may hold anything at any depth. The ledger trades
--      coverage for a migration path, which is the whole point of phasing it -- but an
--      exception is a hole for as long as it exists.
--
--   4. CODE PATHS THE OFFLINE SUITE NEVER EXECUTES. A runtime guard only ever inspects values
--      that some run actually produces. Measured: the suite sets `combat.low_health_add` 32
--      times and never once with a handle, because its mock adds are plain tables, while in the
--      client it holds a live unit. That entry was put in the ledger by reading the writer, not
--      by observing a run -- and a ledger harvested from runs alone would have shipped a guard
--      that threw in-game on a path no test covers.
--
--   5. THE RATCHET'S EVIDENCE IS TEXTUAL. It proves a `set("<key>", …)` line still exists, not
--      that the value at that line is still a handle. A key that quietly changed from a handle
--      to a scalar, keeping its name and its write site, keeps its exception alive on false
--      pretences. It fails in the safe direction -- an exception outliving its need is a
--      to-do, not a hole -- but it is not proof.
--
--   6. THE LEDGER ENUMERATES KEYS READ ACROSS A PACKAGE BOUNDARY, NOT KEYS THE GUARD REFUSES.
--      Those are DIFFERENT SETS, and the difference is not academic: it is why combat was dead
--      in every real boot for a whole phase.
--
--      The list was harvested from the cross-namespace READ audit in
--      tests/kernel/test_blackboard_namespace_audit.lua. `module.combat.izi_bridge` was written
--      by combat and, at the time, believed to be read only inside combat -- so no
--      cross-namespace finding ever named it, and it was never a candidate for this list. The
--      guard then refused it on the FIRST line of `SentinelCombat:initialize()`,
--      `initialize_all` swallowed the throw, and no test noticed because every combat suite
--      constructs SentinelCombat directly. A key can be refused by the guard and invisible to
--      the audit that seeds the ledger AT THE SAME TIME, and that combination is silent in both
--      directions.
--
--      The general shape: a private key that carries behaviour needs an entry just as much as a
--      shared one, and the only thing that produces such an entry today is a human reading a
--      writer. Nothing derives this list from what `assert_pure` would actually reject.
--
--   7. A DECLARED READER LIST USED TO BE CHECKED FOR EXISTENCE, NOT FOR TRUTH -- and while it
--      was, it was wrong. `module.combat.izi_bridge` named the two target strategies as its
--      readers; NEITHER reads that key (both take the bridge by constructor), and the six files
--      that really read it were named by nobody. The entry's retirement plan followed from the
--      false list and was impossible to execute, because four of the six real readers are handed
--      a blackboard and nothing else. Re-measuring in Phase 4d found the same error, less
--      dramatically, in three more entries: `player.object` declared 7 readers of 22,
--      `player.target` 6 of 16, `combat.target` 9 of 16.
--
--      `test_every_ledger_entry_names_its_readers_accurately` now asserts both directions. What
--      IT cannot see is stated at that test: it excludes `sentinel/tests`, so "no readers" means
--      "no readers in production", and it matches `get("<key>"` textually, so a read through a
--      computed key name is invisible to it.
--
-- The depth limit and the metatable check fail CLOSED: unproven means refused, so neither is a
-- blind spot. Items 1 and 2 are structural and need Phase 3's sealed public API. Item 3 shrinks
-- as the ledger does. Item 4 is why the `.object` audit is kept as a backstop -- it reads
-- source text, so it sees what no run reaches, for the one spelling it knows. Item 6 is the one
-- with no mechanism behind it at all: the only defence is that a refused write throws loudly at
-- the writer, which is worth nothing while a caller pcalls it into silence.

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
    -- READER LISTS BELOW WERE RE-MEASURED IN PHASE 4D D1, AND THEY WERE WRONG.
    --
    -- `player.object` declared 7 readers and has 22. `player.target` declared 6 and has 16.
    -- `combat.target` declared 9 and has 16. Nothing had ever compared a declared list against the
    -- tree, so every `retire` estimate below ("largest reader set", "smallest -- retire first") was
    -- an ordering derived from lists that were roughly a third of the truth.
    -- `test_every_ledger_entry_names_its_readers_accurately` now checks both directions.
    ["player.object"] = {
        kind = "sdk_handle",
        writers = { "sentinel/runtime/sensors/player_sensor.lua" },
        readers = {
            "sentinel/modules/combat/action_library.lua",
            "sentinel/modules/combat/combat_zone_detector.lua",
            "sentinel/modules/combat/condition_library.lua",
            "sentinel/modules/combat/context_builder.lua",
            "sentinel/modules/combat/module.lua",
            "sentinel/modules/combat/profiles/paladin/retribution_actions.lua",
            "sentinel/modules/combat/profiles/paladin/retribution_conditions.lua",
            "sentinel/modules/combat/profiles/warlock/pet_controller.lua",
            "sentinel/modules/combat/shared_subtrees.lua",
            "sentinel/modules/combat/strategies/default_target_strategy.lua",
            "sentinel/modules/combat/strategies/grind_target_strategy.lua",
            "sentinel/modules/combat/swing_tracker.lua",
            "sentinel/rotations/mage_frost/frost_actions.lua",
            "sentinel/rotations/mage_frost/frost_combat_state.lua",
            "sentinel/rotations/mage_frost/frost_conditions.lua",
            "sentinel/rotations/mage_frost/frost_support.lua",
            "sentinel/rotations/mage_frost/frost_tbc.lua",
            "sentinel/rotations/mage_frost/kite_controller.lua",
            "sentinel/rotations/mage_frost/pet_controller.lua",
            "sentinel/runtime/app.lua",
            "sentinel/runtime/sensors/aura_sensor.lua",
            "sentinel/shared/combat_helpers.lua",
        },
        retire = "app.lua already feeds SnapshotSource.capture_player() FROM this key, so the "
            .. "snapshot path exists -- readers move to snapshot player fields and the sensor "
            .. "stops publishing the handle. 22 readers, the largest set of any entry, and 16 of "
            .. "them reach it through `shared/combat_helpers.player_and_target` or its mage_frost "
            .. "twin `frost_support.player_and_target` -- so those two helpers are the real "
            .. "migration surface, not 22 call sites. Retire last.",
    },
    ["player.target"] = {
        kind = "sdk_handle",
        writers = { "sentinel/runtime/sensors/player_sensor.lua" },
        readers = {
            "sentinel/modules/combat/action_library.lua",
            "sentinel/modules/combat/condition_library.lua",
            "sentinel/modules/combat/context_builder.lua",
            "sentinel/modules/combat/module.lua",
            "sentinel/modules/combat/shared_subtrees.lua",
            "sentinel/modules/combat/strategies/default_target_strategy.lua",
            "sentinel/modules/combat/strategies/grind_target_strategy.lua",
            "sentinel/modules/combat/swing_tracker.lua",
            "sentinel/rotations/mage_frost/frost_actions.lua",
            "sentinel/rotations/mage_frost/frost_combat_state.lua",
            "sentinel/rotations/mage_frost/frost_conditions.lua",
            "sentinel/rotations/mage_frost/frost_support.lua",
            "sentinel/rotations/mage_frost/kite_controller.lua",
            "sentinel/runtime/app.lua",
            "sentinel/runtime/sensor_hub.lua",
            "sentinel/shared/combat_helpers.lua",
        },
        retire = "Snapshot target fields plus the symbolic UNIT_TARGET ref. Almost every reader is "
            .. "a `get(\"combat.target\") or get(\"player.target\")` fallback pair, so this "
            .. "retires together with combat.target or not at all.",
    },
    ["combat.target"] = {
        kind = "sdk_handle",
        writers = { "sentinel/modules/combat/module.lua" },
        readers = {
            "sentinel/modules/combat/action_library.lua",
            "sentinel/modules/combat/condition_library.lua",
            "sentinel/modules/combat/context_builder.lua",
            "sentinel/modules/combat/module.lua",
            "sentinel/modules/combat/shared_subtrees.lua",
            "sentinel/modules/combat/strategies/default_target_strategy.lua",
            "sentinel/modules/combat/strategies/grind_target_strategy.lua",
            "sentinel/modules/combat/swing_tracker.lua",
            "sentinel/rotations/mage_frost/frost_actions.lua",
            "sentinel/rotations/mage_frost/frost_combat_state.lua",
            "sentinel/rotations/mage_frost/frost_conditions.lua",
            "sentinel/rotations/mage_frost/frost_support.lua",
            "sentinel/rotations/mage_frost/frost_tbc.lua",
            "sentinel/rotations/mage_frost/kite_controller.lua",
            "sentinel/runtime/app.lua",
            "sentinel/shared/combat_helpers.lua",
        },
        retire = "The selected target becomes a snapshot-derived record (guid + scalars) plus "
            .. "UNIT_TARGET for intents. Paired with player.target above -- the two share 14 of "
            .. "their 16 readers, because the fallback pair is written as one expression.",
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
        },
        retire = "mage_frost's reader is GONE (Phase 4c D4): its casts leave as `cast` intents and "
            .. "the package no longer references a dispatcher at all. One reader left, in "
            .. "shared/combat_helpers.lua -- the cheapest collaborator to retire.",
    },
    -- `module.combat.izi_bridge` WAS HERE, added in Phase 4c and RETIRED in Phase 4d D1. Its two
    -- lives are the two blind spots documented above this table, so it is recorded rather than
    -- silently deleted:
    --
    --   * IT WAS NOT LISTED WHEN IT SHOULD HAVE BEEN (blind spot 6 below). The guard refused it,
    --     `SentinelCombat:initialize()` threw on its first statement, `initialize_all` swallowed the
    --     error, and combat was dead in every real boot from Phase 4b D3 until Phase 4c -- with no
    --     test seeing it, because every combat suite constructs SentinelCombat directly.
    --   * ITS READER LIST WAS WRONG WHEN IT WAS LISTED (blind spot 7 below). It named the two target
    --     strategies, which receive the bridge BY CONSTRUCTOR and never read this key at all. The
    --     six real readers were condition_library (x3), retribution_conditions, frost_combat_state
    --     and frost_conditions -- four of which cannot be reached by constructor, which is why the
    --     retirement plan built on that false premise could not have worked.
    --
    -- Retired by MOVING THE STORAGE, not by widening the guard: the bridge is now published as
    -- `Sentinel.forecast` (kernel/forecast.lua) and the write in modules/combat/module.lua is gone.
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

    -- `pairs` walks the RAW table, so it cannot see through `__index`. A handle reached by
    -- metamethod is invisible to the scan above: `setmetatable({}, {__index = handle})` has no
    -- fields at all and would otherwise pass as an empty table. A metatable is also how
    -- `__call` smuggles behaviour into something that is not of type "function". Refusing it
    -- outright costs nothing measurable -- every metatable-carrying value on the blackboard
    -- today sits under an already-ledgered key -- and closes the only evasion the field walk
    -- has.
    if getmetatable(value) ~= nil then
        error(string.format(
            "blackboard set refused %s: the table carries a metatable, and `pairs` cannot see "
            .. "through `__index`, so the guard cannot prove it holds no handle -- a handle "
            .. "served by a metamethod would read as an empty table (ADR 08 §2.7). Store plain "
            .. "data, or add the key to Blackboard.HANDLE_LEDGER with a writer, a reader and a "
            .. "retirement plan.", describe_path(key, path)), 0)
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
