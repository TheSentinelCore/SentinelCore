local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SensorHub = require("runtime/sensor_hub")
local T = require("tests/test_util")

local M = {}

local function make_player(buff_set, overrides)
    overrides = overrides or {}
    return {
        get_target = function() return nil end,
        get_position = function() return { x = 0, y = 0, z = 0 } end,
        get_health = function() return overrides.health or 100 end,
        get_max_health = function() return overrides.max_health or 100 end,
        get_power = function() return 100 end,
        get_max_power = function() return 100 end,
        is_casting_spell = function() return overrides.is_casting or false end,
        is_channelling_spell = function() return overrides.is_channeling or false end,
        is_moving = function() return false end,
        is_auto_attacking = function() return overrides.is_auto_attacking or false end,
        get_attack_speed = function() return 3.0 end,
        is_in_combat = function() return overrides.in_combat or false end,
        is_dead = function() return overrides.is_dead or false end,
        is_ghost = function() return overrides.is_ghost or false end,
        is_mounted = function() return overrides.is_mounted or false end,
        has_buff = function(_self, spell_id)
            if type(spell_id) == "table" then
                for _, id in ipairs(spell_id) do
                    if buff_set[id] then
                        return true
                    end
                end
                return false
            end
            return buff_set[spell_id] == true
        end,
        get_buff_data = function(_self, spell_id)
            return { is_active = buff_set[spell_id] == true, stack_count = 0 }
        end,
        get_buff_stacks = function() return 0 end,
        get_buffs = function() return {} end,
    }
end

function M.run()
    core = {
        object_manager = {
            get_local_player = function()
                return make_player({ [20375] = true })
            end,
        },
        game_time = function() return 1000 end,
        delta_time = function() return 0.05 end,
        get_ping = function() return 33 end,
        get_map_id = function() return 489 end,
        get_map_name = function() return "Warsong Gulch" end,
    }

    local bb = Blackboard:new()
    local hub = SensorHub:new(bb, EventBus:new())
    hub._unit_helper = nil
    hub:refresh()

    T.assert_equal(bb:get("rotation.active_seal"), "command")

    -- Test: combat state transition fires event
    local eb2 = EventBus:new()
    local events_received = {}
    eb2:subscribe("player:combat_changed", function(payload)
        events_received[#events_received + 1] = { event = "combat_changed", in_combat = payload.in_combat }
    end)
    local bb2 = Blackboard:new()
    local hub2 = SensorHub:new(bb2, eb2)
    hub2._unit_helper = nil
    -- First refresh: no combat (default)
    hub2:refresh()
    T.assert_equal(#events_received, 0, "no combat event on first refresh")

    -- Change mock to report combat
    local player_combat = make_player({}, { in_combat = true })
    core.object_manager.get_local_player = function() return player_combat end
    hub2:refresh()
    T.assert_equal(#events_received, 1, "combat event fired on transition")
    T.assert_equal(events_received[1].in_combat, true, "combat event reports in_combat=true")

    -- Same state: no new event
    hub2:refresh()
    T.assert_equal(#events_received, 1, "no duplicate combat event when state unchanged")

    -- Test: mount state transition fires event
    local eb3 = EventBus:new()
    local mount_events = {}
    eb3:subscribe("player:mount_changed", function(payload)
        mount_events[#mount_events + 1] = { is_mounted = payload.is_mounted }
    end)
    local bb3 = Blackboard:new()
    local hub3 = SensorHub:new(bb3, eb3)
    hub3._unit_helper = nil
    hub3:refresh()
    T.assert_equal(#mount_events, 0, "no mount event on first refresh")

    local player_mounted = make_player({}, { is_mounted = true })
    core.object_manager.get_local_player = function() return player_mounted end
    hub3:refresh()
    T.assert_equal(#mount_events, 1, "mount event fired on mount")
    T.assert_equal(mount_events[1].is_mounted, true, "mount event reports mounted")

    -- Test: death transition fires event
    local eb4 = EventBus:new()
    local death_events = {}
    eb4:subscribe("player:death_changed", function(payload)
        death_events[#death_events + 1] = { is_dead = payload.is_dead, is_ghost = payload.is_ghost }
    end)
    local bb4 = Blackboard:new()
    local hub4 = SensorHub:new(bb4, eb4)
    hub4._unit_helper = nil
    hub4:refresh()
    T.assert_equal(#death_events, 0, "no death event on first refresh")

    local player_dead = make_player({}, { is_dead = true })
    core.object_manager.get_local_player = function() return player_dead end
    hub4:refresh()
    T.assert_equal(#death_events, 1, "death event fired")
    T.assert_equal(death_events[1].is_dead, true, "death event reports is_dead")

    -- Test: shutdown unsubscribes IZI callbacks
    local hub5 = SensorHub:new(Blackboard:new(), EventBus:new())
    hub5._aura_sensor._izi_unsubscribers = { function() hub5._test_unsub_called = true end }
    hub5:shutdown()
    T.assert_equal(hub5._test_unsub_called, true, "shutdown calls unsubscribers")
    T.assert_equal(#hub5._aura_sensor._izi_unsubscribers, 0, "shutdown clears unsubscribers")

    -- Test: health threshold crossing fires event
    local eb6 = EventBus:new()
    local hp_events = {}
    eb6:subscribe("player:health_threshold", function(payload)
        hp_events[#hp_events + 1] = { threshold = payload.threshold, direction = payload.direction, hp = payload.health_pct }
    end)
    local bb6 = Blackboard:new()
    local hub6 = SensorHub:new(bb6, eb6)
    hub6._unit_helper = nil
    -- Start at full health
    core.object_manager.get_local_player = function() return make_player({}) end
    hub6:refresh()
    T.assert_equal(#hp_events, 0, "no hp event at full health")

    -- Drop to 15% HP (crosses 0.20 and 0.15 thresholds)
    core.object_manager.get_local_player = function()
        return make_player({}, { health = 15, max_health = 100 })
    end
    hub6:refresh()
    -- Should fire for thresholds crossed: 0.20 (below) and 0.15 (below)
    T.assert_true(#hp_events >= 2, "hp threshold events fired: got " .. #hp_events)

    -- Restore default core for other test files
    core = nil
end

return M
