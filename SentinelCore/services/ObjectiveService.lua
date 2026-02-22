local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

---@private
---@param status any
---@return string
local function normalize_status(status)
    local normalized = tostring(status or "running"):lower()
    if normalized == "success" or normalized == "completed" or normalized == "complete" or normalized == "done" then
        return "success"
    end
    if normalized == "failure" or normalized == "failed" or normalized == "error" then
        return "failure"
    end
    if normalized == "idle" or normalized == "none" then
        return "idle"
    end
    return "running"
end

---@private
---@param objective any
---@return table
local function describe_objective(objective)
    if type(objective) ~= "table" then
        return {
            id = tostring(objective or ""),
            kind = "custom",
            label = tostring(objective or "objective"),
        }
    end

    local summary = {
        id = tostring(objective.id or objective.key or ""),
        kind = tostring(objective.kind or objective.type or "custom"),
        label = tostring(objective.label or objective.name or "objective"),
    }

    if type(objective.index) == "number" then
        summary.index = objective.index
    end
    if type(objective.queue_size) == "number" then
        summary.queue_size = objective.queue_size
    end
    if type(objective.destination) == "table" then
        summary.destination = {
            x = tonumber(objective.destination.x) or 0,
            y = tonumber(objective.destination.y) or 0,
            z = tonumber(objective.destination.z) or 0,
        }
    end

    return summary
end

---@class ObjectiveService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _services table|nil
---@field private _mode_id string
---@field private _provider table|nil
---@field private _provider_id string
---@field private _active_objective table|nil
---@field private _active_started_at number
---@field private _last_progress_at number
---@field private _state string
---@field private _last_error string|nil
local ObjectiveService = {}
ObjectiveService.__index = ObjectiveService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table|nil
---@return ObjectiveService
function ObjectiveService:new(event_bus, blackboard, cfg)
    local o = setmetatable({}, ObjectiveService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._services = nil
    o._mode_id = "grind"
    o._provider = nil
    o._provider_id = ""
    o._active_objective = nil
    o._active_started_at = 0
    o._last_progress_at = 0
    o._state = "idle"
    o._last_error = nil
    o:_write_blackboard_state()
    return o
end

---@private
---@return number
function ObjectiveService:_now()
    return (core and core.time and core.time()) or 0
end

---@private
---@param objective table|nil
function ObjectiveService:_publish_selected(objective)
    if not objective then
        return
    end
    self._event_bus:emit(Events.OBJECTIVE_SELECTED, {
        timestamp = self:_now(),
        mode = self._mode_id,
        provider_id = self._provider_id,
        objective = describe_objective(objective),
    })
end

---@private
---@param objective table|nil
---@param detail table|nil
function ObjectiveService:_publish_progress(objective, detail)
    if not objective then
        return
    end
    self._event_bus:emit(Events.OBJECTIVE_PROGRESS, {
        timestamp = self:_now(),
        mode = self._mode_id,
        provider_id = self._provider_id,
        objective = describe_objective(objective),
        detail = detail,
    })
end

---@private
---@param objective table|nil
---@param detail table|nil
function ObjectiveService:_publish_completed(objective, detail)
    if not objective then
        return
    end
    self._event_bus:emit(Events.OBJECTIVE_COMPLETED, {
        timestamp = self:_now(),
        mode = self._mode_id,
        provider_id = self._provider_id,
        objective = describe_objective(objective),
        detail = detail,
    })
end

---@private
---@param objective table|nil
---@param error_code string
---@param detail table|nil
function ObjectiveService:_publish_failed(objective, error_code, detail)
    self._event_bus:emit(Events.OBJECTIVE_FAILED, {
        timestamp = self:_now(),
        mode = self._mode_id,
        provider_id = self._provider_id,
        objective = describe_objective(objective),
        error_code = error_code,
        detail = detail,
    })
end

---@private
---@return string
function ObjectiveService:_resolve_provider_id()
    if not self._provider then
        return ""
    end

    local provider = self._provider
    if type(provider.id) == "function" then
        local ok, value = pcall(provider.id, provider)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end

    if type(provider.PROVIDER_ID) == "string" and provider.PROVIDER_ID ~= "" then
        return provider.PROVIDER_ID
    end

    return tostring(self._mode_id or "mode") .. ".provider"
end

---@private
---@param now number
---@return table
function ObjectiveService:_build_provider_context(now)
    return {
        now = now,
        mode_id = self._mode_id,
        provider_id = self._provider_id,
        blackboard = self._blackboard,
        services = self._services,
        objective = self._active_objective,
    }
end

---@private
function ObjectiveService:_write_blackboard_state()
    self._blackboard:set("objective.mode", self._mode_id)
    self._blackboard:set("objective.provider_id", self._provider_id)
    self._blackboard:set("objective.active", self._active_objective ~= nil)
    self._blackboard:set("objective.state", self._state)
    self._blackboard:set("objective.has_work", self:has_work())

    if self._active_objective then
        self._blackboard:set("objective.current", describe_objective(self._active_objective))
    else
        self._blackboard:clear("objective.current")
    end

    if self._last_error then
        self._blackboard:set("objective.last_error", self._last_error)
    else
        self._blackboard:clear("objective.last_error")
    end
end

---@private
---@param reason string
function ObjectiveService:_abort_active(reason)
    if not self._active_objective then
        return
    end

    local provider = self._provider
    if provider and type(provider.abort) == "function" then
        pcall(provider.abort, provider, self._active_objective, self:_build_provider_context(self:_now()), reason)
    end
end

---@private
---@param objective any
---@param now number
function ObjectiveService:_set_active_objective(objective, now)
    local normalized = objective
    if type(normalized) ~= "table" then
        normalized = {
            id = tostring(objective or ""),
            kind = "custom",
            label = tostring(objective or "objective"),
            payload = objective,
        }
    end

    if normalized.id == nil then
        normalized.id = string.format("%s-%d", tostring(self._provider_id or "provider"), math.floor(now * 1000))
    end
    if normalized.kind == nil then
        normalized.kind = normalized.type or "custom"
    end
    if normalized.label == nil then
        normalized.label = normalized.name or tostring(normalized.kind)
    end

    self._active_objective = normalized
    self._active_started_at = now
    self._last_progress_at = 0
    self._state = "active"
    self._last_error = nil
    self:_publish_selected(normalized)
    self:_write_blackboard_state()
end

---@private
---@param outcome "completed"|"failed"
---@param error_code string|nil
---@param detail table|nil
function ObjectiveService:_clear_active_objective(outcome, error_code, detail)
    local previous = self._active_objective
    if outcome == "completed" then
        self:_publish_completed(previous, detail)
        self._last_error = nil
    elseif outcome == "failed" then
        self._last_error = error_code or ErrorCodes.OBJECTIVE_EXECUTION_FAILED
        self:_publish_failed(previous, self._last_error, detail)
    end

    self._active_objective = nil
    self._active_started_at = 0
    self._last_progress_at = 0
    self._state = "idle"
    self:_write_blackboard_state()
end

---@param mode_id string
---@param provider table|nil
---@param services table|nil
function ObjectiveService:set_mode(mode_id, provider, services)
    self:_abort_active("mode_switch")
    self._active_objective = nil
    self._active_started_at = 0
    self._last_progress_at = 0
    self._state = "idle"
    self._last_error = nil

    self._mode_id = tostring(mode_id or "grind")
    self._provider = provider
    self._services = services
    self._provider_id = self:_resolve_provider_id()

    if self._provider and type(self._provider.on_mode_enter) == "function" then
        pcall(self._provider.on_mode_enter, self._provider, self:_build_provider_context(self:_now()))
    end

    self:_write_blackboard_state()
end

---@return boolean
function ObjectiveService:is_active()
    return self._active_objective ~= nil
end

---@return string
function ObjectiveService:get_state()
    return self._state
end

---@return string|nil
function ObjectiveService:get_last_error()
    return self._last_error
end

---@return table|nil
function ObjectiveService:get_current()
    if not self._active_objective then
        return nil
    end
    return describe_objective(self._active_objective)
end

---@return boolean
function ObjectiveService:has_work()
    if not self._provider then
        return false
    end
    if self._active_objective ~= nil then
        return true
    end

    if type(self._provider.has_work) == "function" then
        local ok, value = pcall(self._provider.has_work, self._provider, self:_build_provider_context(self:_now()))
        if ok then
            return value == true
        end
        return false
    end

    return type(self._provider.acquire) == "function"
end

---@return boolean
---@return string|nil
function ObjectiveService:acquire_next()
    if self._active_objective then
        return true, nil
    end
    if not self._provider or type(self._provider.acquire) ~= "function" then
        return false, ErrorCodes.OBJECTIVE_PROVIDER_INVALID
    end

    local now = self:_now()
    local ok, objective, err = pcall(self._provider.acquire, self._provider, self:_build_provider_context(now))
    if not ok then
        self._last_error = ErrorCodes.OBJECTIVE_EXECUTION_FAILED
        self:_write_blackboard_state()
        return false, self._last_error
    end

    if objective == nil then
        local error_code = err or ErrorCodes.OBJECTIVE_NONE_AVAILABLE
        if error_code ~= ErrorCodes.OBJECTIVE_NONE_AVAILABLE then
            self._last_error = error_code
        end
        self:_write_blackboard_state()
        return false, error_code
    end

    self:_set_active_objective(objective, now)
    return true, nil
end

---@param now? number
---@return string status
---@return string|nil error_code
function ObjectiveService:tick(now)
    now = tonumber(now) or self:_now()

    if not self._provider then
        self._state = "idle"
        self:_write_blackboard_state()
        return "idle", ErrorCodes.OBJECTIVE_PROVIDER_INVALID
    end

    if not self._active_objective then
        local acquired, acquire_err = self:acquire_next()
        if not acquired then
            if acquire_err == ErrorCodes.OBJECTIVE_NONE_AVAILABLE then
                return "idle", acquire_err
            end
            return "failure", acquire_err
        end
    end

    if not self._active_objective then
        return "idle", ErrorCodes.OBJECTIVE_NONE_AVAILABLE
    end

    if type(self._provider.tick) ~= "function" then
        self:_clear_active_objective("failed", ErrorCodes.OBJECTIVE_PROVIDER_INVALID, {
            reason = "missing_tick",
        })
        return "failure", ErrorCodes.OBJECTIVE_PROVIDER_INVALID
    end

    local timeout = tonumber(self._cfg.objective_timeout) or 120.0
    if self._active_started_at > 0 and (now - self._active_started_at) > timeout then
        self:_clear_active_objective("failed", ErrorCodes.ACTION_TIMEOUT, {
            reason = "objective_timeout",
        })
        return "failure", ErrorCodes.ACTION_TIMEOUT
    end

    local ok, status, detail = pcall(
        self._provider.tick,
        self._provider,
        self._active_objective,
        self:_build_provider_context(now)
    )
    if not ok then
        self:_clear_active_objective("failed", ErrorCodes.OBJECTIVE_EXECUTION_FAILED, {
            reason = "provider_tick_exception",
        })
        return "failure", ErrorCodes.OBJECTIVE_EXECUTION_FAILED
    end

    local normalized = normalize_status(status)
    if type(detail) ~= "table" then
        detail = nil
    end

    if normalized == "running" then
        local progress_interval = tonumber(self._cfg.progress_emit_interval) or 1.0
        if self._last_progress_at == 0 or (now - self._last_progress_at) >= progress_interval then
            self._last_progress_at = now
            self:_publish_progress(self._active_objective, detail)
        end
        self._state = "active"
        self:_write_blackboard_state()
        return "running", nil
    end

    if normalized == "success" or normalized == "idle" then
        self:_clear_active_objective("completed", nil, detail)
        return "success", nil
    end

    local error_code = (detail and detail.error_code) or ErrorCodes.OBJECTIVE_EXECUTION_FAILED
    self:_clear_active_objective("failed", error_code, detail)
    return "failure", error_code
end

---@param now? number
---@return boolean
---@return string|nil
function ObjectiveService:update(now)
    if self._active_objective ~= nil then
        self._state = "active"
    elseif self._provider ~= nil then
        self._state = "idle"
    else
        self._state = "idle"
    end

    self:_write_blackboard_state()
    return true, nil
end

---@return table
function ObjectiveService:get_snapshot()
    return {
        mode = self._mode_id,
        provider_id = self._provider_id,
        state = self._state,
        active = self._active_objective ~= nil,
        has_work = self:has_work(),
        objective = self:get_current(),
        last_error = self._last_error,
        started_at = self._active_started_at,
    }
end

function ObjectiveService:reset()
    self:_abort_active("reset")
    self._provider = nil
    self._provider_id = ""
    self._services = nil
    self._active_objective = nil
    self._active_started_at = 0
    self._last_progress_at = 0
    self._state = "idle"
    self._last_error = nil
    self:_write_blackboard_state()
end

return ObjectiveService
