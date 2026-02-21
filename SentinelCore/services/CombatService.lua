local Helpers = require("lib/Helpers")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

---@private
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

---@private
---@param target game_object|nil
---@return string
local function safe_target_name(target)
    local name = safe_method(target, "get_name")
    if type(name) == "string" and name ~= "" then
        return name
    end
    return "unknown"
end

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

---@return boolean
---@return string|nil
function CombatService:run_maintenance()
    if self:is_active() then
        return false, nil
    end
    if not self._rotation or not self._rotation.tick_maintenance_once then
        return false, nil
    end

    local ok_tick, executed, err = pcall(self._rotation.tick_maintenance_once, self._rotation)
    if not ok_tick then
        return false, ErrorCodes.ROTATION_UNAVAILABLE
    end
    if executed == true then
        return true, nil
    end
    if err == ErrorCodes.CAST_GUARD_BLOCKED or err == ErrorCodes.ROTATION_UNAVAILABLE then
        return false, nil
    end
    return false, err
end

---@return boolean
function CombatService:should_hold_for_maintenance()
    if self:is_active() then
        return false
    end
    if not self._rotation or not self._rotation.should_hold_maintenance then
        return false
    end

    local ok, hold = pcall(self._rotation.should_hold_maintenance, self._rotation)
    if not ok or hold ~= true then
        return false
    end

    if self._nav and self._nav.stop then
        pcall(self._nav.stop, self._nav)
    end

    return true
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

    if not self:_target_valid(target) then
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
        target_name = safe_target_name(target),
    })

    if self._nav and self._nav.stop then
        pcall(self._nav.stop, self._nav)
    end

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
    if not target then
        return false
    end

    local valid = safe_method(target, "is_valid")
    if valid ~= true then
        return false
    end

    local dead = safe_method(target, "is_dead")
    if dead == nil or dead == true then
        return false
    end

    local ghost = safe_method(target, "is_ghost")
    if ghost == nil or ghost == true then
        return false
    end

    return true
end

---@private
---@param target game_object
---@return number
function CombatService:_distance_to_target(target)
    local player_pos = self._blackboard:get("player.position")
    local target_pos = safe_method(target, "get_position")
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

    local pull_profile = nil
    local ok_profile, resolved = pcall(self._rotation.get_pull_profile, self._rotation)
    if ok_profile and type(resolved) == "table" then
        pull_profile = resolved
    else
        pull_profile = {}
    end
    local pull_range = tonumber(pull_profile.max_pull_range) or 30
    local distance = self:_distance_to_target(target)

    if distance > pull_range then
        local target_pos = safe_method(target, "get_position")
        if not target_pos then
            return false, ErrorCodes.TARGET_LOST
        end
        self._nav:move_to(target_pos)
        return true, nil
    end

    if self._nav and self._nav.stop then
        pcall(self._nav.stop, self._nav)
    end

    if core and core.input and core.input.set_target then
        pcall(core.input.set_target, target)
    end

    if pull_profile.pull_spell_id then
        local ok_call, ok, err = pcall(self._rotation.tick_once, self._rotation)
        if not ok_call then
            return false, ErrorCodes.ROTATION_UNAVAILABLE
        end
        if not ok and err ~= ErrorCodes.CAST_GUARD_BLOCKED then
            return false, err
        end
    end

    local player = self._blackboard:get("player.object")
    local player_in_combat = safe_method(player, "is_in_combat") == true
        or self._blackboard:get("player.in_combat", false) == true
    local target_in_combat = safe_method(target, "is_in_combat") == true

    if pull_profile.pull_spell_id then
        -- Do not advance to combat state until pull has actually engaged combat.
        if not player_in_combat and not target_in_combat then
            return true, nil
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
        local ok_get, resolved = pcall(self._targeting.get_target, self._targeting)
        if ok_get then
            target = resolved
        end
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

    local target_dead = safe_method(target, "is_dead")
    if target_dead == true then
        self._blackboard:set("loot.pending_target", target)
        self._event_bus:emit(Events.KILL_CONFIRMED, {
            timestamp = now,
            target_name = safe_target_name(target),
        })
        self:reset()
        return true, nil
    end

    if target_dead == nil then
        self._last_error = ErrorCodes.TARGET_LOST
        self._event_bus:emit(Events.COMBAT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        self:reset()
        return false, self._last_error
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
        if self._nav and self._nav.stop then
            pcall(self._nav.stop, self._nav)
        end
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
        if self._nav and self._nav.stop then
            pcall(self._nav.stop, self._nav)
        end
        local ok_call, ok, err = pcall(self._rotation.tick_once, self._rotation)
        if not ok_call then
            self._last_error = ErrorCodes.ROTATION_UNAVAILABLE
            self._event_bus:emit(Events.COMBAT_FAILED, {
                timestamp = now,
                error_code = self._last_error,
            })
            self:reset()
            return false, self._last_error
        end
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
