local Helpers = require("lib/Helpers")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

local OBJECT_UNWRAP_KEYS = {
    "object",
    "raw_object",
    "game_object",
}

---@param obj any
---@param method string
---@param ... any
---@return any
local function safe_method(obj, method, ...)
    if not obj then
        return nil
    end
    local fn = obj[method]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, obj, ...)
    if not ok then
        return nil
    end
    return value
end

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

---@class TargetingService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _current_target game_object|nil
local TargetingService = {}
TargetingService.__index = TargetingService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table
---@return TargetingService
function TargetingService:new(event_bus, blackboard, cfg)
    local o = setmetatable({}, TargetingService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._current_target = nil
    return o
end

---@return number
function TargetingService:get_adaptive_radius()
    local base = tonumber(self._cfg.base_radius) or 45.0
    local max_radius = tonumber(self._cfg.max_radius) or 75.0

    -- Expand radius while out of combat and no target to improve XP/h acquisition uptime.
    local in_combat = self._blackboard:get("player.in_combat", false)
    local has_target = self._current_target ~= nil
    local boost = (not in_combat and not has_target) and 10.0 or 0.0
    return math.min(max_radius, base + boost)
end

---@private
---@param unit game_object
---@param player game_object
---@return boolean
local function can_engage(unit, player)
    local player_can_attack = safe_method(player, "can_attack", unit)
    local unit_can_attack = safe_method(unit, "can_attack", player)
    local player_enemy_with = safe_method(player, "is_enemy_with", unit)
    local unit_enemy_with = safe_method(unit, "is_enemy_with", player)

    -- Different mob families/expansions can report hostility flags inconsistently.
    -- Allow engagement if any reliable attackability/hostility signal is positive.
    if player_can_attack == true
        or unit_can_attack == true
        or player_enemy_with == true
        or unit_enemy_with == true then
        return true
    end

    return false
end

---@private
---@param unit game_object
---@param player game_object
---@return boolean
local function is_engaged_by_others(unit, player)
    if safe_method(unit, "is_in_combat") ~= true then
        return false
    end

    local unit_target = unwrap_game_object(safe_method(unit, "get_target"))
    if not unit_target then
        -- Out-of-party contested combat; safest default is skip.
        return true
    end

    if unit_target == player then
        return false
    end

    local player_pet = unwrap_game_object(safe_method(player, "get_pet"))
    if player_pet and unit_target == player_pet then
        return false
    end

    return true
end

---@private
---@param unit game_object
---@param player game_object
---@return boolean
local function is_valid_target(unit, player)
    if not unit then
        return false
    end
    if safe_method(unit, "is_valid") ~= true then
        return false
    end
    if safe_method(unit, "is_unit") ~= true then
        return false
    end
    if safe_method(unit, "is_dead") == true or safe_method(unit, "is_ghost") == true then
        return false
    end
    if unit == player then
        return false
    end
    if is_engaged_by_others(unit, player) then
        return false
    end
    if not can_engage(unit, player) then
        return false
    end
    return true
end

---@param target game_object
---@return number
function TargetingService:score_target(target)
    local player = self._blackboard:get("player.object")
    if not player then
        return -math.huge
    end

    local player_pos = self._blackboard:get("player.position")
    local target_pos = safe_method(target, "get_position")
    if not target_pos then
        return -math.huge
    end
    local distance = Helpers.distance_3d(player_pos, target_pos)

    local target_hp = math.max(1, tonumber(safe_method(target, "get_health")) or 1)
    local target_max_hp = math.max(1, tonumber(safe_method(target, "get_max_health")) or target_hp)
    local hp_ratio = target_hp / target_max_hp

    local player_level = tonumber(safe_method(player, "get_level")) or 1
    local target_level = tonumber(safe_method(target, "get_level")) or player_level
    local level_delta = target_level - player_level

    local classification = tonumber(safe_method(target, "get_classification")) or 0
    local elite_risk = (classification == 1 or classification == 2 or classification == 3) and 1.0 or 0.0

    local weights = self._cfg.score_weights or {}
    local w_kill = tonumber(weights.kill_speed) or 0.40
    local w_loot = tonumber(weights.loot_value) or 0.20
    local w_travel = tonumber(weights.travel_cost) or 0.30
    local w_risk = tonumber(weights.risk) or 0.10

    local kill_speed = 1.0 - hp_ratio
    local loot_value = (target_level >= player_level) and 1.0 or 0.6
    local travel_cost = distance / math.max(1.0, tonumber(self._cfg.max_radius) or 75.0)
    local risk = math.max(0, level_delta * 0.2) + elite_risk

    local score = (kill_speed * w_kill) + (loot_value * w_loot) - (travel_cost * w_travel) - (risk * w_risk)

    self._event_bus:emit(Events.TARGET_SCORE_DEBUG, {
        target_id = tonumber(safe_method(target, "get_npc_id")) or 0,
        score = score,
        kill_speed = kill_speed,
        loot_value = loot_value,
        travel_cost = travel_cost,
        risk = risk,
    })

    return score
end

---@return game_object|nil
---@return string|nil
function TargetingService:acquire_target()
    local player = unwrap_game_object(self._blackboard:get("player.object"))
    if not player or safe_method(player, "is_valid") ~= true then
        return nil, ErrorCodes.TARGET_NOT_FOUND
    end

    local objects = {}
    if core and core.object_manager and core.object_manager.get_visible_objects then
        local ok_objects, value = pcall(core.object_manager.get_visible_objects)
        if ok_objects and type(value) == "table" then
            objects = value
        end
    end
    local radius = self:get_adaptive_radius()
    local player_pos = self._blackboard:get("player.position")

    local best_target = nil
    local best_score = -math.huge
    local nearby_combat_count = 0

    for i = 1, #objects do
        local candidate = unwrap_game_object(objects[i])
        if is_valid_target(candidate, player) then
            local candidate_pos = safe_method(candidate, "get_position")
            local dist = Helpers.distance_3d(player_pos, candidate_pos)
            if dist <= radius then
                if dist <= 10.0 then
                    nearby_combat_count = nearby_combat_count + 1
                end
                local score = self:score_target(candidate)
                if score > best_score then
                    best_score = score
                    best_target = candidate
                end
            end
        end
    end

    if not best_target then
        self._current_target = nil
        self._blackboard:clear("combat.target")
        self._blackboard:set("combat.enemy_count", 0)
        return nil, ErrorCodes.TARGET_NOT_FOUND
    end

    self._current_target = best_target
    self._blackboard:set("combat.target", best_target)
    self._blackboard:set("combat.enemy_count", math.max(1, nearby_combat_count))
    self._event_bus:emit(Events.TARGET_ACQUIRED, {
        timestamp = (core and core.time and core.time()) or 0,
        target_name = tostring(safe_method(best_target, "get_name") or "unknown"),
        target_level = tonumber(safe_method(best_target, "get_level")) or 0,
        score = best_score,
    })

    return best_target, nil
end

---@return game_object|nil
function TargetingService:get_target()
    if self._current_target and safe_method(self._current_target, "is_valid") == true then
        if safe_method(self._current_target, "is_dead") ~= true then
            return self._current_target
        end
    end
    return nil
end

function TargetingService:clear_target(reason)
    if self._current_target then
        self._event_bus:emit(Events.TARGET_LOST, {
            timestamp = (core and core.time and core.time()) or 0,
            reason = reason,
        })
    end
    self._current_target = nil
    self._blackboard:clear("combat.target")
    self._blackboard:set("combat.enemy_count", 0)
end

function TargetingService:update()
    local target = self:get_target()
    if target then
        self._blackboard:set("combat.target", target)
        local current_count = tonumber(self._blackboard:get("combat.enemy_count", 0)) or 0
        if current_count <= 0 then
            self._blackboard:set("combat.enemy_count", 1)
        end
    end
end

return TargetingService
