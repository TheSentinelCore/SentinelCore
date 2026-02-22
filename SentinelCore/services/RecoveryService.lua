local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

---@class RecoveryService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _active boolean
---@field private _error_code string|nil
---@field private _error_detail table|nil
---@field private _attempts_used number
---@field private _stage string
---@field private _next_restart_at number
local RecoveryService = {}
RecoveryService.__index = RecoveryService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table
---@return RecoveryService
function RecoveryService:new(event_bus, blackboard, cfg)
    local o = setmetatable({}, RecoveryService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._active = false
    o._error_code = nil
    o._error_detail = nil
    o._attempts_used = 0
    o._stage = "idle"
    o._next_restart_at = 0
    return o
end

---@return boolean
function RecoveryService:is_active()
    return self._active == true
end

---@return number
function RecoveryService:get_attempts_used()
    return self._attempts_used
end

---@return string|nil
function RecoveryService:get_error_code()
    return self._error_code
end

---@param error_code string
---@param detail? table
function RecoveryService:report_critical(error_code, detail)
    if self._active then
        return
    end

    self._active = true
    self._error_code = error_code
    self._error_detail = detail
    self._stage = "reported"
    self._next_restart_at = 0

    self._event_bus:emit(Events.RECOVERY_STARTED, {
        timestamp = (core and core.time and core.time()) or 0,
        error_code = error_code,
        detail = detail,
    })
end

---@param now number
---@return table|nil
function RecoveryService:update(now)
    now = now or ((core and core.time and core.time()) or 0)
    if not self._active then
        return nil
    end

    local max_attempts = tonumber(self._cfg.auto_restart_max_attempts) or 3
    local backoff = self._cfg.auto_restart_backoff_secs or { 2, 5, 10 }

    if self._stage == "reported" then
        local idx = math.min(#backoff, self._attempts_used + 1)
        local delay = tonumber(backoff[idx]) or 1
        self._next_restart_at = now + delay
        self._stage = "paused"
        return {
            action = "pause",
            error_code = self._error_code,
            stage = ErrorCodes.RECOVERY_PAUSED,
        }
    end

    if self._stage == "paused" then
        if self._attempts_used >= max_attempts then
            self._stage = "failed"
            self._event_bus:emit(Events.RECOVERY_ESCALATED, {
                timestamp = now,
                stage = "failed",
                error_code = ErrorCodes.RECOVERY_ATTEMPTS_EXHAUSTED,
            })
            return {
                action = "fail",
                error_code = ErrorCodes.RECOVERY_ATTEMPTS_EXHAUSTED,
                stage = "failed",
            }
        end

        if self._next_restart_at == 0 then
            local idx = math.min(#backoff, self._attempts_used + 1)
            local delay = tonumber(backoff[idx]) or 1
            self._next_restart_at = now + delay
        end

        if now >= self._next_restart_at then
            self._attempts_used = self._attempts_used + 1
            self._stage = "restarting"
            local next_idx = math.min(#backoff, self._attempts_used + 1)
            local next_delay = tonumber(backoff[next_idx]) or 1
            self._next_restart_at = now + next_delay
            self._event_bus:emit(Events.RECOVERY_ESCALATED, {
                timestamp = now,
                stage = "restart",
                attempts_used = self._attempts_used,
                error_code = ErrorCodes.RECOVERY_RESTARTING,
            })
            return {
                action = "restart",
                attempts_used = self._attempts_used,
                error_code = ErrorCodes.RECOVERY_RESTARTING,
                stage = "restart",
            }
        end

        return nil
    end

    if self._stage == "restarting" then
        return nil
    end

    if self._stage == "failed" then
        return {
            action = "fail",
            error_code = ErrorCodes.RECOVERY_ATTEMPTS_EXHAUSTED,
            stage = "failed",
        }
    end

    return nil
end

---@param success boolean
function RecoveryService:complete_restart_attempt(success)
    if not self._active then
        return
    end

    if success then
        self._active = false
        self._stage = "idle"
        self._error_code = nil
        self._error_detail = nil
        self._next_restart_at = 0
        self._event_bus:emit(Events.RECOVERY_COMPLETED, {
            timestamp = (core and core.time and core.time()) or 0,
            attempts_used = self._attempts_used,
        })
        self._attempts_used = 0
        return
    end

    self._stage = "paused"
end

function RecoveryService:reset()
    self._active = false
    self._error_code = nil
    self._error_detail = nil
    self._attempts_used = 0
    self._stage = "idle"
    self._next_restart_at = 0
end

return RecoveryService
