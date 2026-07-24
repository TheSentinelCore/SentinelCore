-- kernel/cadence_meter.lua
-- Bounded statistics over tick intervals.
--
-- ADR 08 §13 open question 7: there is NO documented tick rate. `on_render` is once per
-- frame; `on_update` is documented both as "reduced speed, relative to On Render" and as
-- "executed on each frame update" -- in the same file. The frame-budget design depends on
-- the real cadence, so the scheduler measures it instead of assuming it.
--
-- Two rules this file exists to enforce:
--
--   1. UNDER-SAMPLED MEANS UNKNOWN (ADR 08 §9.3). `stats()` returns nil plus a named reason
--      until it has enough data. A fabricated cadence would silently produce a fabricated
--      frame budget, which is strictly worse than admitting we do not know yet.
--   2. BOUNDED MEMORY. This records at tick rate, forever. A ring buffer keeps the last N
--      samples; the lifetime counters are plain integers.

local CadenceMeter = {}
CadenceMeter.__index = CadenceMeter

local DEFAULT_CAPACITY = 600           -- ~10 s of history at 60 Hz
local DEFAULT_MIN_SAMPLES = 30
local DEFAULT_STALL_THRESHOLD_MS = 1000 -- a loading screen, not a frame

---@param opts table|nil { capacity, min_samples, stall_threshold_ms }
function CadenceMeter:new(opts)
    opts = opts or {}
    local o = setmetatable({}, CadenceMeter)
    o._capacity = opts.capacity or DEFAULT_CAPACITY
    o._min_samples = opts.min_samples or DEFAULT_MIN_SAMPLES
    o._stall_threshold_ms = opts.stall_threshold_ms or DEFAULT_STALL_THRESHOLD_MS
    o._samples = {}
    o._next = 1        -- ring write cursor
    o._filled = 0      -- retained sample count, <= capacity
    o._total = 0       -- lifetime accepted samples
    o._stalls = 0      -- lifetime samples above the stall threshold
    o._rejected = 0    -- lifetime corrupt samples
    return o
end

--- A sample is usable only if it is a real, finite, non-negative number. A negative
--- interval means the clock went backwards -- that is a bug signal, not a data point.
local function is_usable(sample)
    if type(sample) ~= "number" then return false end
    if sample ~= sample then return false end          -- NaN
    if sample == math.huge or sample == -math.huge then return false end
    return sample >= 0
end

---Record one tick interval in milliseconds.
---@param delta_ms number
function CadenceMeter:record(delta_ms)
    if not is_usable(delta_ms) then
        self._rejected = self._rejected + 1
        return false
    end

    self._total = self._total + 1

    -- Stalls are real frames but they are not cadence. Folding an 8 s loading screen into
    -- the window would poison every statistic derived from it.
    if delta_ms >= self._stall_threshold_ms then
        self._stalls = self._stalls + 1
        return false
    end

    self._samples[self._next] = delta_ms
    self._next = (self._next % self._capacity) + 1
    if self._filled < self._capacity then
        self._filled = self._filled + 1
    end
    return true
end

---@return number retained samples currently in the window
function CadenceMeter:sample_count()
    return self._filled
end

---@return number lifetime samples accepted (including stalls)
function CadenceMeter:total_recorded()
    return self._total
end

---Statistics over the retained window.
---@return table|nil stats, string|nil reason
function CadenceMeter:stats()
    if self._filled < self._min_samples then
        return nil, "insufficient_samples"
    end

    local sorted = {}
    local sum = 0
    for i = 1, self._filled do
        local v = self._samples[i]
        sorted[i] = v
        sum = sum + v
    end
    table.sort(sorted)

    local n = self._filled
    local median = sorted[math.ceil(n / 2)]
    -- Nearest-rank p95: the smallest sample at or above the 95th percentile position.
    local p95 = sorted[math.min(n, math.ceil(n * 0.95))]

    -- A zero median interval has no meaningful frequency. Report nil rather than inf --
    -- inf propagates into every downstream budget calculation as a plausible number.
    local hz = nil
    if median > 0 then
        hz = 1000 / median
    end

    return {
        count = n,
        min = sorted[1],
        max = sorted[n],
        mean = sum / n,
        median = median,
        p95 = p95,
        hz = hz,
        stalls = self._stalls,
        rejected = self._rejected,
        total = self._total,
    }
end

function CadenceMeter:reset()
    self._samples = {}
    self._next = 1
    self._filled = 0
end

return CadenceMeter
