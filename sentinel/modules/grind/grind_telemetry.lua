local GrindTelemetry = {}
GrindTelemetry.__index = GrindTelemetry

---Wrap telemetry initialization, throttled publishing, and death loop detection.
---Extracted from SentinelGrind to encapsulate the _last_refresh_ms access pattern.
local PUBLISH_INTERVAL_MS = 2000

function GrindTelemetry:new(event_bus)
    return setmetatable({
        _event_bus = event_bus,
        _telemetry = nil,
        _initialized = false,
        _last_refresh_ms = 0,
    }, self)
end

---Set the underlying telemetry instance.
---Called during grind module initialization before tick().
---@param telemetry table Telemetry module instance
function GrindTelemetry:set_telemetry(telemetry)
    self._telemetry = telemetry
end

---Tick: initialize if needed and publish throttled telemetry data.
---@param bb table Blackboard
---@param now_ms number Current time in milliseconds
function GrindTelemetry:tick(bb, now_ms)
    if not self._telemetry then return end

    -- Initialize on first enabled tick
    if not self._initialized then
        self._telemetry:initialize(now_ms)
        self._initialized = true
    end

    -- Publish to blackboard, throttled to PUBLISH_INTERVAL_MS
    if now_ms - self._last_refresh_ms >= PUBLISH_INTERVAL_MS then
        self._telemetry:publish_to_blackboard(bb, now_ms)
        self._last_refresh_ms = now_ms
    end
end

---Check if the player is in a death loop.
---@param now_ms number Current time in milliseconds
---@return boolean
function GrindTelemetry:is_death_loop(now_ms)
    if not self._telemetry then return false end
    return self._telemetry:is_death_loop(now_ms)
end

---Shut down the underlying telemetry.
function GrindTelemetry:shutdown()
    if self._telemetry then
        self._telemetry:shutdown()
    end
end

return GrindTelemetry
