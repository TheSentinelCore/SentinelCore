local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

---@class LootService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _state string
---@field private _target game_object|nil
---@field private _started_at number
---@field private _attempts number
---@field private _last_attempt_at number
---@field private _last_error string|nil
local LootService = {}
LootService.__index = LootService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table
---@return LootService
function LootService:new(event_bus, blackboard, cfg)
    local o = setmetatable({}, LootService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._state = "idle"
    o._target = nil
    o._started_at = 0
    o._attempts = 0
    o._last_attempt_at = 0
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
    if not target then
        return false, ErrorCodes.LOOT_FAILED
    end

    local now = (core and core.time and core.time()) or 0
    self._state = "looting"
    self._target = target
    self._started_at = now
    self._attempts = 0
    self._last_attempt_at = 0
    self._last_error = nil

    self._event_bus:emit(Events.LOOT_STARTED, {
        timestamp = now,
        target_name = target.get_name and target:get_name() or "unknown",
    })

    return true, nil
end

function LootService:reset()
    self._state = "idle"
    self._target = nil
    self._attempts = 0
    self._last_attempt_at = 0
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

    if now - self._started_at > timeout then
        self._state = "failed"
        self._last_error = ErrorCodes.LOOT_TIMEOUT
        self._event_bus:emit(Events.LOOT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        return false, self._last_error
    end

    if not self._target or not self._target.is_valid or not self._target:is_valid() then
        self._state = "failed"
        self._last_error = ErrorCodes.LOOT_FAILED
        self._event_bus:emit(Events.LOOT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        return false, self._last_error
    end

    if self._attempts < retry_limit and (self._last_attempt_at == 0 or (now - self._last_attempt_at) >= retry_delay) then
        self._attempts = self._attempts + 1
        self._last_attempt_at = now
        if core and core.input and core.input.loot_object then
            core.input.loot_object(self._target)
        end
    end

    local loot_count = 0
    if core and core.game_ui and core.game_ui.get_loot_item_count then
        loot_count = tonumber(core.game_ui.get_loot_item_count()) or 0
    end

    if loot_count > 0 then
        if core and core.input and core.input.loot_item then
            for i = 1, loot_count do
                core.input.loot_item(i)
            end
        end
        if core and core.input and core.input.close_loot then
            core.input.close_loot()
        end

        self._state = "completed"
        self._event_bus:emit(Events.LOOT_COMPLETED, {
            timestamp = now,
            looted_items = loot_count,
        })
        return true, nil
    end

    -- Empty loot window can still be a successful completion once interaction was attempted.
    if self._attempts >= 1 and now - self._last_attempt_at >= retry_delay then
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
