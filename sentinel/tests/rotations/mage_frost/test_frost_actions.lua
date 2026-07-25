-- PHASE 4C: the recorder moved, the assertions did not.
--
-- Casts leave the plugin as `cast` intents, so there is no SpellDispatcher to record against. Every
-- assertion below is unchanged: the dispatcher's `action_id` travels as the intent's `payload.label`
-- and its `spell_id` as `payload.spell_id`, so `actions[1].action_id` still means what it meant.
--
-- `accept = false` now models a queue that REFUSES the submission rather than a dispatcher that
-- refused the queue call. Both are "the cast did not get in", which is the only thing these
-- assertions ever distinguished.
--
-- WHAT THIS FILE CANNOT SEE, and did not see before either: whether the cast ever reaches the SDK.
-- Recording is at submit, so the GCD gate, the castability gate and the lease generation check are
-- all downstream of everything asserted here. tests/rotations/mage_frost/test_frost_cast_intents.lua
-- commits the queue and is where that lives.
local Api = require("kernel/api")
local Blackboard = require("core/blackboard")
local ControlBroker = require("kernel/control_broker")
local Status = require("core/bt/status")
-- Phase 4d D5: a cast names its unit by a guid ref MINTED THROUGH THE KERNEL against the tick's
-- frozen snapshot, so the surface needs BOTH `units` (the mint) and a scheduler (the tick).
local Snapshot = require("kernel/snapshot")
local Units = require("kernel/units")
local T = require("tests/test_util")

local M = {}

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_guid() return opts.guid or "guid" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:get_health_percentage() return opts.health_pct or 1.0 end
    function unit:is_dead() return false end
    function unit:has_buff(_) return false end
    function unit:get_buff_data(_) return { is_active = false, stack_count = 0 } end
    function unit:get_buff_stacks(_) return 0 end
    function unit:get_buffs() return {} end
    return unit
end

local function make_bb(overrides)
    overrides = overrides or {}

    local bb = Blackboard:new()
    local player = make_unit({ guid = "player" })
    local target = make_unit({ guid = "target", position = { x = 10, y = 0, z = 0 } })

    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("combat.target", target)
    bb:set("module.combat.catalog", require("kernel/catalogs/spell"):new())

    local accept = overrides.accept ~= false
    local queued_actions = overrides.queued_actions or {}
    local queued_positions = overrides.queued_positions or {}

    -- Split by DESTINATION, the way the two dispatcher verbs used to split: a payload carrying a
    -- point is a ground-targeted cast, anything else is a unit cast. That keeps
    -- "blizzard should not use queue_target" meaningful without naming either verb.
    local recording_queue = {
        submit = function(_self, intent)
            local payload = intent.payload or {}
            local entry = { action_id = payload.label, spell_id = payload.spell_id }
            if payload.point then
                entry.position = payload.point
                queued_positions[#queued_positions + 1] = entry
            else
                queued_actions[#queued_actions + 1] = entry
            end
            return accept
        end,
    }
    local broker = ControlBroker:new({ intent_queue = recording_queue })
    -- The tick a minted guid ref is stamped with. These scenarios never commit -- the recording
    -- queue captures the intent at submit -- so any stable tick will do; what matters is that the
    -- mint can read ONE, because a rotation with no snapshot can name no unit.
    local frozen = Snapshot.empty(1)
    _G.Sentinel = Api.build({
        blackboard = bb, broker = broker, intent_queue = recording_queue,
        scheduler = { current_snapshot = function() return frozen end },
        units = Units:new(),
    })

    return bb, queued_actions, queued_positions
end

function M.run()
    local Act = require("rotations/mage_frost/frost_actions")
    -- `make_bb` publishes `_G.Sentinel`; the offline harness's surface must go back afterwards or
    -- every plugin suite that follows loses its kernel.
    local saved_surface = _G.Sentinel
    local ok, err = pcall(M._body, Act)
    _G.Sentinel = saved_surface
    if not ok then error(err, 0) end
end

function M._body(Act)

    -- queue_frostbolt returns SUCCESS when dispatcher accepts
    local bb, actions = make_bb({ accept = true })
    T.assert_equal(Act.queue_frostbolt(bb), Status.SUCCESS, "frostbolt should return SUCCESS")
    T.assert_equal(actions[1].action_id, "frostbolt", "frostbolt action_id should match")

    -- queue_frostbolt returns FAILURE when dispatcher rejects
    bb, actions = make_bb({ accept = false })
    T.assert_equal(Act.queue_frostbolt(bb), Status.FAILURE, "frostbolt should return FAILURE when rejected")

    -- queue_frostbolt returns FAILURE when spell not in catalog
    bb = make_bb({ accept = true })
    bb:set("module.combat.catalog", nil)
    T.assert_equal(Act.queue_frostbolt(bb), Status.FAILURE, "frostbolt should FAILURE without catalog")

    -- noop returns FAILURE
    T.assert_equal(Act.noop(bb), Status.FAILURE, "noop should return FAILURE")

    -- queue_blizzard uses queue_position (not queue_target)
    local positions
    bb, actions, positions = make_bb({ accept = true })
    T.assert_equal(Act.queue_blizzard(bb), Status.SUCCESS, "blizzard should return SUCCESS")
    T.assert_equal(#actions, 0, "blizzard should not use queue_target")
    T.assert_equal(positions[1].action_id, "blizzard", "blizzard should use queue_position")
    T.assert_not_nil(positions[1].position, "blizzard should provide a position")

    -- queue_fire_blast returns SUCCESS
    bb, actions = make_bb({ accept = true })
    T.assert_equal(Act.queue_fire_blast(bb), Status.SUCCESS, "fire_blast should return SUCCESS")
    T.assert_equal(actions[1].action_id, "fire_blast", "fire_blast action_id should match")

    -- queue_frost_nova targets player (self-cast AoE)
    bb, actions = make_bb({ accept = true })
    T.assert_equal(Act.queue_frost_nova(bb), Status.SUCCESS, "frost_nova should return SUCCESS")
    T.assert_equal(actions[1].action_id, "frost_nova", "frost_nova action_id should match")

    -- queue_ice_barrier uses fast=true (off-GCD)
    bb, actions = make_bb({ accept = true })
    T.assert_equal(Act.queue_ice_barrier(bb), Status.SUCCESS, "ice_barrier should return SUCCESS")
    T.assert_equal(actions[1].action_id, "ice_barrier", "ice_barrier action_id should match")

    -- queue_icy_veins uses fast=true (off-GCD)
    bb, actions = make_bb({ accept = true })
    T.assert_equal(Act.queue_icy_veins(bb), Status.SUCCESS, "icy_veins should return SUCCESS")
    T.assert_equal(actions[1].action_id, "icy_veins", "icy_veins action_id should match")

    -- queue_counterspell uses INTERRUPT priority
    bb, actions = make_bb({ accept = true })
    T.assert_equal(Act.queue_counterspell(bb), Status.SUCCESS, "counterspell should return SUCCESS")
    T.assert_equal(actions[1].action_id, "counterspell", "counterspell action_id should match")

    -- queue_evocation targets player
    bb, actions = make_bb({ accept = true })
    T.assert_equal(Act.queue_evocation(bb), Status.SUCCESS, "evocation should return SUCCESS")
    T.assert_equal(actions[1].action_id, "evocation", "evocation action_id should match")

    -- maintenance: frost_armor, ice_armor, arcane_intellect, conjure_food, conjure_water
    bb, actions = make_bb({ accept = true })
    T.assert_equal(Act.queue_frost_armor(bb), Status.SUCCESS, "frost_armor should return SUCCESS")
    T.assert_equal(actions[1].action_id, "frost_armor", "frost_armor action_id should match")

    bb, actions = make_bb({ accept = true })
    T.assert_equal(Act.queue_arcane_intellect(bb), Status.SUCCESS, "arcane_intellect should return SUCCESS")
    T.assert_equal(actions[1].action_id, "arcane_intellect", "arcane_intellect action_id should match")

    bb, actions = make_bb({ accept = true })
    T.assert_equal(Act.queue_conjure_water(bb), Status.SUCCESS, "conjure_water should return SUCCESS")
    T.assert_equal(actions[1].action_id, "conjure_water", "conjure_water action_id should match")

    -- blizzard returns FAILURE with no target
    bb = make_bb({ accept = true })
    bb:set("combat.target", nil)
    bb:set("player.target", nil)
    T.assert_equal(Act.queue_blizzard(bb), Status.FAILURE, "blizzard should FAILURE without target")
end

return M
