local TelemetryService = {}
TelemetryService.__index = TelemetryService

local function now_secs()
    if core and core.time then
        local ok, value = pcall(core.time)
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    return os.time()
end

local function safe_method(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(obj[method], obj, ...)
    if ok then
        return value
    end
    return nil
end

---@class TelemetryService
function TelemetryService:new(bb, cfg, logger)
    local o = setmetatable({}, TelemetryService)
    o._bb = bb
    o._cfg = cfg or {}
    o._log = logger
    o._started_at = now_secs()
    o._last_snapshot = 0
    o._last_report = 0
    o._money_baseline = nil
    o._money_gained = 0
    o._kills = 0
    o._last_dead_guid = ""
    return o
end

function TelemetryService:_track_money()
    local money = tonumber(self._bb:get("player.money_copper"))
    if money == nil then
        return
    end

    if self._money_baseline == nil then
        self._money_baseline = money
        return
    end

    local delta = money - self._money_baseline
    if delta > 0 then
        self._money_gained = self._money_gained + delta
    end
    self._money_baseline = money
end

function TelemetryService:_track_kills()
    local target = self._bb:get("combat.target")
    if not target then
        return
    end

    if safe_method(target, "is_dead") == true then
        local guid = tostring(safe_method(target, "get_guid") or "")
        if guid ~= "" and guid ~= self._last_dead_guid then
            self._last_dead_guid = guid
            self._kills = self._kills + 1
        end
    end
end

---@param now number
function TelemetryService:update(now)
    self:_track_money()
    self:_track_kills()

    local snapshot_interval = tonumber(self._cfg.telemetry and self._cfg.telemetry.snapshot_interval) or 1.0
    if (now - self._last_snapshot) < snapshot_interval then
        return
    end
    self._last_snapshot = now

    local elapsed = math.max(1, now - self._started_at)
    local gph = (self._money_gained / elapsed) * 3600.0

    local snapshot = {
        session_started_at = self._started_at,
        uptime_secs = elapsed,
        kills = self._kills,
        gold_gained_copper = self._money_gained,
        gold_per_hour_copper = gph,
        deaths = self._bb:get("telemetry.deaths", 0),
        vendor_needs_trip = self._bb:get("vendor.needs_trip", false),
        role = self._bb:get("duo.role", "leader"),
    }

    self._bb:set("telemetry.snapshot", snapshot)
    self._bb:set("telemetry.gold_per_hour_copper", gph)

    local report_interval = tonumber(self._cfg.telemetry and self._cfg.telemetry.report_interval) or 10.0
    if (now - self._last_report) >= report_interval then
        self._last_report = now
        if self._log then
            self._log:info("telemetry: kills=%d gph=%.0f copper/h uptime=%.0fs", self._kills, gph, elapsed)
        end
    end
end

return TelemetryService
