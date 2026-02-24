local Helpers = require("lib/Helpers")
local FactionResolver = require("lib/FactionResolver")
local get_now = require("lib/TimeHelper").get_now
local UnitQueries = require("lib/UnitQueries")
local safe_method = UnitQueries.safe_method
local unwrap_game_object = UnitQueries.unwrap_game_object

---@class SentinelSensors
---@field private _blackboard Blackboard
---@field private _was_dead boolean
local Sensors = {}
Sensors.__index = Sensors

---@param blackboard Blackboard
---@return SentinelSensors
function Sensors:new(blackboard)
    local o = setmetatable({}, Sensors)
    o._blackboard = blackboard
    o._was_dead = false
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

--- Get the player object without the is_valid() gate.
--- Dead/ghost players may fail is_valid() but we still need to detect death state.
---@private
---@return game_object|nil
local function get_raw_player()
    if not core or not core.object_manager or not core.object_manager.get_local_player then
        return nil
    end
    return unwrap_game_object(core.object_manager.get_local_player())
end

---@return table
function Sensors:update()
    local bb = self._blackboard
    local now = get_now()
    bb:set("_time", now)

    local player = get_player()
    bb:set("player.object", player)

    local sensor_snapshot = {
        timestamp = now,
        player_valid = player ~= nil,
    }

    -- Always update death/ghost state, even when is_valid() fails.
    -- Dead/ghost players may be "invalid" to the object manager but we
    -- MUST detect death to trigger corpse recovery.
    if not player then
        local raw = get_raw_player()
        if raw then
            local is_dead = safe_method(raw, "is_dead") or false
            local is_ghost = safe_method(raw, "is_ghost") or false
            bb:set("player.is_dead", is_dead)
            bb:set("player.is_ghost", is_ghost)

            if is_dead or is_ghost then
                -- Update position so ghost navigation works
                local raw_pos = safe_method(raw, "get_position")
                if raw_pos then
                    bb:set("player.position", raw_pos)
                end

                if is_dead and not self._was_dead and raw_pos then
                    bb:set("player.death_position", { x = raw_pos.x, y = raw_pos.y, z = raw_pos.z })
                end
                self._was_dead = true
            elseif self._was_dead then
                self._was_dead = false
                bb:clear("player.death_position")
            end
        end
        return sensor_snapshot
    end

    local pos = safe_method(player, "get_position")
    local target = safe_method(player, "get_target")
    local map_id = (core and core.get_map_id and core.get_map_id()) or 0
    local instance_type = (core and core.get_instance_type and core.get_instance_type()) or "none"
    local spec_id = 0
    if player.get_specialization_id then
        spec_id = tonumber(safe_method(player, "get_specialization_id")) or 0
    elseif core and core.spell_book and core.spell_book.get_specialization_id then
        spec_id = tonumber(core.spell_book.get_specialization_id()) or 0
    end

    bb:set("player.position", pos)
    bb:set("player.target", target)
    bb:set("player.health", safe_method(player, "get_health") or 0)
    bb:set("player.max_health", safe_method(player, "get_max_health") or 1)
    local in_combat = safe_method(player, "is_in_combat") or false
    bb:set("player.in_combat", in_combat)
    local casting = safe_method(player, "is_casting_spell") or false
    local channelling = safe_method(player, "is_channelling_spell") or false
    bb:set("player.is_casting", casting or channelling)

    -- Movement state (always set, default false if method unavailable)
    bb:set("player.is_moving", safe_method(player, "is_moving") or false)

    -- Aggro detection: true if player is in combat or any nearby enemy is in combat with us
    bb:set("combat.has_aggro", in_combat)
    bb:set("player.level", safe_method(player, "get_level") or 1)
    bb:set("player.xp", safe_method(player, "get_xp") or 0)
    bb:set("player.max_xp", safe_method(player, "get_max_xp") or 1)
    bb:set("player.class_id", safe_method(player, "get_class") or 0)
    bb:set("player.spec_id", spec_id)
    local faction_id = safe_method(player, "get_faction_id") or 0
    bb:set("player.faction_id", faction_id)
    bb:set("player.faction_team", FactionResolver.resolve_team(faction_id))

    bb:set("player.durability_pct", tonumber(safe_method(player, "get_durability_pct")) or 1.0)

    -- Death state tracking: cache death position on alive→dead transition
    local is_dead = safe_method(player, "is_dead") or false
    local is_ghost = safe_method(player, "is_ghost") or false
    bb:set("player.is_dead", is_dead)
    bb:set("player.is_ghost", is_ghost)

    if is_dead and not self._was_dead and pos then
        bb:set("player.death_position", { x = pos.x, y = pos.y, z = pos.z })
    elseif not is_dead and not is_ghost then
        self._was_dead = false
        bb:clear("player.death_position")
    end
    if is_dead or is_ghost then
        self._was_dead = true
    end

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
