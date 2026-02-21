local Events = require("events/Events")

---@class SentinelConsoleLogger
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _enabled boolean
---@field private _history table[]
---@field private _max_history number
local ConsoleLogger = {}
ConsoleLogger.__index = ConsoleLogger

---@param event_bus EventBus
---@param blackboard Blackboard
---@return SentinelConsoleLogger
function ConsoleLogger:new(event_bus, blackboard)
    local o = setmetatable({}, ConsoleLogger)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._enabled = true
    o._history = {}
    o._max_history = 120
    o:_bind()
    return o
end

---@private
---@param level string
---@param message string
---@param event_name? string
function ConsoleLogger:_push_history(level, message, event_name)
    local now = (core and core.time and core.time()) or 0
    local entry = {
        timestamp = now,
        level = level,
        event = event_name or "",
        message = message,
    }

    self._history[#self._history + 1] = entry
    while #self._history > self._max_history do
        table.remove(self._history, 1)
    end
end

---@private
---@param level "info"|"warn"|"error"
---@param message string
---@param event_name? string
function ConsoleLogger:_log(level, message, event_name)
    self:_push_history(level, message, event_name)

    if not self._enabled then
        return
    end

    local prefix = "[SentinelCore] "
    if not core then
        return
    end

    if level == "error" and core.log_error then
        core.log_error(prefix .. message)
        return
    end
    if level == "warn" and core.log_warning then
        core.log_warning(prefix .. message)
        return
    end
    if core.log then
        core.log(prefix .. message)
    end
end

---@private
function ConsoleLogger:_bind()
    self._event_bus:on(Events.STATE_CHANGED, function(data)
        self:_log("info", string.format("state %s -> %s (%s)",
            tostring(data.from),
            tostring(data.to),
            tostring(data.substate_to or "-")), Events.STATE_CHANGED)
    end, { owner = self })

    self._event_bus:on(Events.STARTED, function(data)
        self:_log("info", "started mode=" .. tostring(data and data.mode or "unknown"), Events.STARTED)
    end, { owner = self })

    self._event_bus:on(Events.STOPPED, function(data)
        self:_log("info", "stopped reason=" .. tostring(data and data.reason or "-"), Events.STOPPED)
    end, { owner = self })

    self._event_bus:on(Events.PAUSED, function(data)
        self:_log("warn", "paused reason=" .. tostring(data and data.reason or "-"), Events.PAUSED)
    end, { owner = self })

    self._event_bus:on(Events.RESUMED, function()
        self:_log("info", "resumed", Events.RESUMED)
    end, { owner = self })

    self._event_bus:on(Events.FAILED, function(data)
        self:_log("error", "failed: " .. tostring(data.error_code or "unknown"), Events.FAILED)
    end, { owner = self })

    self._event_bus:on(Events.VENDOR_FAILED, function(data)
        self:_log("warn", "vendor failed: " .. tostring(data.error_code or "unknown"), Events.VENDOR_FAILED)
    end, { owner = self })

    self._event_bus:on(Events.VENDOR_COMPLETED, function()
        self:_log("info", "vendor completed", Events.VENDOR_COMPLETED)
    end, { owner = self })

    self._event_bus:on(Events.CONTEXT_FAILED, function(data)
        self:_log("warn", "context resolve failed: " .. tostring(data.error_code or "unknown"), Events.CONTEXT_FAILED)
    end, { owner = self })

    self._event_bus:on(Events.RECOVERY_STARTED, function(data)
        self:_log("warn", "recovery started: " .. tostring(data and data.error_code or "unknown"), Events.RECOVERY_STARTED)
    end, { owner = self })

    self._event_bus:on(Events.RECOVERY_ESCALATED, function(data)
        self:_log("warn", "recovery escalation: " .. tostring(data and data.stage or "unknown"), Events.RECOVERY_ESCALATED)
    end, { owner = self })

    self._event_bus:on(Events.RECOVERY_COMPLETED, function()
        self:_log("info", "recovery completed", Events.RECOVERY_COMPLETED)
    end, { owner = self })
end

function ConsoleLogger:set_enabled(enabled)
    self._enabled = enabled == true
end

---@param limit? number
---@return table[]
function ConsoleLogger:get_history(limit)
    local out = {}
    local max = tonumber(limit) or #self._history
    if max < 1 then
        return out
    end

    local start_index = math.max(1, #self._history - max + 1)
    for i = start_index, #self._history do
        out[#out + 1] = self._history[i]
    end
    return out
end

function ConsoleLogger:clear_history()
    self._history = {}
end

function ConsoleLogger:destroy()
    self._event_bus:off_owner(self)
end

return ConsoleLogger
