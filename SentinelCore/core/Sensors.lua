local Helpers = require("lib/Helpers")
local FactionResolver = require("lib/FactionResolver")

local OBJECT_UNWRAP_KEYS = {
    "object",
    "raw_object",
    "game_object",
}

---@param value any
---@return any
local function unwrap_game_object(value)
    if type(value) ~= "table" then
        return value
    end

    for i = 1, #OBJECT_UNWRAP_KEYS do
        local candidate = rawget(value, OBJECT_UNWRAP_KEYS[i])
        if candidate ~= nil then
            return candidate
        end
    end

    return value
end

---@class SentinelSensors
---@field private _blackboard Blackboard
local Sensors = {}
Sensors.__index = Sensors

---@param blackboard Blackboard
---@return SentinelSensors
function Sensors:new(blackboard)
    local o = setmetatable({}, Sensors)
    o._blackboard = blackboard
    return o
end

---@private
---@return game_object|nil
local function get_player()
    if not core or not core.object_manager or not core.object_manager.get_local_player then
        return nil
    end
    local player = unwrap_game_object(core.object_manager.get_local_player())
    if not player or not player.is_valid or not player:is_valid() then
        return nil
    end
    return player
end

---@return table
function Sensors:update()
    local bb = self._blackboard
    local now = (core and core.time and core.time()) or 0
    bb:set("_time", now)

    local player = get_player()
    bb:set("player.object", player)

    local sensor_snapshot = {
        timestamp = now,
        player_valid = player ~= nil,
    }

    if not player then
        return sensor_snapshot
    end

    local pos = player:get_position()
    local target = player.get_target and player:get_target() or nil
    local map_id = (core and core.get_map_id and core.get_map_id()) or 0
    local instance_type = (core and core.get_instance_type and core.get_instance_type()) or "none"
    local spec_id = 0
    if player.get_specialization_id then
        spec_id = tonumber(player:get_specialization_id()) or 0
    elseif core and core.spell_book and core.spell_book.get_specialization_id then
        spec_id = tonumber(core.spell_book.get_specialization_id()) or 0
    end

    bb:set("player.position", pos)
    bb:set("player.target", target)
    bb:set("player.health", player:get_health())
    bb:set("player.max_health", player:get_max_health())
    bb:set("player.in_combat", player:is_in_combat())
    bb:set("player.is_casting", player:is_casting_spell() or player:is_channelling_spell())
    bb:set("player.level", player:get_level())
    bb:set("player.xp", player:get_xp())
    bb:set("player.max_xp", player:get_max_xp())
    bb:set("player.class_id", player:get_class())
    bb:set("player.spec_id", spec_id)
    local faction_id = player:get_faction_id()
    bb:set("player.faction_id", faction_id)
    bb:set("player.faction_team", FactionResolver.resolve_team(faction_id))

    bb:set("context.ui_map_id", map_id)
    bb:set("context.instance_type", instance_type)
    bb:set("context.position", pos)

    sensor_snapshot.player = {
        health = bb:get("player.health", 0),
        max_health = bb:get("player.max_health", 0),
        in_combat = bb:get("player.in_combat", false),
        level = bb:get("player.level", 0),
        xp = bb:get("player.xp", 0),
        max_xp = bb:get("player.max_xp", 0),
        class_id = bb:get("player.class_id", 0),
        spec_id = bb:get("player.spec_id", 0),
    }

    sensor_snapshot.context = {
        ui_map_id = map_id,
        instance_type = instance_type,
        x = pos and pos.x or 0,
        y = pos and pos.y or 0,
        z = pos and pos.z or 0,
    }

    return sensor_snapshot
end

---@param a table|nil
---@param b table|nil
---@return number
function Sensors.distance_3d(a, b)
    return Helpers.distance_3d(a, b)
end

return Sensors
