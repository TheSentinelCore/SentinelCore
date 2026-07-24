-- tests/kernel/test_cadence_meter.lua
-- ADR 08 §13 open question 7: "No documented tick rate. on_render is once per frame;
-- on_update is described BOTH as 'reduced speed, relative to On Render' AND 'executed on
-- each frame update' in the same file. The scheduler must measure rather than assume."
--
-- This is the measuring instrument. It is a pure statistics sink so the statistics can be
-- asserted offline; the live number comes from feeding it real deltas in-game.
--
-- The discipline under test is ADR 08 §9.3: an under-sampled meter reports UNKNOWN. It does
-- not report a plausible-looking zero, because a frame budget derived from a fabricated
-- cadence is worse than no frame budget at all.

local CadenceMeter = require("kernel/cadence_meter")
local T = require("tests/test_util")

local M = {}

local function feed(meter, samples)
    for _, s in ipairs(samples) do meter:record(s) end
    return meter
end

--- Below min_samples the meter refuses to answer, and says why.
function M.test_reports_unknown_before_enough_samples()
    local meter = CadenceMeter:new({ min_samples = 5 })
    feed(meter, { 16, 16, 16 })

    local stats, reason = meter:stats()
    T.assert_nil(stats, "an under-sampled meter must not report statistics")
    T.assert_equal(reason, "insufficient_samples", "refusal must carry a named reason")
    T.assert_equal(meter:sample_count(), 3)
end

function M.test_computes_statistics_once_sampled()
    local meter = CadenceMeter:new({ min_samples = 5 })
    feed(meter, { 10, 20, 30, 40, 50 })

    local stats = meter:stats()
    T.assert_not_nil(stats, "five samples with min_samples=5 must produce statistics")
    T.assert_equal(stats.count, 5)
    T.assert_equal(stats.min, 10)
    T.assert_equal(stats.max, 50)
    T.assert_near(stats.mean, 30, 0.001)
    T.assert_equal(stats.median, 30)
end

--- p95 must sit at the slow tail: that is the number a frame budget has to survive,
--- not the mean.
function M.test_p95_tracks_the_slow_tail()
    local meter = CadenceMeter:new({ min_samples = 5 })
    local samples = {}
    for i = 1, 100 do samples[i] = i end
    feed(meter, samples)

    local stats = meter:stats()
    T.assert_equal(stats.p95, 95, "p95 of 1..100 is 95")
    T.assert_equal(stats.max, 100)
end

--- Hz is the number the tick-rate question actually asks for.
function M.test_reports_hz_from_the_median_interval()
    local meter = CadenceMeter:new({ min_samples = 3 })
    feed(meter, { 20, 20, 20, 20 })

    local stats = meter:stats()
    T.assert_near(stats.hz, 50, 0.001, "a 20 ms median interval is 50 Hz")
end

--- The ring buffer must bound memory: this runs 60+ times a second, forever.
function M.test_ring_buffer_keeps_only_the_last_n_samples()
    local meter = CadenceMeter:new({ capacity = 4, min_samples = 1 })
    feed(meter, { 100, 100, 100, 100, 5, 5, 5, 5 })

    local stats = meter:stats()
    T.assert_equal(stats.count, 4, "capacity must bound the retained sample count")
    T.assert_equal(stats.max, 5, "the old 100 ms samples must have been evicted")
    T.assert_equal(meter:total_recorded(), 8, "the lifetime counter still sees every sample")
end

--- A loading screen freezes the tick for seconds. Those frames are real, but folding them
--- into the cadence would make the median meaningless -- they are counted separately.
function M.test_stalls_are_excluded_from_statistics_but_counted()
    local meter = CadenceMeter:new({ min_samples = 3, stall_threshold_ms = 1000 })
    feed(meter, { 16, 16, 8000, 16, 16 })

    local stats = meter:stats()
    T.assert_equal(stats.count, 4, "the 8 s stall must not enter the sample window")
    T.assert_equal(stats.max, 16)
    T.assert_equal(stats.stalls, 1, "but the stall must still be reported")
end

--- Corrupt input is rejected rather than averaged in. A negative interval means the clock
--- went backwards; that is a bug signal, not a data point.
function M.test_rejects_corrupt_samples()
    local meter = CadenceMeter:new({ min_samples = 1 })
    meter:record(-5)
    meter:record(nil)
    meter:record("16")
    meter:record(0 / 0)

    T.assert_equal(meter:sample_count(), 0, "no corrupt sample may be retained")
    local stats, reason = meter:stats()
    T.assert_nil(stats)
    T.assert_equal(reason, "insufficient_samples")
end

--- Zero is legitimate: two ticks can land inside the same millisecond.
function M.test_zero_is_a_valid_sample()
    local meter = CadenceMeter:new({ min_samples = 2 })
    feed(meter, { 0, 0 })
    local stats = meter:stats()
    T.assert_not_nil(stats, "0 ms intervals are real and must be retained")
    T.assert_equal(stats.min, 0)
    T.assert_nil(stats.hz, "a zero median interval has no meaningful Hz -- must be nil, not inf")
end

return M
