local Helpers = require("lib/Helpers")
local FactionResolver = require("lib/FactionResolver")
local get_now = require("lib/TimeHelper").get_now
local UnitQueries = require("lib/UnitQueries")
local safe_method = UnitQueries.safe_method
local unwrap_game_object = UnitQueries.unwrap_game_object

local _hostile_player_last_detected = false
local _last_zone_id = nil

---@class SentinelSensors
---@field private _blackboard Blackboard
---@field private _was_dead boolean
---@field private _event_bus table|nil
---@field private _events table|nil
local Sensors = {}
Sensors.__index = Sensors

---@param blackboard Blackboard
---@param event_bus table|nil
---@param events table|nil
---@return SentinelSensors
function Sensors:new(blackboard, event_bus, events)
    local o = setmetatable({}, Sensors)
    o._blackboard = blackboard
    o._was_dead = false
    o._event_bus = event_bus
    o._events = events
    o._last_player_level = nil
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
    local current_level = safe_method(player, "get_level") or 1
    bb:set("player.level", current_level)

    -- Level-up detection
    local prev_level = self._last_player_level or current_level
    if current_level > prev_level and prev_level > 0 then
        if self._event_bus then
            self._event_bus:emit("player.level_up", {
                previous_level = prev_level,
                new_level = current_level,
            })
        end
    end
    self._last_player_level = current_level
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

    -- Zone tracking
    local zone_id = nil
    local zone_name = nil
    if core and core.game then
        local ok_z, z = pcall(function()
            return core.game.get_zone_id and core.game.get_zone_id()
                or core.game.get_current_map_id and core.game.get_current_map_id()
                or core.game.map_id and core.game.map_id()
        end)
        if ok_z then zone_id = tonumber(z) end

        local ok_n, n = pcall(function()
            return core.game.get_zone_name and core.game.get_zone_name()
                or core.game.get_current_map_name and core.game.get_current_map_name()
                or ""
        end)
        if ok_n and type(n) == "string" then zone_name = n end
    end

    if zone_id ~= nil then
        bb:set("player.zone_id", zone_id)
        if zone_name then bb:set("player.zone_name", zone_name) end
        if _last_zone_id ~= nil and zone_id ~= _last_zone_id and self._event_bus and self._events then
            self._event_bus:emit(self._events.ZONE_CHANGED, {
                from = _last_zone_id,
                to = zone_id,
                name = zone_name or "",
            })
        end
        _last_zone_id = zone_id
    end

    -- Hostile player detection
    local hostile_player_nearby = false
    local ok_units, all_units = pcall(function()
        return core.object_manager.get_all_units and core.object_manager.get_all_units()
            or {}
    end)
    if ok_units and type(all_units) == "table" then
        local p_pos = bb:get("player.position")
        for i = 1, #all_units do
            local unit = all_units[i]
            if unit then
                local ok_player, is_p = pcall(function() return unit:is_player() end)
                local ok_enemy, is_e = pcall(function() return unit:is_enemy() end)
                if (ok_player and is_p == true) and (ok_enemy and is_e == true) then
                    local u_pos = safe_method(unit, "get_position")
                    if u_pos and p_pos then
                        local dist_sq = (u_pos.x - p_pos.x)^2 + (u_pos.y - p_pos.y)^2
                        if dist_sq < 3600 then
                            hostile_player_nearby = true
                        end
                    end
                end
            end
        end
    end

    bb:set("player.hostile_player_nearby", hostile_player_nearby)
    if hostile_player_nearby and not _hostile_player_last_detected then
        if self._event_bus and self._events then
            self._event_bus:emit(self._events.HOSTILE_PLAYER_DETECTED, { detected = true })
        end
    end
    _hostile_player_last_detected = hostile_player_nearby

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
