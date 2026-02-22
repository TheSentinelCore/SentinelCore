local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")
local Helpers = require("lib/Helpers")

---@private
---@param unit any
---@param method string
---@param ... any
---@return any
local function safe_unit_call(unit, method, ...)
    if not unit then
        return nil
    end
    local fn = unit[method]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, unit, ...)
    if not ok then
        return nil
    end
    return value
end

---@private
---@param value any
---@return number|nil
local function normalize_pct(value)
    local n = tonumber(value)
    if n == nil then
        return nil
    end
    if n > 1.0 then
        n = n / 100.0
    end
    if n < 0 then
        n = 0
    elseif n > 1 then
        n = 1
    end
    return n
end

---@private
---@param unit any
---@return number|nil
local function resolve_unit_mana_pct(unit)
    if not unit then
        return nil
    end

    local current = tonumber(safe_unit_call(unit, "get_power", 0))
    local maximum = tonumber(safe_unit_call(unit, "get_max_power", 0))
    if current ~= nil and maximum ~= nil and maximum > 0 then
        return normalize_pct(current / maximum)
    end

    current = tonumber(safe_unit_call(unit, "get_mana"))
    maximum = tonumber(safe_unit_call(unit, "get_max_mana"))
    if current ~= nil and maximum ~= nil and maximum > 0 then
        return normalize_pct(current / maximum)
    end

    return nil
end

---@class SentinelTelemetry
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _session_id string
---@field private _started_at number
---@field private _last_flush number
---@field private _flush_interval number
---@field private _counters table
---@field private _rates table
---@field private _cast_guard_by_spell table<number, number>
---@field private _last_update_at number
---@field private _last_kill_at number
---@field private _combat_downtime_total number
---@field private _combat_downtime_samples number
---@field private _was_dead boolean
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
    o._last_update_at = o._started_at
    o._last_kill_at = 0
    o._combat_downtime_total = 0
    o._combat_downtime_samples = 0
    o._was_dead = false
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
        cast_guard_blocked = 0,
        chase_updates = 0,
        chase_repaths = 0,
        failed_pulls = 0,
        unreachable_targets = 0,
        idle_full_resource_secs = 0,
    }
    o._cast_guard_by_spell = {}
    o._rates = {
        xp_per_hour = 0,
        gold_per_hour = 0,
        kills_per_hour = 0,
        deaths_per_hour = 0,
        cast_guard_blocked_per_min = 0,
        chase_repaths_per_min = 0,
        chase_updates_per_min = 0,
        failed_pulls_per_hour = 0,
        unreachable_targets_per_hour = 0,
        idle_full_resource_pct = 0,
        combat_downtime_avg_secs = 0,
        cast_guard_blocked_per_min_by_spell = {},
    }

    o:_bind_events()
    return o
end

---@private
---@param data table|nil
---@return number
function Telemetry:_record_blocked_entries(data)
    local blocked = type(data) == "table" and type(data.blocked) == "table" and data.blocked or {}
    local recorded = 0
    for i = 1, #blocked do
        local entry = blocked[i]
        local reason = tostring(entry and entry.reason or data and data.error_code or "")
        if reason == ErrorCodes.CAST_GUARD_BLOCKED then
            self._counters.cast_guard_blocked = self._counters.cast_guard_blocked + 1
            local spell_id = tonumber(entry and entry.spell_id) or 0
            if spell_id > 0 then
                self._cast_guard_by_spell[spell_id] = (tonumber(self._cast_guard_by_spell[spell_id]) or 0) + 1
            end
            recorded = recorded + 1
        end
    end
    return recorded
end

---@private
function Telemetry:_bind_events()
    self._event_bus:on(Events.KILL_CONFIRMED, function(data)
        local now = tonumber(data and data.timestamp) or ((core and core.time and core.time()) or 0)
        if self._last_kill_at > 0 then
            local downtime = now - self._last_kill_at
            if downtime >= 0 then
                self._combat_downtime_total = self._combat_downtime_total + downtime
                self._combat_downtime_samples = self._combat_downtime_samples + 1
            end
        end
        self._last_kill_at = now
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

    self._event_bus:on(Events.ROTATION_BLOCKED, function(data)
        local recorded = self:_record_blocked_entries(data)
        if recorded == 0 and tostring(data and data.error_code or "") == ErrorCodes.CAST_GUARD_BLOCKED then
            self._counters.cast_guard_blocked = self._counters.cast_guard_blocked + 1
        end
    end, { owner = self })

    self._event_bus:on(Events.COMBAT_CHASE_UPDATE, function(data)
        self._counters.chase_updates = self._counters.chase_updates + 1
        if tostring(data and data.reason or "") == "target_shift" then
            self._counters.chase_repaths = self._counters.chase_repaths + 1
        end
    end, { owner = self })

    self._event_bus:on(Events.COMBAT_FAILED, function(data)
        local code = tostring(data and data.error_code or "")
        if code == ErrorCodes.PULL_FAILED then
            self._counters.failed_pulls = self._counters.failed_pulls + 1
        elseif code == ErrorCodes.TARGET_LOST or code == ErrorCodes.NAV_MOVE_FAILED then
            self._counters.unreachable_targets = self._counters.unreachable_targets + 1
        end
    end, { owner = self })
end

---@private
---@return boolean
function Telemetry:_is_idle_full_resources()
    if self._blackboard:get("player.in_combat", false) == true then
        return false
    end

    local target = self._blackboard:get("combat.target")
    if target ~= nil then
        return false
    end

    local player = self._blackboard:get("player.object")
    if not player or safe_unit_call(player, "is_valid") ~= true then
        return false
    end

    local health = tonumber(self._blackboard:get("player.health", 0))
    local max_health = tonumber(self._blackboard:get("player.max_health", 0))
    if max_health <= 0 then
        max_health = tonumber(safe_unit_call(player, "get_max_health")) or 1
    end
    if health <= 0 then
        health = tonumber(safe_unit_call(player, "get_health")) or 0
    end

    local health_pct = normalize_pct(health / math.max(1, max_health)) or 0
    local mana_pct = resolve_unit_mana_pct(player)
    local threshold = tonumber(self._blackboard:get("telemetry.idle_full_resource_threshold", 0.98)) or 0.98

    return health_pct >= threshold and (mana_pct == nil or mana_pct >= threshold)
end

---@private
---@param now number
function Telemetry:_sample_death_state(now)
    local player = self._blackboard:get("player.object")
    if not player or safe_unit_call(player, "is_valid") ~= true then
        self._was_dead = false
        return
    end

    local dead = safe_unit_call(player, "is_dead") == true
    if not dead then
        local health = tonumber(self._blackboard:get("player.health", 0))
        dead = health ~= nil and health <= 0
    end

    if dead and self._was_dead ~= true then
        self._counters.deaths = self._counters.deaths + 1
    end
    self._was_dead = dead == true
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
    self._rates.deaths_per_hour = (self._counters.deaths / elapsed) * 3600.0
    self._rates.xp_per_hour = (xp_gained / elapsed) * 3600.0
    self._rates.cast_guard_blocked_per_min = (self._counters.cast_guard_blocked / elapsed) * 60.0
    self._rates.chase_repaths_per_min = (self._counters.chase_repaths / elapsed) * 60.0
    self._rates.chase_updates_per_min = (self._counters.chase_updates / elapsed) * 60.0
    self._rates.failed_pulls_per_hour = (self._counters.failed_pulls / elapsed) * 3600.0
    self._rates.unreachable_targets_per_hour = (self._counters.unreachable_targets / elapsed) * 3600.0
    self._rates.idle_full_resource_pct = self._counters.idle_full_resource_secs / elapsed
    if self._combat_downtime_samples > 0 then
        self._rates.combat_downtime_avg_secs = self._combat_downtime_total / self._combat_downtime_samples
    else
        self._rates.combat_downtime_avg_secs = 0
    end

    local by_spell = {}
    for spell_id, count in pairs(self._cast_guard_by_spell) do
        local sid = tonumber(spell_id)
        if sid and sid > 0 then
            by_spell[sid] = (tonumber(count) or 0) * 60.0 / elapsed
        end
    end
    self._rates.cast_guard_blocked_per_min_by_spell = by_spell

    -- Gold metrics are placeholder until detailed bag value APIs are integrated.
    local gold_gained = self._blackboard:get("telemetry.gold_gained", 0)
    self._rates.gold_per_hour = (gold_gained / elapsed) * 3600.0
end

---@param now number
function Telemetry:update(now)
    now = now or ((core and core.time and core.time()) or 0)

    local dt = now - (tonumber(self._last_update_at) or now)
    if dt < 0 then
        dt = 0
    end
    self._last_update_at = now

    if self:_is_idle_full_resources() then
        self._counters.idle_full_resource_secs = self._counters.idle_full_resource_secs + dt
    end
    self:_sample_death_state(now)

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
