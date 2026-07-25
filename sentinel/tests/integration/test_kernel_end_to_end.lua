-- tests/integration/test_kernel_end_to_end.lua
-- ONE REAL PATH, END TO END. Phase 4c Deliverable 5.
--
-- ================================================================================
-- WHY THIS FILE IS THE PHASE
-- ================================================================================
-- Everything the kernel had before this was driven by doubles. Seven stages, six intent types,
-- eight channels, leases, gates, a frozen snapshot and a tri-state -- every one of them tested, and
-- not one of them ever reached by production code running as production code. ADR 08 §13.1 item 15
-- states it plainly: "Nothing in production emits an intent."
--
-- So this test drives a REAL `SentinelApp` through REAL ticks and asserts that the frost rotation:
--
--   1. reads the tick's frozen snapshot through `Sentinel.snapshot`,
--   2. evaluates a `Sentinel.cond` predicate that answers in `Truth`,
--   3. acquires a CASTING lease from the real ControlBroker,
--   4. emits a `cast` intent,
--   5. and that intent commits through the real gates and reaches the SDK.
--
-- ================================================================================
-- WHERE THE DOUBLES ARE
-- ================================================================================
-- At the SDK boundary and NOWHERE ELSE. Four things are faked, and all four are the injector:
--
--   * `_G.core`                                -- object manager, input, clocks, log
--   * `_G.spell_helper`                        -- the spell-book helper the castable gate asks
--   * `common/modules/spell_queue`             -- via `package.loaded`, because `app.lua` resolves it
--                                                 through a guarded `require` that fails offline
--   * the `game_object` handles themselves     -- there is no game
--
-- Above that line everything is the shipping object: `SentinelApp:new()`, its Scheduler, its
-- ControlBroker, its IntentQueue and gates, its ModuleRegistry, the real combat module, the real
-- `ProfileRegistry` picking Mage by numeric class id, and the real `rotations/mage_frost` package
-- reaching the kernel only through `_G.Sentinel`.
--
-- ================================================================================
-- PHASE 4d: THE TWO HALVES ARE NOW JOINED (D7), AND THE TARGET PIN IS REAL (D4)
-- ================================================================================
-- This header used to admit that the snapshot half and the cast half were pinned SEPARATELY: tests
-- 1-2 proved a `Sentinel.cond` predicate answers off a live snapshot, tests 3-5 proved a lease
-- becomes a packet, and nothing connected them. Test 7 now drives one continuous chain --
-- snapshot -> predicate -> lease -> intent -> COMMIT -> gates -> SDK -- with the blackboard
-- deliberately made to CONTRADICT the snapshot, so the chain is red if the health gate ever
-- regresses to a blackboard read. Measured: reverting `Cond.health_below` to that read turns two of
-- the four Phase 4d tests red and leaves the rest of the suite green.
--
-- Test 6 replaces a false green. `test_app_tick.lua` claimed to pin that the cast executor receives
-- the app's target resolution; it exercised the RESOLVER in isolation and stayed green with the
-- `unit_target` assignment deleted from `runtime/app.lua`. Test 6 asserts the PACKET at the SDK
-- boundary and goes red under exactly that edit.
--
-- ================================================================================
-- WHAT THIS PIN CANNOT SEE
-- ================================================================================
-- Stated because a check believed for more than it covers is how this tree got `snapshot` claimed
-- for three phases.
--
--  1. THE INJECTOR'S ACTUAL BEHAVIOUR. `queue_spell_target` returning true here means the double was
--     called with plausible arguments. Whether the client casts anything is not observable offline,
--     and no assertion in this file should be read as evidence that it does.
--  2. TICK CADENCE AND TIMING. `core.time` is scripted. Nothing here measures whether the frame
--     budget is realistic or whether the GCD estimate matches the server. ADR 08 §13 q7 is still
--     open and still needs a live client.
--  3. THE PRODUCTION DRIVE PATH BEYOND COMBAT. Combat still reaches the rotation through
--     `ModuleRegistry`, not through the Phase 3 plugin registry -- that is D3. What this proves is
--     that the CAST PATH is real, not that the LOAD path is final.
--  4. EVERY OTHER ACTION. Two casts commit here (an armour buff and Cold Snap). The other 36 sites
--     share the two converted helpers and are covered at outcome level in
--     test_frost_cast_intents.lua, but this file drives two.
--  5. THE SIXTEEN UNCONVERTED CONDITIONS. Only `health_below`/`health_above` read the snapshot. The
--     rest still read the blackboard, so "the rotation reads the snapshot" is true of the health
--     gate and of nothing else yet -- and the chain in test 7 is therefore ONE condition wide.
--  6. THE SYMBOLIC UNIT VOCABULARY IS PINNED FROM A HAND-BUILT INTENT, NOT FROM THE ROTATION. It
--     has to be: `frost_support.name_unit` converts every frost cast to a guid, which
--     short-circuits `resolve_unit` before `deps.unit_target` is ever consulted. Test 6 proves the
--     KERNEL resolves `"target"` correctly; it says nothing about where a Frostbolt lands.
--  7. NO GATE REFUSAL IN THIS FILE IS ROTATION-DRIVEN. `Cond.spell_ready` asks the same SDK
--     predicate one stage before the `castable` gate does, by design (kernel/spells.lua's header),
--     so a spell the SDK refuses never becomes an intent at all. The gate is therefore driven by a
--     direct submission, and "the gate refuses" is proven while "the rotation can provoke the gate"
--     is not -- because it cannot.
--  8. THE BLACKBOARD DIVERGENCE IS AN INSTRUMENT, AND INSTRUMENTS DRIFT. Test 7 plants a false
--     `player.health_pct` in ARBITRATE. That is only sound while `player_sensor.lua:63` is the sole
--     writer of that key; a second writer during ACT would silently erase the lie and take the
--     evidence with it. The tests assert the planted value back for that reason.

local SentinelApp = require("runtime/app")
local Bands = require("kernel/bands")
local Executors = require("kernel/intent_executors")
local T = require("tests/test_util")

local M = {}

local MAGE_CLASS_ID = 8

--- The three auras that SILENCE THE MAINTENANCE TREE, by real TBC spell id.
---
--- `maintenance_tree.lua` opens on any character missing armour or Arcane Intellect, and it runs
--- ahead of everything else in every state including IDLE -- so a test that wants the rotation
--- quiet, or wants a LATER branch reached, has to give the character the buffs a level-70 mage
--- would actually be carrying. These are the ids `frost_conditions.lua:33-35` matches:
---
---     27124  Ice Armor (rank 5)        -> closes `ensure_ice_armor`
---     27126  Arcane Intellect (rank 6) -> closes `ensure_arcane_intellect`
---      7301  Frost Armor (rank 3)      -> closes `ensure_frost_armor`
---
--- Not a contrivance and not a stub: this is a buffed mage, which is the ordinary case.
local BUFFED = { [27124] = true, [27126] = true, [7301] = true }

-- ---------------------------------------------------------------------------
-- The SDK boundary
-- ---------------------------------------------------------------------------

---A `game_object` double. Only the verbs the sensors and gates actually call.
local function make_unit(opts)
    local unit = {}
    function unit:is_valid() return true end
    function unit:is_unit() return true end
    function unit:is_game_object() return false end
    function unit:is_dead() return false end
    function unit:get_guid() return opts.guid end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:get_health() return opts.health or 100 end
    function unit:get_max_health() return opts.max_health or 100 end
    function unit:get_power() return opts.power or 100 end
    function unit:get_max_power() return opts.max_power or 100 end
    function unit:get_level() return opts.level or 70 end
    function unit:get_class() return opts.class_id end
    function unit:get_race() return 1 end
    function unit:get_target() return opts.target end
    function unit:get_pet() return nil end
    -- Hostility, as the target strategy asks it (`is_enemy_with`, then `can_attack`). Absent by
    -- default, which is why the out-of-combat tests never auto-engage: `_allow_idle_auto_engage`
    -- refuses first, and no unit here would answer yes anyway.
    function unit:is_player() return opts.is_player == true end
    function unit:is_enemy_with() return opts.hostile == true end
    function unit:can_attack() return opts.hostile == true end
    function unit:is_in_combat() return opts.in_combat == true end
    function unit:is_casting_spell() return false end
    function unit:is_channelling_spell() return false end
    function unit:is_moving() return false end
    function unit:is_mounted() return false end
    function unit:is_ghost() return false end
    function unit:is_active_spell_interruptable() return true end
    function unit:get_attack_speed() return 2.0 end
    -- `auras` is a set of REAL TBC spell ids the unit carries. It exists so a test can silence the
    -- maintenance tree, which otherwise opens on every character and casts armour before the
    -- rotation ever reaches a decision further down the priority list. Empty by default, so every
    -- test written before this behaves exactly as it did.
    local auras = opts.auras or {}
    function unit:has_buff(spell_id) return auras[spell_id] == true end
    function unit:get_buff_data(spell_id)
        return { is_active = auras[spell_id] == true, stack_count = auras[spell_id] and 1 or 0 }
    end
    function unit:get_buff_stacks() return 0 end
    function unit:get_buffs() return {} end
    function unit:get_health_percentage()
        return (opts.health or 100) / (opts.max_health or 100)
    end
    return unit
end

---Everything the injector would provide, and nothing above it.
---@param opts table|nil { health_pct?, in_combat? }
---@return table sdk { packets, player, target, restore }
local function install_sdk(opts)
    opts = opts or {}

    local saved = {
        core = _G.core,
        spell_helper = _G.spell_helper,
        sentinel = _G.Sentinel,
        pending = _G.__SentinelPending,
        spell_queue = package.loaded["common/modules/spell_queue"],
    }

    local health_pct = opts.health_pct or 1.0
    local target = make_unit({ guid = "guid-target", class_id = 1, in_combat = true,
        position = { x = 12, y = 0, z = 0 }, health = 60, hostile = opts.hostile_target })
    local player = make_unit({
        guid = "guid-player",
        class_id = MAGE_CLASS_ID,
        health = math.floor(health_pct * 100),
        max_health = 100,
        -- `runtime/sensors/player_sensor.lua:32-38` derives `player.mana_pct` from get_power over
        -- get_max_power, so this is the knob that closes the maintenance tree's `conjure_mana_gem`
        -- branch -- the one sequence in that tree with no aura and no `spell_ready` guard, gated
        -- only on `mana_above(0.50)`. Left at full by default, so every test written before this
        -- behaves exactly as it did.
        power = opts.mana_pct and math.floor(opts.mana_pct * 100) or 100,
        max_power = 100,
        in_combat = opts.in_combat == true,
        -- THE CLIENT'S TARGET, which is not the same fact as the rotation's selection. In combat
        -- the two normally agree; `client_target` exists so a test can give the CLIENT a target
        -- while the character is not fighting, which is exactly the divergence ADR 08 §13.1
        -- item 19 is about.
        target = (opts.in_combat or opts.client_target) and target or nil,
        auras = opts.auras,
    })

    -- The one place a packet can leave. Recorded, never asserted as "the client cast".
    local packets = {}
    local spell_queue = {}
    function spell_queue:queue_spell_target(spell_id, unit, priority, message)
        packets[#packets + 1] = { verb = "target", spell_id = spell_id, unit = unit,
            priority = priority, message = message }
        return true
    end
    function spell_queue:queue_spell_target_fast(spell_id, unit, priority, message)
        packets[#packets + 1] = { verb = "target_fast", spell_id = spell_id, unit = unit,
            priority = priority, message = message }
        return true
    end
    function spell_queue:queue_spell_position(spell_id, point, priority, message)
        packets[#packets + 1] = { verb = "position", spell_id = spell_id, point = point,
            priority = priority, message = message }
        return true
    end
    function spell_queue:queue_spell_position_fast(spell_id, point, priority, message)
        packets[#packets + 1] = { verb = "position_fast", spell_id = spell_id, point = point,
            priority = priority, message = message }
        return true
    end
    package.loaded["common/modules/spell_queue"] = spell_queue

    -- The gate's real question. Answered yes by default: the point of the original pin is that a
    -- PERMITTED cast travels the whole way, and a refusal would only prove that a refusal refuses.
    --
    -- Two knobs were added for the Phase 4d cases, both spelled as the injector spells them:
    --
    --   * `uncastable` -- a set of spell ids this character cannot cast right now. Used to close the
    --     off-GCD branches that sit ABOVE the one under test in the frost priority list, without
    --     inventing a cooldown model the SDK does not expose. A frost mage who took Cold Snap but
    --     not Ice Barrier or Icy Veins is an ordinary character, not a contrivance.
    --   * `castable = false` -- the whole helper says no. This is the SDK saying "out of range, out
    --     of line of sight, or not known", and it is what the castable gate is FOR.
    --
    -- METHOD-CALL CONVENTION. `shared/spell_helper.lua` invokes this through `call_method`, so the
    -- helper itself arrives as the first argument and `spell_id` as the second. Writing
    -- `function(spell_id)` here reads the helper table as the id and silently matches nothing.
    local uncastable = opts.uncastable or {}
    _G.spell_helper = {
        is_spell_castable = function(_self, spell_id)
            if opts.castable == false then return false end
            return uncastable[spell_id] ~= true
        end,
        is_spell_in_line_of_sight = function() return true end,
        get_spell_cooldown = function() return 0 end,
    }

    local clock = { ms = 0 }
    _G.core = {
        object_manager = {
            get_local_player = function() return player end,
            get_all_objects = function() return { player, target } end,
            get_object_from_guid = function(guid)
                if guid == "guid-player" then return player end
                if guid == "guid-target" then return target end
                return nil
            end,
            GetUnits = function() return {} end,
        },
        input = setmetatable({}, { __index = function() return function() return true end end }),
        quests = setmetatable({}, { __index = function() return function() return false end end }),
        inventory = setmetatable({}, { __index = function() return function() return 0 end end }),
        time = function() return clock.ms / 1000 end,
        game_time = function() return clock.ms end,
        log = function() end,
        log_error = function() end,
        geometry = {
            distance = function(a, b)
                if not a or not b then return math.huge end
                return math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2)
            end,
        },
        read_data_file = function() return nil end,
        write_data_file = function() return true end,
        event_bus = { on = function() return function() end end, off = function() end,
            send = function() end, publish = function() end },
    }

    return {
        packets = packets,
        player = player,
        target = target,
        --- Advance the scripted clock, so the GCD gate sees time pass between ticks.
        advance = function(ms) clock.ms = clock.ms + ms end,
        restore = function()
            _G.core = saved.core
            _G.spell_helper = saved.spell_helper
            _G.Sentinel = saved.sentinel
            _G.__SentinelPending = saved.pending
            package.loaded["common/modules/spell_queue"] = saved.spell_queue
        end,
    }
end

---Stand a real app up over the SDK doubles and drive it.
---@param opts table|nil passed to install_sdk
---@param body function (app, sdk) -> nil
local function with_live_app(opts, body)
    local sdk = install_sdk(opts)
    local ok, err = pcall(function()
        local app = SentinelApp:new()
        app:publish_api()
        app:initialize()
        body(app, sdk)
    end)
    sdk.restore()
    if not ok then error(err, 0) end
end

---Drive `n` real ticks, returning every report.
local function run_ticks(app, sdk, n)
    local reports = {}
    for _ = 1, n do
        sdk.advance(200)   -- well clear of any GCD, so a cast is never held for timing
        reports[#reports + 1] = app:on_update()
    end
    return reports
end

-- ---------------------------------------------------------------------------
-- The Phase 4d chain fixture
-- ---------------------------------------------------------------------------

--- A level-70 frost mage, buffed, in combat, and at 10% health.
---
--- Every entry closes exactly one branch that sits ABOVE `cold_snap_defensive` in the off-GCD
--- selector, and every one of them is an ordinary fact about a character rather than a stub:
---
---     auras = BUFFED          the maintenance tree has nothing to do (it runs ahead of everything)
---     uncastable[33405]       Ice Barrier is not available -> `ice_barrier` closes
---     uncastable[12472]       Icy Veins is not available   -> `icy_veins` closes
---     hostile_target          there is a real enemy, so the module engages instead of idling
---     health_pct = 0.10       `cold_snap_defensive`'s snapshot-backed gate opens
---
--- The two ids are the ranks the DB-baked catalog resolves at level 70, measured against this same
--- harness. A mage who trained Cold Snap but not Ice Barrier, with Icy Veins on cooldown, is not a
--- contrivance -- it is most of levelling.
local WOUNDED_MAGE = {
    in_combat = true,
    health_pct = 0.10,
    hostile_target = true,
    auras = BUFFED,
    uncastable = { [33405] = true, [12472] = true },
}

--- Make the blackboard and the frozen snapshot DISAGREE about health, from ARBITRATE onwards.
---
--- See the section header above test 7 for why. In short: while the two agree, no assertion can
--- tell a snapshot-backed condition from a blackboard-backed one, so the pin would survive
--- reverting the very conversion it exists to protect.
---
--- ARBITRATE is the stage for it: SENSE (stage 1) has already frozen the snapshot and written the
--- key, and ACT (stage 5) has not yet run the rotation. Writing it from ACT would be a race with
--- the module registry handler; writing it from SENSE would be overwritten by the sensor.
---
--- WHAT IT CANNOT SEE: nothing downstream re-derives `player.health_pct` during ACT -- checked, the
--- only writer is `runtime/sensors/player_sensor.lua:63`. If a second writer ever appears the lie
--- would be silently overwritten and these tests would go green for the wrong reason, so the
--- assertion on `blackboard_health` is not decoration.
local function install_health_divergence(app, blackboard)
    app:get_scheduler():register("ARBITRATE", "test.health_divergence", function()
        blackboard:set("player.health_pct", 1.0)
    end)
end

---The first packet the SDK recorded under a given action label, or nil.
local function packet_labelled(sdk, label)
    for _, packet in ipairs(sdk.packets) do
        if packet.message == label then return packet end
    end
    return nil
end

local function all_committed(reports)
    local out = {}
    for _, report in ipairs(reports) do
        for _, intent in ipairs(report.intents and report.intents.committed or {}) do
            out[#out + 1] = intent
        end
    end
    return out
end

local function first_of_type(intents, intent_type)
    for _, intent in ipairs(intents) do
        if intent.type == intent_type then return intent end
    end
    return nil
end

---Every rejection in a tick report, as `type/gate/reason/label`.
---
---A failing assertion that says only "no cast committed" sends the next reader back to the
---debugger; one that says `cast/castable/unit_unresolved` says which of the seven stages refused
---and why. The commit stage already names every refusal (that is what §12's complaint about empty
---catch blocks bought); this only stops the test from throwing that information away.
local function describe_rejections(report)
    local out = {}
    for _, rejection in ipairs(report.intents and report.intents.rejected or {}) do
        local intent = rejection.intent or {}
        out[#out + 1] = string.format("%s/%s/%s(label=%s)",
            tostring(intent.type), tostring(rejection.gate), tostring(rejection.reason),
            tostring(intent.payload and intent.payload.label))
    end
    for _, failure in ipairs(report.intents and report.intents.failed or {}) do
        local intent = failure.intent or {}
        out[#out + 1] = string.format("%s/executor/%s(label=%s)",
            tostring(intent.type), tostring(failure.reason),
            tostring(intent.payload and intent.payload.label))
    end
    if #out == 0 then return "no rejections and no failures -- nothing was submitted" end
    return table.concat(out, ", ")
end

function M.probe_wounded()
    with_live_app({ in_combat = true, health_pct = 0.10, hostile_target = true,
        auras = { [27124] = true, [27126] = true, [7301] = true },
        uncastable = { [33405] = true, [12472] = true } }, function(app, sdk)
        local bb = app:get_blackboard()
        _G.core.log = function(m) print("LOG " .. tostring(m)) end
        app:get_scheduler():register("ACT", "probe.state", function(ctx)
            print(("t%d target=%s dist=%s block=%s"):format(ctx.tick_index,
                tostring(bb:get("combat.target")), tostring(bb:get("combat.target_distance")),
                tostring(bb:get("rotation.last_block_reason"))))
        end)
        local reports = run_ticks(app, sdk, 6)
        for _, r in ipairs(reports) do
            for _, i in ipairs(r.intents.committed) do
                print(("committed t%d %s spell=%s label=%s"):format(r.tick_index, i.type,
                    tostring(i.payload and i.payload.spell_id),
                    tostring(i.payload and i.payload.label)))
            end
            for _, j in ipairs(r.intents.rejected) do
                print(("rejected  t%d %s %s label=%s"):format(r.tick_index,
                    tostring(j.intent and j.intent.type), tostring(j.reason),
                    tostring(j.intent and j.intent.payload and j.intent.payload.label)))
            end
        end
        local H = require("rotations/mage_frost/frost_support")
        for _, key in ipairs({ "cold_snap", "ice_barrier", "icy_veins", "frostbolt", "ice_lance",
                               "frost_nova", "health_potion" }) do
            print(("spell_id_for %-14s = %s"):format(key, tostring(H.spell_id_for(bb, key))))
        end
        print("cooldowns=" .. tostring(bb:get("module.combat.cooldowns"))
            .. " level=" .. tostring(bb:get("player.level"))
            .. " in_combat=" .. tostring(bb:get("player.in_combat"))
            .. " health_pct=" .. tostring(bb:get("player.health_pct")))
        print("combat.target=" .. tostring(bb:get("combat.target"))
            .. " player.target=" .. tostring(bb:get("player.target"))
            .. " sdk.target=" .. tostring(sdk.target))
        for i, p in ipairs(sdk.packets) do
            print(("packet %d verb=%s spell=%s msg=%s unit=%s"):format(
                i, p.verb, tostring(p.spell_id), tostring(p.message), tostring(p.unit)))
        end
    end)
end

function M.probe_healthy()
    with_live_app({ in_combat = true, health_pct = 1.0 }, function(app, sdk)
        run_ticks(app, sdk, 4)
        for i, p in ipairs(sdk.packets) do
            print(("healthy packet %d spell=%s msg=%s"):format(
                i, tostring(p.spell_id), tostring(p.message)))
        end
    end)
end

function M.probe_measure()
    with_live_app(nil, function(app, sdk)
        local bb = app:get_blackboard()
        local broker = app:get_control_broker()
        local sched = app:get_scheduler()
        sched:register("SENSE", "probe.sense", function(ctx)
            print(("SENSE t%d combat.target=%s player.target=%s casting=%s"):format(
                ctx.tick_index, tostring(bb:get("combat.target")),
                tostring(bb:get("player.target")), tostring(broker:who_owns("CASTING"))))
        end)
        sched:register("ACT", "probe.act", function(ctx)
            print(("ACT   t%d combat.target=%s casting=%s"):format(
                ctx.tick_index, tostring(bb:get("combat.target")),
                tostring(broker:who_owns("CASTING"))))
        end)
        local reports = run_ticks(app, sdk, 4)
        for _, r in ipairs(reports) do
            for _, i in ipairs(r.intents.committed) do
                print(("committed t%d %s %s"):format(r.tick_index, i.type, tostring(i.owner)))
            end
            for _, j in ipairs(r.intents.rejected) do
                print(("rejected  t%d %s %s"):format(r.tick_index,
                    tostring(j.intent and j.intent.type), tostring(j.reason)))
            end
        end
        print("packets=" .. #sdk.packets)
    end)
end

-- ---------------------------------------------------------------------------
-- 1. The snapshot is readable from the public surface, during a real tick
-- ---------------------------------------------------------------------------

function M.test_a_real_tick_publishes_a_readable_snapshot_on_the_surface()
    with_live_app({ health_pct = 0.42 }, function(app, sdk)
        run_ticks(app, sdk, 1)

        local snapshot = _G.Sentinel.snapshot
        T.assert_not_nil(snapshot, "Sentinel.snapshot must resolve after a real tick")
        T.assert_true(snapshot:is_frozen())
        T.assert_equal(snapshot:tick_index(), 1)
        T.assert_true(snapshot:get("player.available"),
            "SENSE must have captured the player through the real SnapshotSource")
        T.assert_near(snapshot:get("player.health_pct"), 0.42, 0.0001,
            "and the value must be the one the SDK double reported")
        T.assert_true(snapshot == app:get_scheduler():current_snapshot(),
            "the surface must hand back the scheduler's snapshot, not a second one")
    end)
end

--- The whole reason the retention exists: a plugin holds `_G.Sentinel` across ticks and must read
--- THIS tick's world, not the one that existed when it took the reference.
function M.test_the_surfaces_snapshot_advances_with_each_real_tick()
    with_live_app(nil, function(app, sdk)
        local surface = _G.Sentinel
        run_ticks(app, sdk, 1)
        local first = surface.snapshot:tick_index()
        run_ticks(app, sdk, 1)
        T.assert_equal(surface.snapshot:tick_index(), first + 1,
            "the same reference must resolve the newer snapshot")
    end)
end

-- ---------------------------------------------------------------------------
-- 2. A Sentinel.cond predicate answers in Truth, off that same snapshot
-- ---------------------------------------------------------------------------

function M.test_a_cond_predicate_answers_in_truth_against_the_live_snapshot()
    with_live_app({ health_pct = 0.10 }, function(app, sdk)
        run_ticks(app, sdk, 1)

        local S = _G.Sentinel
        local predicates = S.cond.bind(S.snapshot)
        local verdict = predicates.health_below(0.15)

        T.assert_true(verdict == S.Truth.True,
            "a real snapshot at 10% must answer True to health_below(0.15) -- and answer in Truth")
        T.assert_true(S.Truth.resolve(verdict, S.Truth.Policy.TreatFalse) == true,
            "and must resolve to a decision a behaviour tree can act on")
    end)
end

--- The tri-state earning its keep on real data. `pet.*` is captured by nothing -- there is no pet
--- tier in `snapshot_source.lua` -- so this Unknown comes from a datum the system genuinely lacks
--- rather than from a fixture arranged to produce one.
function M.test_a_predicate_over_data_the_snapshot_does_not_carry_answers_unknown()
    with_live_app(nil, function(app, sdk)
        run_ticks(app, sdk, 1)
        local S = _G.Sentinel
        local predicates = S.cond.bind(S.snapshot)
        T.assert_true(predicates.unit_available(S.cond.UNIT_PET) == S.Truth.Unknown,
            "no pet tier exists, so the honest answer is Unknown, not False")
    end)
end

-- ---------------------------------------------------------------------------
-- 3-5. THE PIN: lease -> intent -> gate -> SDK, inside a real tick
-- ---------------------------------------------------------------------------

--- The frost rotation, running under the real combat module, must emit a `cast` intent that commits.
---
--- Nothing here reaches into the rotation to make it cast. The app is stood up over a Mage, ticked,
--- and the profile decides for itself -- `ProfileRegistry` maps numeric class 8 onto
--- `rotations/mage_frost`, and the maintenance tree opens on a character carrying no armour buff.
function M.test_the_frost_rotation_emits_a_cast_intent_that_commits_through_the_gate()
    with_live_app(nil, function(app, sdk)
        local reports = run_ticks(app, sdk, 3)
        local committed = all_committed(reports)
        local cast = first_of_type(committed, "cast")

        T.assert_not_nil(cast,
            "the rotation must emit a cast intent that survives dedupe, gates and generation check")
        T.assert_equal(cast.owner, "sentinel.rotation.mage_frost",
            "and it must be attributed to the plugin that emitted it")
        T.assert_true(type(cast.payload.spell_id) == "number",
            "carrying a resolved spell id, not a key")
        T.assert_not_nil(cast.generation,
            "and a lease generation -- an unleased intent is refused at commit")
    end)
end

--- The intent is not merely accepted; it reaches the SDK. This is the last link in the chain, and
--- the one that was missing from every green test before this phase.
function M.test_the_committed_cast_reaches_the_spell_queue()
    with_live_app(nil, function(app, sdk)
        run_ticks(app, sdk, 3)

        T.assert_true(#sdk.packets > 0, "a committed cast must produce a packet at the SDK boundary")
        local packet = sdk.packets[1]
        T.assert_true(type(packet.spell_id) == "number")
        T.assert_true(packet.priority == 1 or packet.priority == 7,
            "§6.3: the band must have been mapped onto a spell_queue priority, got "
            .. tostring(packet.priority))
        T.assert_true(type(packet.message) == "string" and packet.message ~= "",
            "and must carry the action's breadcrumb")
    end)
end

--- The lease is real, taken from the real broker, on the channel §6.1 assigns to casting.
---
--- Asserted through the BROKER rather than through the rotation: the plugin claiming it took a lease
--- proves nothing, and the generation validator wired in `SentinelApp:new()` is what actually
--- refuses an unleased cast. So the question asked here is the broker's -- who held CASTING on the
--- tick the cast committed.
function M.test_the_cast_was_authorised_by_a_casting_lease()
    with_live_app(nil, function(app, sdk)
        local broker = app:get_control_broker()
        local holder_when_cast = nil

        for _ = 1, 4 do
            sdk.advance(200)
            local report = app:on_update()
            if first_of_type(report.intents.committed, "cast") then
                holder_when_cast = broker:who_owns("CASTING")
                break
            end
        end

        T.assert_equal(holder_when_cast, "sentinel.rotation.mage_frost",
            "the broker must show CASTING held by the rotation on the tick its cast committed")
    end)
end

--- The committed cast sits in a band the rotation is entitled to.
function M.test_the_cast_carries_a_band_the_rotation_may_claim()
    with_live_app(nil, function(app, sdk)
        local cast = first_of_type(all_committed(run_ticks(app, sdk, 3)), "cast")
        T.assert_not_nil(cast)
        T.assert_true(cast.band >= Bands.BANDS.COMBAT.min,
            "a rotation's cast sits at COMBAT or above, never below")
        T.assert_true(Bands.permits("rotation", Bands.name_for(cast.band)),
            "and in a band §6.2 permits the rotation tier: " .. tostring(Bands.name_for(cast.band)))
    end)
end

-- ---------------------------------------------------------------------------
-- 6. WHICH UNIT DOES `"target"` MEAN? (ADR 08 §13.1 item 19)
-- ---------------------------------------------------------------------------
--
-- ================================================================================
-- WHAT THIS REPLACES, AND WHY THE OLD CHECK WAS A FALSE GREEN
-- ================================================================================
-- `tests/runtime/test_app_tick.lua` asserted `app:unit_target_resolver()(nil) == chosen` under the
-- name "the cast executor is wired to the app's target resolution". It exercised the RESOLVER and
-- never the WIRING: delete the `unit_target = o:unit_target_resolver()` line from
-- `runtime/app.lua`'s `Executors.install` call and that assertion still passed, because nothing in
-- it ever observed the installed deps. A correct helper the executors never receive is the same
-- bug with an extra step -- which is the exact sentence the old test's own docstring used.
--
-- MEASURED, not argued: with the assignment commented out, this test fails on the packet
-- (`guid-target` reaches the SDK instead of `guid-the-mob-the-rotation-chose`) and the old one
-- stays green. That is the whole difference between the two.
--
-- ================================================================================
-- WHY THIS CANNOT RIDE THE FROST CAST PATH
-- ================================================================================
-- It cannot, and the reason is deliberate on both sides. `frost_support.name_unit` converts EVERY
-- frost cast to `{ unit_guid = ... }`, and `resolve_cast_destination` short-circuits into
-- `resolve_unit_by_guid` before `resolve_unit` is ever reached -- so `deps.unit_target` is never
-- consulted on that path at all. Naming a unit by guid is the stronger choice for a cast (it pins
-- the unit the rotation actually chose), and it means the symbolic vocabulary has to be pinned by a
-- caller that genuinely uses it. `pet_command`'s `attack`/`cast` do; a hand-built cast intent, as
-- here, is the smallest thing that does.
--
-- ================================================================================
-- WHAT THIS PIN CANNOT SEE
-- ================================================================================
--   * IT DOES NOT PROVE THE ROTATION IS AIMED CORRECTLY. It proves the KERNEL resolves `"target"`
--     to the app's selection. The frost cast path names units by guid and is covered elsewhere;
--     nothing here says anything about where a Frostbolt lands.
--   * IT DOES NOT PIN THE PRECEDENCE INSIDE `selected_target`. `combat.target` beating
--     `player.target` is `test_app_tick.lua`'s assertion, and it stays there. This pins that the
--     executors ask that function AT ALL.
--   * IT SAYS NOTHING ABOUT `"player"` OR `"pet"`. Those resolve through other branches of
--     `resolve_unit` and neither consults `deps.unit_target`.

--- A cast naming its unit SYMBOLICALLY must commit at the unit the ROTATION selected, not at the
--- one the client happens to have targeted.
---
--- The two are made to DISAGREE on purpose, because they usually agree and the bug only shows when
--- they do not: the character is not fighting, the client still points at a mob from the last pull,
--- and the rotation has selected something else. With `unit_target` unwired the executor falls back
--- to `player:get_target()` and the packet silently leaves at the wrong mob -- nothing throws, no
--- gate refuses, and the tick report reads clean.
function M.test_a_symbolic_cast_commits_at_the_rotations_unit_not_the_clients()
    -- `mana_pct = 0.40` and `auras = BUFFED` between them leave the maintenance tree with nothing
    -- to do; out of combat nothing else in the profile runs, so the CASTING channel is free for
    -- the probe below. Silencing the rotation is not the same as stubbing it -- it is still built,
    -- still ticked, and still reaching its own decisions.
    with_live_app({ client_target = true, auras = BUFFED, mana_pct = 0.40 }, function(app, sdk)
        local bb = app:get_blackboard()
        local broker = app:get_control_broker()
        local rotation_unit = make_unit({ guid = "guid-the-mob-the-rotation-chose", class_id = 1 })
        local submitted = nil

        -- ACT is where §7 says intents are emitted, and this handler is a stand-in for a plugin
        -- that names its unit symbolically. Everything below it -- the lease, the generation stamp,
        -- the gates, the executor, the packet -- is the shipping kernel.
        app:get_scheduler():register("ACT", "test.symbolic_caster", function()
            bb:set("combat.target", rotation_unit)
            local caretaker = broker:acquire({
                channel = "CASTING",
                owner = "test.symbolic_caster",
                band = "COMBAT", offset = 0, tier = "rotation",
                ttl_ticks = 2,
            })
            if not caretaker then
                submitted = "no_lease"
                return
            end
            submitted = caretaker:submit({
                type = "cast",
                payload = {
                    spell_id = 133,
                    unit = Executors.UNIT_TARGET,
                    label = "symbolic_probe",
                },
            })
        end)

        local report = run_ticks(app, sdk, 1)[1]

        -- The premise, asserted rather than assumed: if the client and the rotation agreed, this
        -- test could not tell a correct resolution from a fallback.
        T.assert_true(sdk.player:get_target() == sdk.target,
            "the CLIENT must be pointing at a unit for the fallback to have something to pick")
        T.assert_true(sdk.target ~= rotation_unit,
            "and it must NOT be the rotation's selection, or the two answers are indistinguishable")
        T.assert_true(bb:get("combat.target") == rotation_unit,
            "the rotation's selection must be the one on the blackboard when COMMIT runs")

        T.assert_true(submitted == true,
            "the probe must have taken a real CASTING lease and submitted under it, got "
            .. tostring(submitted))

        local cast = first_of_type(report.intents.committed, "cast")
        T.assert_not_nil(cast, "the symbolic cast must survive every gate: "
            .. describe_rejections(report))
        T.assert_equal(cast.owner, "test.symbolic_caster")

        local packet = nil
        for _, p in ipairs(sdk.packets) do
            if p.message == "symbolic_probe" then packet = p end
        end
        T.assert_not_nil(packet, "and must reach the SDK boundary")
        T.assert_true(packet.unit == rotation_unit,
            "the packet must name the ROTATION's unit -- `unit_target` unwired sends it at the "
            .. "client's instead, which is the silent wrong-mob bug")
        T.assert_true(packet.unit ~= sdk.target,
            "and specifically not `player:get_target()`, which is the executor's own fallback")
    end)
end

-- ---------------------------------------------------------------------------
-- 7. THE WHOLE CHAIN, IN ONE TEST (Phase 4d D7)
-- ---------------------------------------------------------------------------
--
-- ================================================================================
-- THE HOLE THIS CLOSES
-- ================================================================================
-- This file's own header admitted it: the snapshot half and the cast half were both pinned and
-- were not JOINED. Tests 1-2 proved a snapshot exists and that `Sentinel.cond` answers off it;
-- tests 3-5 proved a lease produces an intent that reaches the SDK. Nothing connected the two, so
-- "the rotation reads the snapshot AND that read is what decides the cast" was two true sentences
-- with an unproven `and` in the middle. One test now drives:
--
--     snapshot read -> `Sentinel.cond` predicate -> CASTING lease -> `cast` intent -> COMMIT
--     -> gates -> packet at the SDK.
--
-- ================================================================================
-- THE ROUTE, AND WHY IT IS THIS ONE
-- ================================================================================
-- `frost_tbc.lua`'s `cold_snap_defensive` is the only branch in the profile whose FIRST condition
-- is snapshot-backed: `Cond.health_below(0.30)` goes through `snapshot_predicate`, which binds
-- `Sentinel.cond` to `Sentinel.snapshot` and resolves a `Truth` under `TreatFalse`. Everything
-- above it in the off-GCD selector is closed here by ordinary character facts rather than by
-- stubs -- a mage who took Cold Snap but has neither Ice Barrier nor Icy Veins available is a
-- perfectly ordinary mage.
--
-- ================================================================================
-- THE BLACKBOARD IS MADE TO LIE, ON PURPOSE
-- ================================================================================
-- This is the load-bearing part of the setup and it is worth being explicit about, because it
-- looks like tampering and is the opposite.
--
-- `player.health_pct` exists in TWO places: the blackboard key the sensor writes in SENSE, and the
-- frozen snapshot `SnapshotSource` captures in the same stage. Both are filled from the same SDK
-- double, so they normally agree -- and while they agree, a test cannot tell a condition that
-- reads the SNAPSHOT from one that reads the BLACKBOARD. `Cond.health_below` was a blackboard read
-- until Phase 4c D5; reverting it would leave every assertion below green.
--
-- So an ARBITRATE-stage handler overwrites the BLACKBOARD key with full health after SENSE has run
-- and before ACT. From then on, inside the tick:
--
--     snapshot   player.health_pct = 0.10   <- frozen, honest, what SENSE actually saw
--     blackboard player.health_pct = 1.00   <- a lie, planted after the freeze
--
-- The mage is at 10% health and the blackboard says otherwise. `cold_snap_defensive` can only fire
-- if its health gate read the SNAPSHOT. It is also what keeps the combat module engaged --
-- `module.lua:593`'s `_check_safety` reads the blackboard key and would disengage on low health
-- with nothing attacking back -- so the lie is doing two honest jobs at once and neither of them
-- involves stubbing a kernel layer.
--
-- ================================================================================
-- WHAT THIS CHAIN CANNOT SEE
-- ================================================================================
--   1. ONE CONDITION. `health_below`/`health_above` are the only snapshot-backed predicates in the
--      profile (frost_conditions.lua:60-63 says why: the other fifteen are blocked on warm/cold
--      snapshot tiers that do not exist). "The rotation reads the snapshot" remains true of the
--      health gate and of nothing else.
--   2. ONE ACTION. Cold Snap is a self-cast named by guid. It exercises `resolve_unit_by_guid` and
--      the self-cast facing/range skip, not the symbolic vocabulary -- test 6 covers that.
--   3. WHETHER THE CLIENT CASTS ANYTHING. Same limit as every other test here: a packet recorded
--      at the double means the double was called with plausible arguments.
--   4. THE GATE CASE IS NOT ROTATION-DRIVEN, AND CANNOT BE. See
--      `test_the_castable_gate_refuses_the_packet_and_names_itself` for the measured reason.

--- The frozen snapshot decides, and a packet leaves because of what it said.
function M.test_the_snapshot_decides_a_cast_that_reaches_the_sdk()
    with_live_app(WOUNDED_MAGE, function(app, sdk)
        local bb = app:get_blackboard()
        local broker = app:get_control_broker()
        install_health_divergence(app, bb)

        local observed = nil
        for _ = 1, 6 do
            sdk.advance(200)
            local report = app:on_update()
            local packet = packet_labelled(sdk, "cold_snap")
            if packet then
                observed = {
                    report = report,
                    packet = packet,
                    snapshot = _G.Sentinel.snapshot,
                    casting_owner = broker:who_owns("CASTING"),
                    blackboard_health = bb:get("player.health_pct"),
                }
                break
            end
        end

        T.assert_not_nil(observed,
            "the wounded mage must reach cold_snap_defensive and land a packet at the SDK")

        -- 1. THE SNAPSHOT. Frozen in SENSE, still readable from the public surface at assert time.
        local S = _G.Sentinel
        T.assert_near(observed.snapshot:get("player.health_pct"), 0.10, 0.0001,
            "the frozen snapshot must carry the health SENSE actually read")
        T.assert_equal(observed.blackboard_health, 1.0,
            "and the blackboard must be carrying the planted lie, or this proves nothing about "
            .. "which of the two the condition consulted")

        -- 2. THE PREDICATE. Asked here exactly as `frost_conditions.snapshot_predicate` asks it.
        local verdict = S.cond.bind(observed.snapshot).health_below(0.30)
        T.assert_true(verdict == S.Truth.True,
            "`Sentinel.cond` must answer True against that snapshot -- and answer in Truth")
        T.assert_true(S.Truth.resolve(verdict, S.Truth.Policy.TreatFalse) == true,
            "and resolve, under the policy the rotation states, to the decision that opened the branch")

        -- 3. THE LEASE. Asked of the BROKER, not of the plugin: a plugin claiming it holds a lease
        --    proves nothing, and the generation validator is what actually refuses an unleased cast.
        T.assert_equal(observed.casting_owner, "sentinel.rotation.mage_frost",
            "the broker must show CASTING held by the rotation on the tick the cast committed")

        -- 4. THE INTENT, through the real dedupe/gate/generation path.
        local cast = nil
        for _, intent in ipairs(observed.report.intents.committed) do
            if intent.type == "cast" and intent.payload.label == "cold_snap" then cast = intent end
        end
        T.assert_not_nil(cast, "the committed intent must be the cold_snap cast: "
            .. describe_rejections(observed.report))
        T.assert_equal(cast.owner, "sentinel.rotation.mage_frost")
        T.assert_not_nil(cast.generation, "carrying the lease generation COMMIT re-checks")
        T.assert_true(cast.payload.off_gcd == true,
            "and the off-GCD bypass both the action and the kernel catalog agreed on")

        -- 5. THE PACKET. Cold Snap has exactly one rank in TBC (11958), so this id is stable
        --    reference data rather than a snapshot of whatever the catalog happened to resolve.
        T.assert_equal(observed.packet.spell_id, 11958,
            "the packet must carry the rank the catalog resolved for `cold_snap`")
        T.assert_equal(observed.packet.verb, "target_fast",
            "and the FAST spell_queue verb the action asked for -- serving a `fast` request with "
            .. "the slow verb would silently undo the only reason it was requested")
        T.assert_equal(observed.packet.priority, 1,
            "§6.3: COMBAT band maps onto spell_queue priority 1")
    end)
end

--- THE NEGATIVE TWIN. Change health and nothing else, and no such cast commits -- so the packet
--- above is the snapshot's doing and not the setup's.
---
--- ================================================================================
--- WHY 45% AND NOT FULL HEALTH, WHICH IS A FINDING RATHER THAN A PREFERENCE
--- ================================================================================
--- Full health was the obvious negative and it FAILED, for a reason worth recording: `frost_tbc`
--- has TWO Cold Snap branches -- `cold_snap_defensive` at `health_below(0.30)` and
--- `cold_snap_offensive` at `health_above(0.60)` -- and both run `Act.queue_cold_snap`, which
--- labels its intent `"cold_snap"` either way. At 100% health the offensive branch fires the
--- identical action with the identical breadcrumb, so a "no cold_snap packet" assertion at full
--- health is unsatisfiable, and one that passed would have been asserting the wrong thing.
---
--- REPORTED, NOT PAPERED OVER: the SDK breadcrumb cannot distinguish a defensive Cold Snap from an
--- offensive one, so neither can a log line, and neither can a human reading the combat log to
--- work out why a cooldown was spent. That is a real diagnosability gap in `frost_actions.lua`,
--- outside this file's ownership, and it is left to its owner.
---
--- 45% sits in the corridor between the two thresholds: above the defensive gate, below the
--- offensive one. Neither branch may open, which is the negative this test needs.
function M.test_a_mage_between_the_two_thresholds_never_reaches_that_cast()
    local opts = {}
    for k, v in pairs(WOUNDED_MAGE) do opts[k] = v end
    opts.health_pct = 0.45

    with_live_app(opts, function(app, sdk)
        local bb = app:get_blackboard()
        install_health_divergence(app, bb)
        run_ticks(app, sdk, 6)

        local S = _G.Sentinel
        T.assert_true(S.cond.bind(S.snapshot).health_below(0.30) == S.Truth.False,
            "a snapshot at 45% must answer False -- not Unknown, which would mean the negative "
            .. "came from missing data rather than from health")
        T.assert_true(S.cond.bind(S.snapshot).health_above(0.60) == S.Truth.False,
            "and False to the offensive branch's gate too, or the corridor is not a corridor")
        T.assert_not_nil(bb:get("combat.target"),
            "THE POSITIVE CONTROL: the module must still be engaged and running the profile, or "
            .. "the absent packet below proves only that nothing was ticked")
        T.assert_nil(packet_labelled(sdk, "cold_snap"),
            "so no cold_snap packet may reach the SDK from either branch")
    end)
end

--- THE REGRESSION GUARD, and the reason the divergence exists at all.
---
--- The snapshot says 45% -- in the corridor, no Cold Snap. The BLACKBOARD says 10%. If
--- `Cond.health_below` ever regresses to the blackboard read it was before Phase 4c D5, the
--- defensive branch opens on the lie and a Cold Snap packet appears. Nothing else in the suite
--- would notice: the two sources agree everywhere else, so every other assertion about health
--- would stay green.
---
--- This is the inverse of the positive test, and the pair brackets the condition: red if it reads
--- the blackboard, red if it reads nothing, green only if it reads the frozen snapshot.
---
--- ================================================================================
--- THE FALSE GREEN THIS TEST ALREADY HAD, CAUGHT BY ITS OWN MUTATION CHECK
--- ================================================================================
--- First cut of this test planted 10% on the blackboard and asserted no packet. It survived the
--- mutation -- `Cond.health_below` reverted to a blackboard read and the test stayed GREEN -- so it
--- was not measuring what its name claimed. The reason: `module.lua:593`'s `_check_safety` reads
--- the SAME blackboard key against `module.combat.low_health_threshold` (0.35) and disengages when
--- nothing is attacking back. The planted 10% tripped it, combat went IDLE, the off-GCD tree never
--- ran, and "no cold_snap packet" was true because the rotation never got a turn.
---
--- Two things fix it, and both are needed:
---   * the low-health disengage is turned OFF for this test, through the module's own documented
---     config key rather than by reaching into the module;
---   * the test ASSERTS it is still engaged, so it can never again pass by not playing. A negative
---     assertion is only worth what its positive control is worth.
---
--- WHAT IT CANNOT SEE: it pins the SOURCE, not the THRESHOLD. A condition that read the snapshot
--- and compared against the wrong number would pass here and is `test_cond_fraction`'s problem.
function M.test_a_blackboard_lie_cannot_open_the_snapshot_backed_gate()
    local opts = {}
    for k, v in pairs(WOUNDED_MAGE) do opts[k] = v end
    opts.health_pct = 0.45

    with_live_app(opts, function(app, sdk)
        local bb = app:get_blackboard()
        -- The divergence, pointed the other way: the SNAPSHOT is the healthy one.
        app:get_scheduler():register("ARBITRATE", "test.inverted_divergence", function()
            bb:set("player.health_pct", 0.10)
            -- Disarm the module's own low-health bail-out, which reads the same key. Without this
            -- the mutation walks free -- see the section above.
            bb:set("module.combat.low_health_threshold", 0)
        end)
        run_ticks(app, sdk, 6)

        T.assert_near(_G.Sentinel.snapshot:get("player.health_pct"), 0.45, 0.0001,
            "the frozen snapshot must hold the honest reading")
        T.assert_equal(bb:get("player.health_pct"), 0.10,
            "and the blackboard the planted one, or there is no divergence to detect")
        T.assert_not_nil(bb:get("combat.target"),
            "THE POSITIVE CONTROL: the module must still be engaged, or the absent packet below "
            .. "says only that the rotation never ran")
        T.assert_nil(packet_labelled(sdk, "cold_snap"),
            "a cold_snap packet here means the health gate read the BLACKBOARD, which is the "
            .. "fail-open shape ADR 07 §5.1.2 built the tri-state for")
    end)
end

--- THE GATE CASE. `is_spell_castable` says no; the packet does not leave, and the refusal is
--- attributed to the gate that made it.
---
--- ================================================================================
--- WHY THE ROTATION CANNOT DRIVE THIS ONE, AND THAT IS NOT A GAP
--- ================================================================================
--- Measured, not assumed: with the helper answering false for everything, the frost profile emits
--- NO cast at all. `Cond.spell_ready` asks the same SDK predicate through `Sentinel.spells` one
--- stage earlier, and that is by design -- `kernel/spells.lua`'s header states it outright: the
--- GATE decides whether a cast happens, the CONDITION decides whether the rotation FALLS THROUGH
--- to its next priority. A rotation that emitted anyway would burn its tick on an action the gate
--- was always going to refuse.
---
--- So a rotation-driven `castable` rejection is unreachable by construction, and the first
--- assertion below pins exactly that. The gate itself is then driven by the smallest caller that
--- can reach it: the same payload, submitted under a real lease. Everything from `submit` down --
--- dedupe, all six gates, the generation check, the executor -- is the shipping kernel.
function M.test_the_castable_gate_refuses_the_packet_and_names_itself()
    local opts = {}
    for k, v in pairs(WOUNDED_MAGE) do opts[k] = v end
    opts.castable = false

    with_live_app(opts, function(app, sdk)
        local bb = app:get_blackboard()
        local broker = app:get_control_broker()
        install_health_divergence(app, bb)

        local submitted = nil
        app:get_scheduler():register("ACT", "test.refused_caster", function(ctx)
            local caretaker = broker:acquire({
                channel = "CASTING", owner = "test.refused_caster",
                band = "COMBAT", offset = 0, tier = "rotation", ttl_ticks = 2,
            })
            if not caretaker then
                submitted = "no_lease"
                return
            end
            -- PHASE 4D D5. The probe names its unit the way a real plugin must: a guid ref MINTED
            -- by the kernel against this tick's frozen snapshot, through the published surface.
            -- A hand-built `{ unit_guid = ... }` is refused as `unstamped_unit_ref` one step
            -- BEFORE `is_spell_castable` is ever asked, so this pin would stop measuring the
            -- castable gate it was written for and start measuring the stamp check instead.
            local guid, stamp = _G.Sentinel.units:mint_ref(
                ctx.snapshot, core.object_manager.get_local_player())
            submitted = caretaker:submit({
                type = "cast",
                payload = { spell_id = 11958, unit_guid = guid, unit_ref_tick = stamp,
                    off_gcd = true, fast = true, label = "refused_probe" },
            })
        end)

        local report = run_ticks(app, sdk, 1)[1]

        T.assert_true(submitted == true,
            "the probe must have taken a real lease and submitted under it, got " .. tostring(submitted))

        local refused = nil
        local rotation_cast = nil
        for _, rejection in ipairs(report.intents.rejected) do
            local intent = rejection.intent or {}
            if intent.owner == "test.refused_caster" then refused = rejection end
        end
        for _, intent in ipairs(report.intents.committed) do
            if intent.type == "cast" then rotation_cast = intent end
        end

        T.assert_nil(rotation_cast,
            "no cast may commit while the SDK refuses every spell -- including the rotation's, "
            .. "which never emits one because `spell_ready` asked the same question first")

        T.assert_not_nil(refused, "the probe's cast must be REJECTED, not committed or failed: "
            .. describe_rejections(report))
        T.assert_equal(refused.gate, "castable",
            "and the refusal must name the gate that made it -- ADR 08 §12: nothing is dropped quietly")
        T.assert_equal(refused.reason, "not_castable",
            "with the reason distinguishable from `no_castable_check` (could not ask) and "
            .. "`unit_unresolved` (nothing to aim at)")
        T.assert_equal(#sdk.packets, 0,
            "and NOTHING may reach the SDK boundary, which is the only thing the gate exists for")
    end)
end

-- ---------------------------------------------------------------------------
-- The regression this pin found
-- ---------------------------------------------------------------------------

--- COMBAT MUST ACTUALLY INITIALISE.
---
--- This is the defect the end-to-end pin existed to catch, and it caught it on the first run. From
--- Phase 4b until Phase 4c, `SentinelCombat:initialize()` threw on its FIRST blackboard write --
--- `module.combat.izi_bridge`, refused by the handle guard, whose ledger was built from
--- cross-namespace READ findings and so never considered a key only combat reads. `initialize_all`
--- pcalled the error into nothing and set the module SHUTDOWN. Combat was dead in every real boot:
--- no profile, no catalog, no rotation, no cast, and nothing logged.
---
--- Asserting the OUTCOME (a profile on the blackboard, an ACTIVE module) rather than the specific
--- key, so the pin survives the next collaborator that gets added or retired.
function M.test_the_combat_module_actually_initialises_in_a_real_boot()
    with_live_app(nil, function(app, sdk)
        local bb = app:get_blackboard()

        T.assert_not_nil(bb:get("module.combat.profile"),
            "combat must have built a rotation profile -- a silent init failure leaves this nil")
        T.assert_not_nil(bb:get("module.combat.catalog"), "and published its spell catalog")
        T.assert_equal(bb:get("player.class_id"), MAGE_CLASS_ID,
            "having read the class off the SDK rather than defaulting")

        run_ticks(app, sdk, 1)
        T.assert_nil(bb:get("system.module_faults"),
            "and no module may have faulted at boot")
    end)
end

--- The state that decides whether combat EVER TICKS AGAIN, which the pin above never asserted.
---
--- `ModuleRegistry:tick_all` runs a module only while `get_state(name) == "active"`
--- (runtime/module_registry.lua). Every other assertion in this file infers combat's liveness from
--- side effects it left on the blackboard AT BOOT -- a profile, a catalog, a class id. Those survive
--- the module being set SHUTDOWN or DEGRADED one line later: the writes already happened, so a
--- combat module that initialised perfectly and will never be ticked again reads exactly the same.
--- `rg 'get_state\("combat"\)'` returned ZERO hits repo-wide before this test.
---
--- `"active"` is a literal here and that is a deliberate, reported compromise. `MODULE_STATES` is a
--- FILE-LOCAL in runtime/module_registry.lua with no export, and that file belongs to another unit
--- of this phase -- so exporting it was out of scope. The literal is not unanchored:
--- `tests/runtime/test_module_registry.lua` pins `MODULE_STATES.ACTIVE == "active"` directly, and
--- `test_one_fault_tracker` and `test_tick_isolation` already assert the same string. WHAT THIS
--- CANNOT SEE, precisely: a rename of the private constant's VALUE would redden this test without
--- telling the reader that the registry, not combat, is what changed.
function M.test_the_combat_module_is_active_after_a_real_boot()
    with_live_app(nil, function(app, sdk)
        local registry = app._registry
        T.assert_not_nil(registry, "the app must expose the module registry it drives")

        T.assert_equal(registry:get_state("combat"), "active",
            "combat must be ACTIVE after a real boot -- any other state means `tick_all` skips it "
            .. "forever, however healthy the blackboard looks")

        -- And it must STAY active: DEGRADED is what three consecutive tick faults produce, and a
        -- module that comes up and then quarantines itself is the same silence in slow motion.
        run_ticks(app, sdk, 4)
        T.assert_equal(registry:get_state("combat"), "active",
            "and must still be active after four ticks -- a module that degrades has stopped "
            .. "running with nothing on the blackboard saying so")
    end)
end

--- PHASE 4D D1: THE BLACKBOARD DOES NOT HOLD THE IZI BRIDGE, AND THE FORECAST STILL WORKS.
---
--- These two halves have to be asserted together. Deleting the write alone leaves every reader
--- falling silently through to its non-forecast branch, and the suite stays green -- which is the
--- exact failure this deliverable exists to end.
function M.test_the_forecast_service_replaces_the_bridge_on_the_blackboard()
    with_live_app(nil, function(app)
        local bb = app:get_blackboard()

        T.assert_nil(bb:get("module.combat.izi_bridge"),
            "the blackboard stores VALUES (ADR 08 §2.7); the bridge carries a metatable and the "
            .. "guard was right to refuse it -- the storage moved, the guard did not widen")

        local forecast = app:get_forecast()
        T.assert_not_nil(forecast, "the app must own a forecast service")
        T.assert_true(_G.Sentinel.forecast == forecast,
            "and publish THAT instance -- a plugin reading a different one reads different state")

        -- ONE bridge in the process. Combat used to build a second, so the app's was reachable by
        -- nothing (ADR 08 §7 called `_izi_bridge` constructed-and-never-read, and was right).
        local combat_wrapper = app:get_module("combat")
        T.assert_not_nil(combat_wrapper, "combat must be registered")
        T.assert_true(combat_wrapper._izi_bridge == app:get_izi_bridge(),
            "combat must run on the APP's bridge, not a private second instance")

        -- Offline the IZI SDK is absent, so the honest answer everywhere is "cannot say" -- never a
        -- plausible zero (ADR 08 §9.3). A forecast that answered 0 here would read as "this target
        -- is already dead" to every consumer.
        T.assert_false(forecast:is_available(),
            "the injector-only IZI SDK cannot load offline, and that must be a NAMED state")
        T.assert_nil(forecast:time_to_die(app:get_blackboard():get("player.object")),
            "an unavailable forecast says nil, not 0")
    end)
end

--- An unleased cast is the failure §6.1 exists to prevent, and the generation validator is what
--- prevents it. Driven here against the REAL app rather than a hand-built queue: the validator is
--- wired in `SentinelApp:new()`, and a pin that built its own queue would not prove that wiring.
function M.test_an_intent_submitted_without_a_lease_is_refused_by_the_live_app()
    with_live_app(nil, function(app, sdk)
        local queue = app:get_intent_queue()
        queue:submit({
            type = "cast",
            owner = "impostor",
            band = Bands.BANDS.COMBAT.min,
            payload = { spell_id = 133, unit = "player" },
        })
        local report = run_ticks(app, sdk, 1)[1]

        local refused = nil
        for _, rejection in ipairs(report.intents.rejected) do
            if rejection.intent and rejection.intent.owner == "impostor" then refused = rejection end
        end
        T.assert_not_nil(refused, "an unleased cast must be rejected, not committed")
        T.assert_equal(refused.reason, "stale_generation")

        for _, packet in ipairs(sdk.packets) do
            T.assert_true(packet.spell_id ~= 133,
                "and no packet for it may reach the SDK")
        end
    end)
end

-- ---------------------------------------------------------------------------
-- The tick survives the whole thing
-- ---------------------------------------------------------------------------

--- A real app running real modules must not be quietly faulting its way through the phase. The
--- scheduler swallows handler errors by design (that is the ErrorBoundary), so a green assertion
--- above could coexist with every stage throwing.
function M.test_no_stage_faults_during_the_run()
    with_live_app(nil, function(app, sdk)
        local reports = run_ticks(app, sdk, 3)
        for _, report in ipairs(reports) do
            if #report.faults > 0 then
                local first = report.faults[1]
                error(string.format("tick %d faulted in %s (%s): %s",
                    report.tick_index, first.stage, first.owner, first.error), 0)
            end
        end
    end)
end

return M
