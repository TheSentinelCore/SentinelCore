-- Characterization test for frost_tbc.lua's GCD priority tree (build_gcd_root).
--
-- Purpose (SDD unify-combat-authoring-prioritybuilder-warlock, Unit A / task A1):
-- pins the pre-migration BT.factory-nested tree's action-selection behavior for a
-- set of representative blackboard states, so the PriorityBuilder port (A2) can be
-- proven behavior-preserving by re-running this same suite unmodified against the
-- rewritten tree.
--
-- PHASE 4C: the recorder moved, the assertions did not.
--
-- Casts leave the plugin as `cast` intents now, so there is no SpellDispatcher to record against.
-- What each scenario asserts -- which single action the tree selected -- is unchanged, because the
-- dispatcher's `action_id` is carried through as the intent's `payload.label`. That is the property
-- that makes this file still a characterization test rather than a rewritten one: every
-- `assert_equal(recorder.calls[1], "counterspell")` below is byte-for-byte what it was.
--
-- Recording happens at SUBMIT, not at commit, deliberately. The old recorder logged the queue call
-- whatever the SDK then did with it; recording at commit would additionally fold in the GCD and
-- castability gates, and this suite is about the TREE's choice, not about what the kernel permits.
local Api = require("kernel/api")
local Blackboard = require("core/blackboard")
local ControlBroker = require("kernel/control_broker")
local EventBus = require("core/event_bus")
local Profile = require("rotations/mage_frost/frost_tbc")
local Snapshot = require("kernel/snapshot")
-- Phase 4d D5: a cast names its unit by a guid ref MINTED THROUGH THE KERNEL, so a surface
-- without `units` leaves the rotation with no legal way to name a target and every action refuses.
local Units = require("kernel/units")
local T = require("tests/test_util")

local M = {}

--- Every scenario publishes a real `_G.Sentinel` and must put back whatever the offline harness had
--- there, or the plugin suites that follow lose their kernel.
local function with_surface(surface, fn)
    local saved = _G.Sentinel
    _G.Sentinel = surface
    local ok, err = pcall(fn)
    _G.Sentinel = saved
    if not ok then error(err, 0) end
end

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_guid() return opts.guid or "guid" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:get_health_percentage() return opts.health_pct or 1.0 end
    function unit:is_dead() return false end
    function unit:get_target() return opts.target end
    function unit:has_buff(buff_id)
        local buffs = opts.buffs or {}
        if type(buff_id) == "table" then
            for _, id in ipairs(buff_id) do
                if buffs[id] then return true end
            end
            return false
        end
        return buffs[buff_id] == true
    end
    function unit:get_buff_data(spell_id)
        return { is_active = unit:has_buff(spell_id), stack_count = 0 }
    end
    function unit:get_buff_stacks(_spell_id) return 0 end
    function unit:get_buffs() return {} end
    function unit:is_casting_spell() return opts.casting == true end
    function unit:is_channelling_spell() return false end
    function unit:is_active_spell_interruptable() return opts.interruptible ~= false end
    return unit
end

--- Build a blackboard + a recording dispatcher.
-- @param overrides table Optional key/value pairs applied via bb:set after defaults.
-- @return blackboard, recorder (recorder.calls is an ordered list of {action_id=...})
local function make_bb(overrides)
    spell_helper = {
        is_spell_castable = function(_self, _spell_id, _source, _target, _ignore_facing, _ignore_range)
            return true
        end,
        get_spell_cooldown = function(_self, _spell_id)
            return 0
        end,
        is_spell_in_line_of_sight = function()
            return true
        end,
    }

    local bb = Blackboard:new()
    local player = make_unit({ guid = "player", position = { x = 0, y = 0, z = 0 }, buffs = {},
        casting = overrides and overrides._player_casting })
    local target = make_unit({
        guid = "target",
        position = { x = 25, y = 0, z = 0 },
        health_pct = (overrides and overrides._target_health_pct) or 0.80,
        casting = overrides and overrides._target_casting,
        interruptible = (overrides == nil or overrides._target_interruptible == nil) and true
            or overrides._target_interruptible,
    })
    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.mana_pct", 1.0)
    bb:set("player.level", 70)
    bb:set("player.in_combat", true)
    bb:set("player.is_moving", false)
    bb:set("combat.target", target)
    bb:set("combat.state", "ENGAGING")
    bb:set("combat.enemy_count_10yd", 0)
    bb:set("combat.gcd_until_ms", 0)
    bb:set("module.combat.catalog", require("kernel/catalogs/spell"):new())

    local gcd_ready = true
    if overrides and overrides._gcd_ready == false then
        gcd_ready = false
    end
    bb:set("module.combat.cooldowns", {
        spell_ready = function() return true end,
        is_gcd_ready = function() return gcd_ready end,
    })

    -- The recorder now sits where the intent queue does. A real ControlBroker still stands in front
    -- of it, so a cast that could not take a CASTING lease is invisible here exactly as a cast the
    -- dispatcher refused used to be.
    local recorder = { calls = {} }
    local recording_queue = {
        submit = function(_self, intent)
            table.insert(recorder.calls, intent.payload and intent.payload.label)
            return true
        end,
    }
    local broker = ControlBroker:new({ intent_queue = recording_queue })

    -- The tick a minted guid ref is stamped with. These scenarios record at SUBMIT and never
    -- commit, so any stable tick will do; what matters is that the mint can read ONE, because a
    -- rotation with no snapshot can name no unit and every action would refuse.
    local frozen = Snapshot.empty(1)

    recorder.surface = Api.build({
        blackboard = bb, broker = broker, intent_queue = recording_queue,
        scheduler = { current_snapshot = function() return frozen end },
        -- `Sentinel.units` is where a guid ref is minted, stamped with THIS snapshot's tick index.
        -- The scheduler double above is what makes the stamp reachable; the two travel together.
        units = Units:new(),
    })

    if overrides then
        for key, value in pairs(overrides) do
            if key:sub(1, 1) ~= "_" then
                bb:set(key, value)
            end
        end
    end

    return bb, recorder
end

local function build_profile(bb)
    local bus = EventBus:new()
    return Profile.build(bb, bus)
end

--- Drive one GCD tick with the scenario's kernel surface published.
local function tick_gcd(profile, bb, recorder)
    local status
    with_surface(recorder.surface, function() status = profile:tick_gcd(bb) end)
    return status
end

-- Scenario 1: interruptible cast in range -> counterspell wins over everything else.
function M.test_counterspell_interrupt_wins()
    local bb, recorder = make_bb({ _target_casting = true, _target_interruptible = true })
    local profile = build_profile(bb)
    tick_gcd(profile, bb, recorder)
    T.assert_equal(#recorder.calls, 1, "exactly one action should be queued")
    T.assert_equal(recorder.calls[1], "counterspell", "counterspell interrupt must preempt all other priorities")
end

-- Scenario 2: health critical (<15%) -> Ice Block emergency wins over lower-priority entries.
function M.test_ice_block_emergency_wins()
    local bb, recorder = make_bb({ ["player.health_pct"] = 0.10 })
    local profile = build_profile(bb)
    tick_gcd(profile, bb, recorder)
    T.assert_equal(#recorder.calls, 1, "exactly one action should be queued")
    T.assert_equal(recorder.calls[1], "ice_block", "critical health must trigger Ice Block emergency")
end

-- Scenario 3: 2+ melee attackers -> Frost Nova + kite-start fires (two-action sequence),
-- and kite state is published to the blackboard by the second action.
function M.test_frost_nova_kite_fires_and_starts_kite()
    local bb, recorder = make_bb({ ["combat.enemy_count_10yd"] = 2 })
    local profile = build_profile(bb)
    tick_gcd(profile, bb, recorder)
    T.assert_equal(#recorder.calls, 1, "only the dispatch-producing action (frost_nova) should record a queue call")
    T.assert_equal(recorder.calls[1], "frost_nova", "2+ melee attackers must trigger Frost Nova kite-start")
    T.assert_equal(bb:get("combat.kite_state"), "NOVA_PENDING",
        "start_kite (second action in the sequence) must still run and publish kite state")
end

-- Scenario 4: pet already summoned, standing still, nothing else contending ->
-- filler Frostbolt (summon_water_elemental is skipped because the pet already exists).
function M.test_frostbolt_filler_when_pet_present()
    local bb, recorder = make_bb({ ["combat.has_water_elemental"] = true })
    local profile = build_profile(bb)
    tick_gcd(profile, bb, recorder)
    T.assert_equal(#recorder.calls, 1, "exactly one action should be queued")
    T.assert_equal(recorder.calls[1], "frostbolt", "standing-still filler with no other priorities active must be Frostbolt")
end

-- Scenario 5: default baseline (no water elemental yet, level 70, standing still) ->
-- Summon Water Elemental takes priority over the Frostbolt filler.
function M.test_summon_water_elemental_before_frostbolt_filler()
    local bb, recorder = make_bb()
    local profile = build_profile(bb)
    tick_gcd(profile, bb, recorder)
    T.assert_equal(#recorder.calls, 1, "exactly one action should be queued")
    T.assert_equal(recorder.calls[1], "summon_water_elemental",
        "missing Water Elemental must be summoned ahead of the Frostbolt filler")
end

-- Scenario 6: GCD not ready -> every gated priority fails, tree falls through to
-- the noop fallback and no dispatch call is ever made.
function M.test_fallback_noop_when_gcd_not_ready()
    local bb, recorder = make_bb({ _gcd_ready = false })
    local profile = build_profile(bb)
    local status = tick_gcd(profile, bb, recorder)
    T.assert_equal(#recorder.calls, 0, "no action should be queued while GCD is not ready")
    T.assert_equal(status, "FAILURE", "tree must report FAILURE when only the noop fallback fires")
end

return M
