-- tests/kernel/test_tick_clock.lua
-- The kernel's single tick-time authority.
--
-- WHY THIS EXISTS AS ITS OWN UNIT. Three files in this repo independently computed a tick
-- delta and all three did the SAME thing:
--
--   runtime/app.lua:84                   math.floor(tonumber(delta) * 1000)
--   runtime/callback_bridge.lua:68        math.floor((core.delta_time() or 0) * 1000)
--   runtime/sensors/system_sensor.lua:14  math.floor(num((core.delta_time() or 0) * 1000))
--
-- ...i.e. all three assume `core.delta_time()` returns SECONDS. But the SDK documents it as
-- MILLISECONDS (docs/SylvannasAPI/dev/api/core.md:474). One of those is wrong and the repo
-- cannot tell which by reading, because the same doc page contradicts itself about the tick
-- callback (ADR 08 §13 q7).
--
-- ADR 08 §13 q7 settles the method: "The scheduler must MEASURE rather than assume."
--
-- So: the authoritative delta comes from `core.game_time()`, which is unambiguously
-- milliseconds (ADR 08 §2.5), and `core.delta_time()` is CALIBRATED against it at runtime.
-- The clock reports the unit it measured. Nothing here assumes an answer, and nothing
-- silently "corrects" a value it has not proven.
--
-- ADR 08 §2.5 also forbids mixing the clocks: core.time() is seconds-since-injection,
-- core.game_time() is milliseconds-since-game-start, and every server timestamp lives on
-- the game_time axis only. This clock derives INTERVALS and never hands out an absolute
-- timestamp that could be compared against a server one.

local TickClock = require("kernel/tick_clock")
local T = require("tests/test_util")

local M = {}

--- Drives a clock over a scripted sequence of (game_time_ms, raw_delta_time) pairs.
local function drive(clock, frames)
    local out = {}
    for _, f in ipairs(frames) do
        out[#out + 1] = clock:tick(f[1], f[2])
    end
    return out
end

--- The delta modules receive is derived from game_time, not from delta_time.
function M.test_delta_is_derived_from_game_time()
    local clock = TickClock:new()
    local deltas = drive(clock, {
        { 1000, 0 },
        { 1016, 0 },
        { 1033, 0 },
    })
    T.assert_equal(deltas[1], 0, "the first tick has no predecessor, so its delta is 0")
    T.assert_equal(deltas[2], 16)
    T.assert_equal(deltas[3], 17)
end

--- Until calibration completes, the unit is UNKNOWN. Not "assumed seconds", not
--- "assumed milliseconds" (ADR 08 §9.3).
function M.test_delta_time_unit_starts_unknown()
    local clock = TickClock:new({ calibration_samples = 10 })
    T.assert_equal(clock:delta_time_unit(), "unknown")
    T.assert_nil(clock:delta_time_scale(), "an uncalibrated scale must be nil, never a guessed 1 or 1000")
end

--- If delta_time really returns milliseconds (what the SDK doc says), the measurement
--- must say so -- scale 1.
function M.test_calibrates_delta_time_as_milliseconds()
    local clock = TickClock:new({ calibration_samples = 5 })
    local frames = {}
    for i = 0, 9 do
        frames[#frames + 1] = { 1000 + i * 16, 16 } -- raw delta already in ms
    end
    drive(clock, frames)

    T.assert_equal(clock:delta_time_unit(), "milliseconds")
    T.assert_equal(clock:delta_time_scale(), 1)
end

--- If it really returns seconds (what this repo's three call sites assume), the
--- measurement must say THAT -- scale 1000.
function M.test_calibrates_delta_time_as_seconds()
    local clock = TickClock:new({ calibration_samples = 5 })
    local frames = {}
    for i = 0, 9 do
        frames[#frames + 1] = { 1000 + i * 16, 0.016 } -- raw delta in seconds
    end
    drive(clock, frames)

    T.assert_equal(clock:delta_time_unit(), "seconds")
    T.assert_equal(clock:delta_time_scale(), 1000)
end

--- A ratio that matches neither hypothesis must be reported as ambiguous rather than
--- rounded to whichever is closer. Guessing here is how a wrong constant gets laundered
--- into the frame budget.
function M.test_ambiguous_calibration_is_reported_not_guessed()
    local clock = TickClock:new({ calibration_samples = 5 })
    local frames = {}
    for i = 0, 9 do
        frames[#frames + 1] = { 1000 + i * 16, 0.8 } -- ratio 20: neither 1 nor 1000
    end
    drive(clock, frames)

    T.assert_equal(clock:delta_time_unit(), "ambiguous")
    T.assert_nil(clock:delta_time_scale(), "an ambiguous measurement yields no scale factor")
end

--- A raw delta of zero every frame carries no information; it must not calibrate.
function M.test_zero_raw_delta_never_calibrates()
    local clock = TickClock:new({ calibration_samples = 3 })
    drive(clock, { { 1000, 0 }, { 1016, 0 }, { 1032, 0 }, { 1048, 0 }, { 1064, 0 } })
    T.assert_equal(clock:delta_time_unit(), "unknown")
end

--- The clock owns the cadence measurement (ADR 08 §13 q7).
function M.test_exposes_cadence_statistics()
    local clock = TickClock:new({ cadence = { min_samples = 3 } })
    local frames = {}
    for i = 0, 5 do frames[#frames + 1] = { 1000 + i * 20, 20 } end
    drive(clock, frames)

    local stats = clock:cadence()
    T.assert_not_nil(stats, "after enough ticks the clock must report a cadence")
    T.assert_equal(stats.median, 20)
    T.assert_near(stats.hz, 50, 0.001)
end

--- A loading screen rewinds nothing but freezes everything. The delta is real and must be
--- handed to modules truthfully; the cadence window must not absorb it.
function M.test_stall_is_reported_as_delta_but_excluded_from_cadence()
    local clock = TickClock:new({ cadence = { min_samples = 2, stall_threshold_ms = 1000 } })
    local deltas = drive(clock, {
        { 1000, 16 },
        { 1016, 16 },
        { 9016, 16 }, -- 8 s loading screen
        { 9032, 16 },
    })
    T.assert_equal(deltas[3], 8000, "the real 8 s gap must still be reported to modules")

    local stats = clock:cadence()
    T.assert_equal(stats.max, 16, "the stall must not enter the cadence window")
    T.assert_equal(stats.stalls, 1)
end

--- game_time going backwards is corrupt input, not a negative frame.
function M.test_backwards_clock_yields_zero_delta()
    local clock = TickClock:new()
    local deltas = drive(clock, { { 5000, 16 }, { 4000, 16 } })
    T.assert_equal(deltas[2], 0, "a backwards clock must clamp to 0, never emit a negative delta")
end

--- Offline and in-game the clock must be constructible with no `core` at all.
function M.test_reads_the_sdk_when_no_values_are_passed()
    local saved_game_time = core.game_time
    local saved_delta = core.delta_time
    core.game_time = function() return 12345 end
    core.delta_time = function() return 16 end

    local ok, err = pcall(function()
        local clock = TickClock:new()
        clock:tick()
        clock:tick()
    end)

    core.game_time = saved_game_time
    core.delta_time = saved_delta
    T.assert_true(ok, "tick() with no arguments must read the SDK and not throw: " .. tostring(err))
end

--- A throwing or absent SDK must degrade, not propagate -- this runs inside the tick.
function M.test_survives_a_throwing_sdk()
    local saved_game_time = core.game_time
    core.game_time = function() error("sdk exploded") end

    local ok, delta = pcall(function()
        local clock = TickClock:new()
        clock:tick()
        return clock:tick()
    end)

    core.game_time = saved_game_time
    T.assert_true(ok, "a throwing core.game_time must not propagate out of the clock")
    T.assert_equal(delta, 0, "an unreadable clock yields a 0 delta, not a fabricated one")
end

return M
