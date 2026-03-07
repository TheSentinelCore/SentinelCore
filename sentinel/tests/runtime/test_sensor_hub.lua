local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SensorHub = require("runtime/sensor_hub")
local T = require("tests/test_util")

local M = {}

local function make_player(buff_set)
    return {
        get_target = function() return nil end,
        get_position = function() return { x = 0, y = 0, z = 0 } end,
        get_health = function() return 100 end,
        get_max_health = function() return 100 end,
        get_power = function() return 100 end,
        get_max_power = function() return 100 end,
        is_casting_spell = function() return false end,
        is_channelling_spell = function() return false end,
        is_moving = function() return false end,
        is_auto_attacking = function() return false end,
        get_attack_speed = function() return 3.0 end,
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
end

return M
