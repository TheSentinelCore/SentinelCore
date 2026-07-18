local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SensorHub = require("runtime/sensor_hub")
local T = require("tests/test_util")

local M = {}

local function make_player()
    return {
        get_target = function() return nil end,
        get_position = function() return { x = 1, y = 2, z = 3 } end,
        get_health = function() return 100 end,
        get_max_health = function() return 100 end,
        get_power = function() return 100 end,
        get_max_power = function() return 100 end,
        is_casting_spell = function() return false end,
        is_channelling_spell = function() return false end,
        is_moving = function() return false end,
        is_auto_attacking = function() return false end,
        is_dead = function() return false end,
        is_ghost = function() return false end,
        is_mounted = function() return false end,
        is_outdoors = function() return true end,
        get_attack_speed = function() return 3.0 end,
        has_buff = function() return false end,
        get_buff_data = function() return { is_active = false, stack_count = 0 } end,
        get_buff_stacks = function() return 0 end,
        get_buffs = function() return {} end,
    }
end

function M.run()
    local player = make_player()
    core = {
        object_manager = {
            get_local_player = function()
                return player
            end,
        },
        game_time = function() return 2000 end,
        delta_time = function() return 0.05 end,
        get_ping = function() return 18 end,
        get_map_id = function() return 1459 end,
        get_map_name = function() return "Warsong Gulch" end,
        get_instance_id = function() return 0 end,
        get_instance_name = function() return "Warsong Gulch" end,
        game_ui = {
            get_battlefield_state = function() return 5 end,
            get_battlefield_winner = function() return 1 end,
            get_battlefield_run_time = function() return 123456 end,
            get_corpse_position = function() return { x = 10, y = 20, z = 30 } end,
            get_resurrect_corpse_delay = function() return 12 end,
            get_battlefield_status = function(index)
                local statuses = {
                    [1] = "queued",
                    [2] = "confirm",
                    [3] = "none",
                }
                return statuses[index]
            end,
        },
    }

    local bb = Blackboard:new()
    local hub = SensorHub:new(bb, EventBus:new())
    hub._unit_helper = nil
    hub._izi = {
        queue_popup_info = function()
            return true, {
                kind = "pvp",
                age_ms = 250,
                pvp = {
                    slots = {
                        { idx = 2 },
                    },
                },
            }
        end,
    }

    hub:refresh()
    hub:refresh()

    T.assert_true(bb:get("bg.sensor.in_bg", false))
    T.assert_equal(bb:get("bg.sensor.queue_status_summary"), "queued|confirm|none")
    T.assert_equal(bb:get("bg.sensor.queue_popup_kind"), "pvp")
    T.assert_equal(bb:get("bg.sensor.queue_popup_slot_idx"), 2)
    T.assert_equal(bb:get("bg.sensor.queue_popup_seq"), 1)
    T.assert_equal(bb:get("bg.sensor.battlefield_state_streak_5"), 2)
    T.assert_true(bb:get("bg.sensor.in_finished", false))
    T.assert_equal(bb:get("system.instance_id"), 0)
    T.assert_equal(bb:get("system.instance_name"), "Warsong Gulch")
    T.assert_false(bb:get("player.is_dead", true))
    T.assert_false(bb:get("player.is_ghost", true))
    T.assert_false(bb:get("player.is_mounted", true))
    T.assert_true(bb:get("player.is_outdoors", false))
    T.assert_equal(bb:get("player.resurrect_delay_s"), 12)
end

return M
