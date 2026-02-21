local Helpers = require("lib/Helpers")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

---@class CombatService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _nav NavigationAdapter
---@field private _targeting TargetingService
---@field private _rotation RotationEngine
---@field private _cfg table
---@field private _state string
---@field private _active_target game_object|nil
---@field private _started_at number
---@field private _pull_started_at number
---@field private _pull_sent boolean
---@field private _last_error string|nil
local CombatService = {}
CombatService.__index = CombatService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param navigation NavigationAdapter
---@param targeting TargetingService
---@param rotation RotationEngine
---@param cfg table
---@return CombatService
function CombatService:new(event_bus, blackboard, navigation, targeting, rotation, cfg)
    local o = setmetatable({}, CombatService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav = navigation
    o._targeting = targeting
    o._rotation = rotation
    o._cfg = cfg or {}
    o._state = "idle"
    o._active_target = nil
    o._started_at = 0
    o._pull_started_at = 0
    o._pull_sent = false
    o._last_error = nil
    return o
end

---@return boolean
function CombatService:is_active()
    return self._state == "pull" or self._state == "combat"
end

---@return string
function CombatService:get_state()
    return self._state
end

---@return string|nil
function CombatService:get_last_error()
    return self._last_error
end

---@param target game_object
---@return boolean
---@return string|nil
function CombatService:start(target)
    if not target then
        return false, ErrorCodes.TARGET_NOT_FOUND
    end

    local now = (core and core.time and core.time()) or 0
    self._active_target = target
    self._blackboard:set("combat.target", target)
    self._state = "pull"
    self._started_at = now
    self._pull_started_at = now
    self._pull_sent = false
    self._last_error = nil

    self._event_bus:emit(Events.PULL_STARTED, {
        timestamp = now,
        target_name = target.get_name and target:get_name() or "unknown",
    })

    return true, nil
end

function CombatService:reset()
    self._state = "idle"
    self._active_target = nil
    self._pull_sent = false
    self._blackboard:clear("combat.target")
end

---@private
---@param target game_object
---@return boolean
function CombatService:_target_valid(target)
    if not target or not target.is_valid or not target:is_valid() then
        return false
    end
    if target:is_dead() or target:is_ghost() then
        return false
    end
    return true
end

---@private
---@param target game_object
---@return number
function CombatService:_distance_to_target(target)
    local player_pos = self._blackboard:get("player.position")
    local target_pos = target and target.get_position and target:get_position() or nil
    return Helpers.distance_3d(player_pos, target_pos)
end

---@private
---@param target game_object
---@return boolean
---@return string|nil
function CombatService:_execute_pull(target)
    local now = (core and core.time and core.time()) or 0
    local pull_timeout = tonumber(self._cfg.pull_timeout) or 8.0
    if now - self._pull_started_at > pull_timeout then
        return false, ErrorCodes.PULL_FAILED
    end

    local pull_profile = self._rotation:get_pull_profile()
    local pull_range = tonumber(pull_profile.max_pull_range) or 30
    local distance = self:_distance_to_target(target)

    if distance > pull_range then
        local target_pos = target:get_position()
        self._nav:move_to(target_pos)
        return true, nil
    end

    if core and core.input and core.input.set_target then
        core.input.set_target(target)
    end

    if pull_profile.pull_spell_id then
        local ok, err = self._rotation:tick_once()
        if not ok and err ~= ErrorCodes.CAST_GUARD_BLOCKED then
            return false, err
        end
    end

    self._pull_sent = true
    self._state = "combat"
    return true, nil
end

---@return boolean
---@return string|nil
function CombatService:update()
    if self._state == "idle" then
        return true, nil
    end

    local now = (core and core.time and core.time()) or 0
    local timeout = tonumber(self._cfg.combat_timeout) or 30.0

    local target = self._active_target
    if not target then
        target = self._targeting:get_target()
        self._active_target = target
    end

    if not target then
        self._last_error = ErrorCodes.TARGET_LOST
        self._event_bus:emit(Events.COMBAT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        self:reset()
        return false, self._last_error
    end

    if target:is_dead() then
        self._event_bus:emit(Events.KILL_CONFIRMED, {
            timestamp = now,
            target_name = target:get_name(),
        })
        self:reset()
        return true, nil
    end

    if not self:_target_valid(target) then
        self._last_error = ErrorCodes.TARGET_LOST
        self._event_bus:emit(Events.COMBAT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        self:reset()
        return false, self._last_error
    end

    if now - self._started_at > timeout then
        self._last_error = ErrorCodes.COMBAT_TIMEOUT
        self._event_bus:emit(Events.COMBAT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        self:reset()
        return false, self._last_error
    end

    if self._state == "pull" then
        local ok, err = self:_execute_pull(target)
        if not ok then
            self._last_error = err or ErrorCodes.PULL_FAILED
            self._event_bus:emit(Events.COMBAT_FAILED, {
                timestamp = now,
                error_code = self._last_error,
            })
            self:reset()
            return false, self._last_error
        end
        return true, nil
    end

    if self._state == "combat" then
        local ok, err = self._rotation:tick_once()
        if not ok and err ~= ErrorCodes.CAST_GUARD_BLOCKED then
            self._last_error = err
            self._event_bus:emit(Events.COMBAT_FAILED, {
                timestamp = now,
                error_code = err,
            })
            self:reset()
            return false, err
        end
        return true, nil
    end

    return true, nil
end

return CombatService
