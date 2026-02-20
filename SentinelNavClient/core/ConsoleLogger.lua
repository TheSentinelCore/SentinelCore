-- ConsoleLogger.lua
-- Centralized console logging adapter for EventBus-driven NavClient architecture.
-- Converts nav.* events into human-readable core.log/core.log_warning/core.log_error lines.

local Events = require("events/Events")

local ConsoleLogger = {}
ConsoleLogger.__index = ConsoleLogger

local PREFIX = "[SentinelNavClient] "
local LOG_SEVERITY = {
    ERROR = 0,
    WARN = 1,
    INFO = 2,
    DEBUG = 3,
}

local function format_pos(pos)
    if not pos then return "(?, ?, ?)" end
    local x = tonumber(pos.x) or 0
    local y = tonumber(pos.y) or 0
    local z = tonumber(pos.z) or 0
    return string.format("(%.1f, %.1f, %.1f)", x, y, z)
end

local function format_full_state(state, substate, sub_substate)
    local s = tostring(state or "unknown")
    if substate then s = s .. "." .. tostring(substate) end
    if sub_substate then s = s .. "." .. tostring(sub_substate) end
    return s
end

function ConsoleLogger:new(event_bus, blackboard)
    local o = setmetatable({}, ConsoleLogger)
    o._event_bus = event_bus
    o._bb = blackboard
    o:_subscribe()
    return o
end

function ConsoleLogger:_is_verbose()
    if not self._bb then return false end
    return self._bb:get("config.debug_verbose", false) == true
end

function ConsoleLogger:_get_min_severity()
    if not self._bb then
        return LOG_SEVERITY.INFO
    end

    local value = tonumber(self._bb:get("config.log_severity", LOG_SEVERITY.INFO))
    if not value then
        return LOG_SEVERITY.INFO
    end

    value = math.floor(value + 0.5)
    if value < LOG_SEVERITY.ERROR then value = LOG_SEVERITY.ERROR end
    if value > LOG_SEVERITY.DEBUG then value = LOG_SEVERITY.DEBUG end
    return value
end

function ConsoleLogger:_should_log(level)
    return self:_get_min_severity() >= level
end

function ConsoleLogger:_emit(level, msg)
    if not self:_should_log(level) then
        return
    end

    if level <= LOG_SEVERITY.ERROR then
        if core and core.log_error then
            core.log_error(PREFIX .. msg)
            return
        end
        if core and core.log_warning then
            core.log_warning(PREFIX .. msg)
            return
        end
        if core and core.log then
            core.log(PREFIX .. msg)
            return
        end
        if print then
            print(PREFIX .. msg)
        end
        return
    end

    if level <= LOG_SEVERITY.WARN then
        if core and core.log_warning then
            core.log_warning(PREFIX .. msg)
            return
        end
        if core and core.log then
            core.log(PREFIX .. msg)
            return
        end
        if print then
            print(PREFIX .. msg)
        end
        return
    end

    if core and core.log then
        core.log(PREFIX .. msg)
    elseif print then
        print(PREFIX .. msg)
    end
end

function ConsoleLogger:_info(msg)
    self:_emit(LOG_SEVERITY.INFO, msg)
end

function ConsoleLogger:_warn(msg)
    self:_emit(LOG_SEVERITY.WARN, msg)
end

function ConsoleLogger:_error(msg)
    self:_emit(LOG_SEVERITY.ERROR, msg)
end

function ConsoleLogger:_debug(msg)
    self:_emit(LOG_SEVERITY.DEBUG, msg)
end

function ConsoleLogger:_subscribe()
    if not self._event_bus or type(self._event_bus.on) ~= "function" then
        return
    end

    local owner = self
    local function on(event, handler)
        self._event_bus:on(event, handler, { owner = owner })
    end

    on(Events.STATE_CHANGED, function(data)
        data = data or {}
        local from_full = format_full_state(data.from, data.substate_from, nil)
        local to_full = format_full_state(data.to, data.substate_to, data.sub_substate)

        if data.from ~= data.to then
            self:_info("State " .. from_full .. " -> " .. to_full)
            return
        end

        if self:_is_verbose() and data.substate_from ~= data.substate_to then
            self:_debug("Substate " .. from_full .. " -> " .. to_full)
        end
    end)

    on(Events.PATH_REQUESTED, function(data)
        if not self:_is_verbose() then return end
        data = data or {}
        self:_debug("Path requested " .. format_pos(data.start) .. " -> " .. format_pos(data.destination))
    end)

    on(Events.PATH_RECEIVED, function(data)
        if not self:_is_verbose() then return end
        data = data or {}
        self:_debug(string.format(
            "Path received: %d waypoints, %.1f yd%s",
            tonumber(data.waypoint_count) or 0,
            tonumber(data.distance) or 0,
            data.partial and " (partial)" or ""
        ))
    end)

    on(Events.PATH_FAILED, function(data)
        data = data or {}
        self:_error("Path request failed: " .. tostring(data.error or "unknown error"))
    end)

    on(Events.WAYPOINT_REACHED, function(data)
        if not self:_is_verbose() then return end
        data = data or {}
        self:_debug(string.format(
            "Waypoint %d/%d",
            tonumber(data.index) or 0,
            tonumber(data.total) or 0
        ))
    end)

    on(Events.STUCK_DETECTED, function(data)
        data = data or {}
        self:_warn(string.format(
            "Stuck detected (%d/%d) near %s",
            tonumber(data.attempt) or 0,
            tonumber(data.max_attempts) or 0,
            format_pos(data.position)
        ))
    end)

    on(Events.STUCK_RECOVERED, function(data)
        if not self:_is_verbose() then return end
        data = data or {}
        self:_debug("Recovered from stuck state at " .. format_pos(data.position))
    end)

    on(Events.DEVIATION_DETECTED, function(data)
        if not self:_is_verbose() then return end
        data = data or {}
        self:_debug(string.format(
            "Deviation detected: drift=%.2f yd at %s",
            tonumber(data.drift) or 0,
            format_pos(data.position)
        ))
    end)

    on(Events.REPATH_STARTED, function(data)
        data = data or {}
        local soft = data.soft == true
        local reason = tostring(data.reason or "unspecified")
        if soft then
            if self:_is_verbose() then
                self:_debug("Soft repath started (" .. reason .. ")")
            end
        else
            self:_warn("Repath started (" .. reason .. ")")
        end
    end)

    on(Events.REPATH_COMPLETED, function(data)
        data = data or {}
        local soft = data.soft == true
        local mode = soft and "Soft repath" or "Repath"

        if data.success then
            if self:_is_verbose() then
                self:_debug(string.format(
                    "%s completed (%d waypoints)",
                    mode,
                    tonumber(data.waypoint_count) or 0
                ))
            end
            return
        end

        self:_error(string.format(
            "%s failed: %s",
            mode,
            tostring(data.error or "unknown error")
        ))
    end)

    on(Events.OBSTACLE_DETECTED, function(data)
        if not self:_is_verbose() then return end
        data = data or {}
        self:_debug(string.format(
            "Obstacle detected at %s (zones=%d)",
            format_pos(data.position),
            tonumber(data.zone_count) or 0
        ))
    end)

    on(Events.SERVER_CONNECTED, function(_)
        self:_info("SentinelNavServer connected")
    end)

    on(Events.SERVER_RETRY, function(data)
        data = data or {}
        self:_warn(string.format(
            "Server request retry %d/%d in %.1fs (HTTP %s)",
            tonumber(data.next_attempt) or 0,
            tonumber(data.max_retries) or 0,
            tonumber(data.delay_secs) or 0,
            tostring(data.code or "?")
        ))
    end)

    on(Events.SERVER_DISCONNECTED, function(data)
        data = data or {}
        self:_warn("SentinelNavServer disconnected: " .. tostring(data.reason or "unknown"))
    end)

    on(Events.SERVER_ERROR, function(data)
        data = data or {}
        if data.domain_error then
            if self:_is_verbose() then
                self:_debug("Server domain error: " .. tostring(data.error or "unknown"))
            end
            return
        end
        self:_error("Server error: " .. tostring(data.error or "unknown"))
    end)

    on(Events.FAILED, function(data)
        data = data or {}
        self:_error("Navigation failed: " .. tostring(data.reason or "unknown"))
    end)
end

function ConsoleLogger:destroy()
    if self._event_bus and type(self._event_bus.off_owner) == "function" then
        self._event_bus:off_owner(self)
    end
end

return ConsoleLogger
