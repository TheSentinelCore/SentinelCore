-- kernel/tick_clock.lua
-- The kernel's single tick-time authority (ADR 08 §5.1: "One thing drives the tick").
--
-- ================================================================================
-- THE TWO-CLOCK PROBLEM (ADR 08 §2.5)
-- ================================================================================
-- `core.time()`      -> seconds since PS injection
-- `core.game_time()` -> milliseconds since the game started
-- Every server-derived timestamp -- buff expire_time, cast end, cooldown start_time --
-- lives on the game_time millisecond axis ONLY, and the SDK docs warn explicitly against
-- mixing the two.
--
-- This clock therefore derives its authoritative per-tick delta from `core.game_time()`,
-- which is unambiguous. It publishes INTERVALS only; it never hands out an absolute
-- timestamp that a caller could accidentally compare against a server one.
--
-- ================================================================================
-- WHY `core.delta_time()` IS MEASURED, NOT TRUSTED
-- ================================================================================
-- Three sites in this repo multiply `core.delta_time()` by 1000, i.e. they assume it
-- returns SECONDS:
--
--   runtime/app.lua:84 · runtime/callback_bridge.lua:68 · runtime/sensors/system_sensor.lua:14
--
-- The SDK documents it as MILLISECONDS (docs/SylvannasAPI/dev/api/core.md:474). Exactly one
-- of those is right, and the doc cannot arbitrate because the same page contradicts itself
-- about the update callback's cadence (ADR 08 §13 q7).
--
-- ADR 08 §13 q7: "The scheduler must MEASURE rather than assume."
--
-- So the clock accumulates raw `delta_time()` output over the first N ticks and compares
-- the sum against the elapsed `game_time()` over the same span. The ratio is the scale
-- factor, and it is REPORTED, not applied blind:
--
--   ratio ~ 1     -> delta_time is already milliseconds  (scale 1)
--   ratio ~ 1000  -> delta_time is seconds               (scale 1000)
--   anything else -> "ambiguous"; no scale factor is offered
--
-- Until it has measured, the unit is "unknown" and the scale is nil -- never a guessed
-- constant (ADR 08 §9.3: an unreadable field must not become a plausible-looking zero).

local CadenceMeter = require("kernel/cadence_meter")

local TickClock = {}
TickClock.__index = TickClock

local DEFAULT_CALIBRATION_SAMPLES = 60
-- Tolerance bands around the two hypotheses. Deliberately wide, because `delta_time` and
-- `game_time` are sampled at slightly different points in the frame, and deliberately
-- non-overlapping, so a measurement that fits neither is reported rather than rounded.
local MS_RATIO_MAX = 5      -- ratio at or below this reads as "already milliseconds"
local SECONDS_RATIO_MIN = 200 -- ratio at or above this reads as "seconds"

---@param opts table|nil { calibration_samples, cadence = {…CadenceMeter opts} }
function TickClock:new(opts)
    opts = opts or {}
    local o = setmetatable({}, TickClock)
    o._cadence = CadenceMeter:new(opts.cadence)
    o._calibration_samples = opts.calibration_samples or DEFAULT_CALIBRATION_SAMPLES

    o._last_game_time_ms = nil
    o._tick_index = 0

    -- Calibration accumulators.
    o._calibration_ticks = 0
    o._calibration_raw_sum = 0      -- Σ core.delta_time()
    o._calibration_elapsed_ms = 0   -- Σ game_time deltas over the same ticks
    o._delta_time_unit = "unknown"
    o._delta_time_scale = nil
    return o
end

--- Read a numeric SDK function without letting it escape. Anything unreadable is nil --
--- never a substituted zero that the caller cannot distinguish from a real reading.
local function safe_read(fn)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn)
    if ok and type(value) == "number" and value == value then
        return value
    end
    return nil
end

---Advance one tick.
---@param game_time_ms number|nil Injected for tests; read from core.game_time() otherwise.
---@param raw_delta_time number|nil Injected for tests; read from core.delta_time() otherwise.
---@return number delta_ms Milliseconds since the previous tick (0 on the first tick).
function TickClock:tick(game_time_ms, raw_delta_time)
    if game_time_ms == nil then
        game_time_ms = safe_read(core and core.game_time)
    end
    if raw_delta_time == nil then
        raw_delta_time = safe_read(core and core.delta_time)
    end

    self._tick_index = self._tick_index + 1

    -- An unreadable clock cannot produce a delta. Report 0 and keep the previous anchor:
    -- inventing a delta here would feed a fabricated number to every module.
    if type(game_time_ms) ~= "number" then
        return 0
    end

    local previous = self._last_game_time_ms
    self._last_game_time_ms = game_time_ms
    if previous == nil then
        return 0
    end

    local delta_ms = game_time_ms - previous
    if delta_ms < 0 then
        -- The clock went backwards. That is corrupt, not a negative frame.
        delta_ms = 0
    end

    self._cadence:record(delta_ms)
    self:_accumulate_calibration(delta_ms, raw_delta_time)

    return delta_ms
end

---Compare Σ delta_time against the elapsed game_time over the same span.
function TickClock:_accumulate_calibration(delta_ms, raw_delta_time)
    if self._delta_time_scale ~= nil or self._delta_time_unit == "ambiguous" then
        return -- already settled
    end
    if type(raw_delta_time) ~= "number" or raw_delta_time <= 0 then
        return -- carries no information
    end

    self._calibration_ticks = self._calibration_ticks + 1
    self._calibration_raw_sum = self._calibration_raw_sum + raw_delta_time
    self._calibration_elapsed_ms = self._calibration_elapsed_ms + delta_ms

    if self._calibration_ticks < self._calibration_samples then
        return
    end
    if self._calibration_raw_sum <= 0 or self._calibration_elapsed_ms <= 0 then
        return
    end

    local ratio = self._calibration_elapsed_ms / self._calibration_raw_sum
    if ratio <= MS_RATIO_MAX then
        self._delta_time_unit = "milliseconds"
        self._delta_time_scale = 1
    elseif ratio >= SECONDS_RATIO_MIN then
        self._delta_time_unit = "seconds"
        self._delta_time_scale = 1000
    else
        -- Fits neither hypothesis. Say so; do not round to the nearer one.
        self._delta_time_unit = "ambiguous"
        self._delta_time_scale = nil
    end
    self._measured_ratio = ratio
end

---@return string "unknown" | "milliseconds" | "seconds" | "ambiguous"
function TickClock:delta_time_unit()
    return self._delta_time_unit
end

---@return number|nil 1, 1000, or nil when unmeasured/ambiguous
function TickClock:delta_time_scale()
    return self._delta_time_scale
end

---@return number|nil the raw measured ratio, for diagnostics
function TickClock:measured_ratio()
    return self._measured_ratio
end

---@return table|nil stats, string|nil reason -- see CadenceMeter:stats()
function TickClock:cadence()
    return self._cadence:stats()
end

---@return number ticks driven since construction
function TickClock:tick_index()
    return self._tick_index
end

return TickClock
