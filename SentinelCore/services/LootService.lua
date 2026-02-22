local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")
local Helpers = require("lib/Helpers")

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

---@class LootService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _nav NavigationAdapter|nil
---@field private _state string
---@field private _target game_object|nil
---@field private _started_at number
---@field private _attempts number
---@field private _last_attempt_at number
---@field private _approach_started_at number
---@field private _approach_last_move_at number
---@field private _approaching boolean
---@field private _last_error string|nil
local LootService = {}
LootService.__index = LootService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table
---@param navigation? NavigationAdapter
---@return LootService
function LootService:new(event_bus, blackboard, cfg, navigation)
    local o = setmetatable({}, LootService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._nav = navigation
    o._state = "idle"
    o._target = nil
    o._started_at = 0
    o._attempts = 0
    o._last_attempt_at = 0
    o._approach_started_at = 0
    o._approach_last_move_at = 0
    o._approaching = false
    o._last_error = nil
    return o
end

---@return boolean
function LootService:is_active()
    return self._state == "looting"
end

---@return string
function LootService:get_state()
    return self._state
end

---@return string|nil
function LootService:get_last_error()
    return self._last_error
end

---@param target game_object
---@return boolean
---@return string|nil
function LootService:start(target)
    if not target or safe_method(target, "is_valid") ~= true then
        return false, ErrorCodes.LOOT_FAILED
    end

    local now = (core and core.time and core.time()) or 0
    self._state = "looting"
    self._target = target
    self._started_at = now
    self._attempts = 0
    self._last_attempt_at = 0
    self._approach_started_at = 0
    self._approach_last_move_at = 0
    self._approaching = false
    self._last_error = nil

    self._event_bus:emit(Events.LOOT_STARTED, {
        timestamp = now,
        target_name = safe_target_name(target),
    })

    return true, nil
end

function LootService:reset()
    self._state = "idle"
    self._target = nil
    self._attempts = 0
    self._last_attempt_at = 0
    self._approach_started_at = 0
    self._approach_last_move_at = 0
    self._approaching = false
end

---@private
---@return number|nil
function LootService:_distance_to_target()
    local player_pos = self._blackboard and self._blackboard.get and self._blackboard:get("player.position") or nil
    local corpse_pos = safe_method(self._target, "get_position")
    return Helpers.distance_3d(player_pos, corpse_pos)
end

---@private
---@param now number
---@return boolean
---@return string|nil
---@return boolean
function LootService:_ensure_loot_range(now)
    local interact_range = tonumber(self._cfg.loot_interact_range) or 5.0
    local max_distance = tonumber(self._cfg.loot_approach_max_distance) or 45.0
    local approach_timeout = tonumber(self._cfg.loot_approach_timeout) or 2.5
    local approach_reissue = tonumber(self._cfg.loot_approach_reissue_cooldown) or 0.75

    local distance = self:_distance_to_target()
    if distance == nil then
        return false, ErrorCodes.LOOT_FAILED, false
    end

    if distance <= interact_range then
        if self._approaching and self._nav and self._nav.stop then
            pcall(self._nav.stop, self._nav)
        end
        self._approaching = false
        self._approach_started_at = 0
        return true, nil, false
    end

    if distance > max_distance then
        return false, ErrorCodes.LOOT_FAILED, false
    end

    if not self._nav or type(self._nav.move_to) ~= "function" then
        return false, ErrorCodes.LOOT_FAILED, false
    end

    if self._approach_started_at <= 0 then
        self._approach_started_at = now
    end
    if (now - self._approach_started_at) > approach_timeout then
        return false, ErrorCodes.LOOT_FAILED, false
    end

    if self._approach_last_move_at <= 0 or (now - self._approach_last_move_at) >= approach_reissue then
        local corpse_pos = safe_method(self._target, "get_position")
        if corpse_pos then
            pcall(self._nav.move_to, self._nav, corpse_pos)
            self._approach_last_move_at = now
        end
    end

    self._approaching = true
    return true, nil, true
end

---@return boolean
---@return string|nil
function LootService:update()
    if self._state ~= "looting" then
        return true, nil
    end

    local now = (core and core.time and core.time()) or 0
    local timeout = tonumber(self._cfg.loot_timeout) or 8.0
    local retry_limit = tonumber(self._cfg.interaction_retry_limit) or 3
    local retry_delay = tonumber(self._cfg.interaction_retry_delay) or 0.6
    local zero_loot_confirm = tonumber(self._cfg.zero_loot_confirm_delay) or 0.2

    if now - self._started_at > timeout then
        self._state = "failed"
        self._last_error = ErrorCodes.LOOT_TIMEOUT
        self._event_bus:emit(Events.LOOT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        return false, self._last_error
    end

    if not self._target or safe_method(self._target, "is_valid") ~= true then
        self._state = "failed"
        self._last_error = ErrorCodes.LOOT_FAILED
        self._event_bus:emit(Events.LOOT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        return false, self._last_error
    end

    local range_ok, range_err, approaching = self:_ensure_loot_range(now)
    if not range_ok then
        self._state = "failed"
        self._last_error = range_err or ErrorCodes.LOOT_FAILED
        self._event_bus:emit(Events.LOOT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        return false, self._last_error
    end
    if approaching == true then
        return true, nil
    end

    if self._attempts < retry_limit and (self._last_attempt_at == 0 or (now - self._last_attempt_at) >= retry_delay) then
        self._attempts = self._attempts + 1
        self._last_attempt_at = now
        if core and core.input and core.input.loot_object then
            pcall(core.input.loot_object, self._target)
        end
    end

    local loot_count = 0
    if core and core.game_ui and core.game_ui.get_loot_item_count then
        loot_count = tonumber(core.game_ui.get_loot_item_count()) or 0
    end

    if loot_count > 0 then
        if core and core.input and core.input.loot_item then
            for i = 1, loot_count do
                pcall(core.input.loot_item, i)
            end
        end
        if core and core.input and core.input.close_loot then
            pcall(core.input.close_loot)
        end

        self._state = "completed"
        self._event_bus:emit(Events.LOOT_COMPLETED, {
            timestamp = now,
            looted_items = loot_count,
        })
        return true, nil
    end

    -- Empty loot window can still be a successful completion once interaction was attempted.
    if self._attempts >= retry_limit and now - self._last_attempt_at >= zero_loot_confirm then
        self._state = "completed"
        self._event_bus:emit(Events.LOOT_COMPLETED, {
            timestamp = now,
            looted_items = 0,
        })
        return true, nil
    end

    return true, nil
end

return LootService
