local Catalog = require("modules/battleground/data/bg_catalog")
local Events = require("modules/battleground/events")

local LeaveManager = {}
LeaveManager.__index = LeaveManager

local function num(value)
    return tonumber(value) or 0
end

local function is_trueish(value)
    if value == true or value == 1 then
        return true
    end
    local lowered = tostring(value or ""):lower()
    return lowered == "true" or lowered == "1"
end

local function safe_set(blackboard, key, value)
    blackboard:set(key, value)
end

local function is_supported_map(map_id)
    local id = tonumber(map_id)
    if not id then
        return false
    end
    for _, entry in pairs(Catalog) do
        if tonumber(entry.map_id) == id then
            return true
        end
    end
    return false
end

function LeaveManager:new(event_bus, blackboard)
    local o = setmetatable({}, LeaveManager)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o:_reset_internal()
    o:_publish_snapshot()
    return o
end

function LeaveManager:_reset_internal()
    self._gate_open = false
    self._gate_reason = ""
    self._gate_open_at_ms = 0
    self._initial_delay_until_ms = 0
    self._attempts = 0
    self._last_attempt_at_ms = 0
    self._last_attempt_ok = nil
    self._last_strategy = ""
    self._confirmed = false
    self._confirm_reason = ""
    self._wait_reason = "idle"
    self._api_present = false
    self._exhausted = false
    self._manual_request_reason = nil
end

function LeaveManager:initialize()
    self:reset("initialize")
end

function LeaveManager:reset(_reason)
    self:_reset_internal()
    self:_publish_snapshot()
end

function LeaveManager:request_now(reason)
    self._manual_request_reason = tostring(reason or "manual_request")
end

function LeaveManager:_emit(event_name, payload)
    if self._event_bus then
        self._event_bus:publish(event_name, payload)
    end
end

function LeaveManager:_now_ms()
    return num(self._blackboard:get("system.now_ms", 0))
end

function LeaveManager:_read_settings()
    return {
        enabled = self._blackboard:get("module.bg.enabled", true) == true,
        auto_leave = self._blackboard:get("module.bg.post_game_auto_leave", true) == true,
        streak_required = math.max(1, math.floor(tonumber(self._blackboard:get("module.bg.post_game_state5_streak_required", 1)) or 1)),
        initial_delay_ms = math.floor((tonumber(self._blackboard:get("module.bg.post_game_leave_initial_delay_s", 2.0)) or 2.0) * 1000),
        retry_interval_ms = math.floor((tonumber(self._blackboard:get("module.bg.post_game_leave_retry_interval_s", 1.0)) or 1.0) * 1000),
        max_attempts = math.max(1, math.floor(tonumber(self._blackboard:get("module.bg.post_game_leave_max_attempts", 25)) or 25)),
    }
end

function LeaveManager:_read_sensor()
    return {
        in_bg = self._blackboard:get("bg.sensor.in_bg", false) == true,
        battlefield_state = self._blackboard:get("bg.sensor.battlefield_state"),
        streak_5 = num(self._blackboard:get("bg.sensor.battlefield_state_streak_5", 0)),
        status_summary = tostring(self._blackboard:get("bg.sensor.queue_status_summary", "unknown|unknown|unknown") or "unknown|unknown|unknown"),
        map_id = num(self._blackboard:get("system.map_id", 0)),
    }
end

function LeaveManager:_publish_snapshot()
    local settings = self:_read_settings()
    safe_set(self._blackboard, "bg.leave.enabled", settings.auto_leave)
    safe_set(self._blackboard, "bg.leave.gate_open", self._gate_open)
    safe_set(self._blackboard, "bg.leave.gate_reason", self._gate_reason)
    safe_set(self._blackboard, "bg.leave.gate_open_at_ms", self._gate_open_at_ms)
    safe_set(self._blackboard, "bg.leave.initial_delay_until_ms", self._initial_delay_until_ms)
    safe_set(self._blackboard, "bg.leave.attempts", self._attempts)
    safe_set(self._blackboard, "bg.leave.last_attempt_at_ms", self._last_attempt_at_ms)
    safe_set(self._blackboard, "bg.leave.last_attempt_ok", self._last_attempt_ok)
    safe_set(self._blackboard, "bg.leave.last_strategy", self._last_strategy)
    safe_set(self._blackboard, "bg.leave.confirmed", self._confirmed)
    safe_set(self._blackboard, "bg.leave.confirm_reason", self._confirm_reason)
    safe_set(self._blackboard, "bg.leave.wait_reason", self._wait_reason)
    safe_set(self._blackboard, "bg.leave.api_present", self._api_present)
    safe_set(self._blackboard, "bg.leave.exhausted", self._exhausted)
end

function LeaveManager:_open_gate(reason, now_ms, settings)
    if self._gate_open then
        return
    end
    self._gate_open = true
    self._gate_reason = tostring(reason or "unknown")
    self._gate_open_at_ms = now_ms
    self._initial_delay_until_ms = now_ms + math.max(0, settings.initial_delay_ms)
    self._confirmed = false
    self._confirm_reason = ""
    self._exhausted = false
    self._wait_reason = "waiting_initial_delay"
    self:_emit(Events.LEAVE_GATE_OPENED, {
        reason = self._gate_reason,
        gate_open_at_ms = self._gate_open_at_ms,
        initial_delay_until_ms = self._initial_delay_until_ms,
    })
end

function LeaveManager:_confirm(reason)
    self._confirmed = true
    self._confirm_reason = tostring(reason or "confirmed")
    self._gate_open = false
    self._gate_reason = ""
    self._gate_open_at_ms = 0
    self._initial_delay_until_ms = 0
    self._manual_request_reason = nil
    self._wait_reason = "confirmed"
    self:_emit(Events.LEAVE_CONFIRMED, {
        reason = self._confirm_reason,
        attempts = self._attempts,
        strategy = self._last_strategy,
    })
end

function LeaveManager:_attempt_leave()
    local input = core and core.input or nil
    local leave_fn = input and input.leave_battlefield or nil
    self._api_present = type(leave_fn) == "function"
    if not self._api_present then
        self._wait_reason = "api_missing"
        self:_emit(Events.LEAVE_API_MISSING, {})
        return false, nil
    end

    local attempts = {
        { name = "core.input.leave_battlefield()", run = function() return pcall(leave_fn) end },
        { name = "core.input.leave_battlefield(core.input)", run = function() return pcall(leave_fn, input) end },
    }

    for _, candidate in ipairs(attempts) do
        local ok, value = candidate.run()
        self._last_strategy = candidate.name
        self._last_attempt_ok = ok == true and (value == nil or is_trueish(value))
        if self._last_attempt_ok then
            return true, candidate.name
        end
    end
    return false, self._last_strategy
end

function LeaveManager:update()
    local settings = self:_read_settings()
    local sensor = self:_read_sensor()
    local now_ms = self:_now_ms()

    self._api_present = core and core.input and type(core.input.leave_battlefield) == "function" or false

    if settings.enabled ~= true then
        self:reset("bg_disabled")
        return self:get_snapshot()
    end

    if (self._gate_open or self._attempts > 0) and (not sensor.in_bg) then
        self:_confirm("sensor_in_bg_false")
        self:_publish_snapshot()
        return self:get_snapshot()
    end

    if (self._gate_open or self._attempts > 0)
        and (not is_supported_map(sensor.map_id)) then
        self:_confirm("supported_bg_map_cleared")
        self:_publish_snapshot()
        return self:get_snapshot()
    end

    local finished_signal = tonumber(sensor.battlefield_state) == 5 and sensor.streak_5 >= settings.streak_required
    if sensor.in_bg and (finished_signal or self._manual_request_reason ~= nil) then
        self:_open_gate(self._manual_request_reason or "battlefield_state_5", now_ms, settings)
    end

    if not sensor.in_bg then
        self._wait_reason = "not_in_bg"
        self:_publish_snapshot()
        return self:get_snapshot()
    end

    if not self._gate_open then
        if settings.auto_leave ~= true then
            self._wait_reason = "auto_leave_off"
        else
            self._wait_reason = "waiting_for_gate"
        end
        self:_publish_snapshot()
        return self:get_snapshot()
    end

    if settings.auto_leave ~= true and self._manual_request_reason == nil then
        self._wait_reason = "auto_leave_off"
        self:_publish_snapshot()
        return self:get_snapshot()
    end

    if now_ms < self._initial_delay_until_ms then
        self._wait_reason = "waiting_initial_delay"
        self:_publish_snapshot()
        return self:get_snapshot()
    end

    if self._attempts >= settings.max_attempts then
        self._exhausted = true
        self._wait_reason = "max_attempts"
        self:_emit(Events.LEAVE_MAX_ATTEMPTS_REACHED, {
            attempts = self._attempts,
            battlefield_state = sensor.battlefield_state,
        })
        self:_publish_snapshot()
        return self:get_snapshot()
    end

    if self._last_attempt_at_ms > 0 and (now_ms - self._last_attempt_at_ms) < math.max(200, settings.retry_interval_ms) then
        self._wait_reason = "waiting_retry_interval"
        self:_publish_snapshot()
        return self:get_snapshot()
    end

    self._attempts = self._attempts + 1
    self._last_attempt_at_ms = now_ms
    local ok, strategy = self:_attempt_leave()
    if self._wait_reason ~= "api_missing" then
        self._wait_reason = ok and "awaiting_confirmation" or "leave_dispatch_failed"
    end
    self:_emit(Events.LEAVE_ATTEMPT, {
        attempt = self._attempts,
        ok = ok == true,
        strategy = strategy,
        battlefield_state = sensor.battlefield_state,
    })

    if self._attempts > 0 then
        local state_cleared = sensor.battlefield_state ~= 2 and sensor.battlefield_state ~= 3 and sensor.battlefield_state ~= 5
        local summary = sensor.status_summary
        local statuses_cleared = summary == "none|none|none" or summary == "unknown|unknown|unknown"
        if state_cleared and statuses_cleared then
            self:_confirm("battlefield_state_cleared")
        end
    end

    self:_publish_snapshot()
    return self:get_snapshot()
end

function LeaveManager:get_snapshot()
    return {
        enabled = self._blackboard:get("bg.leave.enabled", false),
        gate_open = self._gate_open,
        gate_reason = self._gate_reason,
        gate_open_at_ms = self._gate_open_at_ms,
        initial_delay_until_ms = self._initial_delay_until_ms,
        attempts = self._attempts,
        last_attempt_at_ms = self._last_attempt_at_ms,
        last_attempt_ok = self._last_attempt_ok,
        last_strategy = self._last_strategy,
        confirmed = self._confirmed,
        confirm_reason = self._confirm_reason,
        wait_reason = self._wait_reason,
        api_present = self._api_present,
        exhausted = self._exhausted,
    }
end

return LeaveManager
