local Events = require("events/Events")
local Helpers = require("lib/Helpers")

---@class SentinelTelemetry
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _session_id string
---@field private _started_at number
---@field private _last_flush number
---@field private _flush_interval number
---@field private _counters table
---@field private _rates table
local Telemetry = {}
Telemetry.__index = Telemetry

---@param event_bus EventBus
---@param blackboard Blackboard
---@param flush_interval number
---@return SentinelTelemetry
function Telemetry:new(event_bus, blackboard, flush_interval)
    local o = setmetatable({}, Telemetry)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._session_id = Helpers.generate_id()
    o._started_at = (core and core.time and core.time()) or 0
    o._last_flush = o._started_at
    o._flush_interval = flush_interval or 1.0
    o._counters = {
        kills = 0,
        deaths = 0,
        loot_events = 0,
        vendor_trips = 0,
        vendor_failures = 0,
        stuck_recoveries = 0,
        restarts = 0,
        failures = 0,
        pauses = 0,
        resumes = 0,
        objectives_completed = 0,
        objective_failures = 0,
    }
    o._rates = {
        xp_per_hour = 0,
        gold_per_hour = 0,
        kills_per_hour = 0,
    }

    o:_bind_events()
    return o
end

---@private
function Telemetry:_bind_events()
    self._event_bus:on(Events.KILL_CONFIRMED, function()
        self._counters.kills = self._counters.kills + 1
    end, { owner = self })

    self._event_bus:on(Events.LOOT_COMPLETED, function()
        self._counters.loot_events = self._counters.loot_events + 1
    end, { owner = self })

    self._event_bus:on(Events.VENDOR_COMPLETED, function()
        self._counters.vendor_trips = self._counters.vendor_trips + 1
    end, { owner = self })

    self._event_bus:on(Events.VENDOR_FAILED, function()
        self._counters.vendor_failures = self._counters.vendor_failures + 1
    end, { owner = self })

    self._event_bus:on(Events.RECOVERY_COMPLETED, function()
        self._counters.stuck_recoveries = self._counters.stuck_recoveries + 1
    end, { owner = self })

    self._event_bus:on(Events.RECOVERY_ESCALATED, function(data)
        if data and data.stage == "restart" then
            self._counters.restarts = self._counters.restarts + 1
        end
    end, { owner = self })

    self._event_bus:on(Events.FAILED, function()
        self._counters.failures = self._counters.failures + 1
    end, { owner = self })

    self._event_bus:on(Events.PAUSED, function()
        self._counters.pauses = self._counters.pauses + 1
    end, { owner = self })

    self._event_bus:on(Events.RESUMED, function()
        self._counters.resumes = self._counters.resumes + 1
    end, { owner = self })

    self._event_bus:on(Events.OBJECTIVE_COMPLETED, function()
        self._counters.objectives_completed = self._counters.objectives_completed + 1
    end, { owner = self })

    self._event_bus:on(Events.OBJECTIVE_FAILED, function()
        self._counters.objective_failures = self._counters.objective_failures + 1
    end, { owner = self })
end

---@private
---@param now number
function Telemetry:_update_rates(now)
    local elapsed = math.max(1, now - self._started_at)
    local player_xp = self._blackboard:get("player.xp", 0)
    local baseline = self._blackboard:get("telemetry.xp_baseline", player_xp)
    if not self._blackboard:has("telemetry.xp_baseline") then
        self._blackboard:set("telemetry.xp_baseline", player_xp)
        baseline = player_xp
    end

    local xp_gained = math.max(0, player_xp - baseline)

    self._rates.kills_per_hour = (self._counters.kills / elapsed) * 3600.0
    self._rates.xp_per_hour = (xp_gained / elapsed) * 3600.0

    -- Gold metrics are placeholder until detailed bag value APIs are integrated.
    local gold_gained = self._blackboard:get("telemetry.gold_gained", 0)
    self._rates.gold_per_hour = (gold_gained / elapsed) * 3600.0
end

---@param now number
function Telemetry:update(now)
    now = now or ((core and core.time and core.time()) or 0)
    self:_update_rates(now)

    if now - self._last_flush < self._flush_interval then
        return
    end

    self._last_flush = now
    self._event_bus:emit(Events.TELEMETRY_FLUSHED, {
        timestamp = now,
        session_id = self._session_id,
        counters = Helpers.deep_copy(self._counters),
        rates = Helpers.deep_copy(self._rates),
    })
end

---@return table
function Telemetry:get_snapshot()
    local context = self._blackboard:get("context.canonical", {})
    local now = (core and core.time and core.time()) or self._started_at
    local uptime = math.max(0, now - self._started_at)
    return {
        session_id = self._session_id,
        started_at = self._started_at,
        uptime_secs = uptime,
        last_flush_at = self._last_flush,
        counters = Helpers.deep_copy(self._counters),
        rates = Helpers.deep_copy(self._rates),
        map_id = context.map_id,
        zone_id = context.zone_id,
        area_id = context.area_id,
    }
end

---@return string
function Telemetry:get_session_id()
    return self._session_id
end

---@param count number
function Telemetry:increment_deaths(count)
    self._counters.deaths = self._counters.deaths + (count or 1)
end

function Telemetry:destroy()
    self._event_bus:off_owner(self)
end

return Telemetry
