-- tests/kernel/test_cond_fraction.lua
-- THE UNIT PIN. Everything else in kernel/cond depends on this file being right.
--
-- WHY THIS FILE EXISTS SEPARATELY FROM test_cond.
-- Three health scales are live in this repo at once (measured, not assumed):
--
--   * kernel/snapshot_source.lua:100   `ratio(hp, hp_max)` -> 0-1 FRACTION.
--   * runtime/sensors/player_sensor.lua:22  `if value > 1 then value = value / 100 end`
--     -> normalizes izi's 0-100 down to a 0-1 FRACTION before the blackboard sees it.
--   * modules/combat/condition_library.lua:468  `H.num(hp_pct) <= (seconds * 10)` compares
--     a RAW 0-100 `get_health_percentage` against a seconds-derived number, with no
--     conversion at all.
--
-- A mechanical port picks one of those by accident and STAYS GREEN, because every
-- assertion it copies over is expressed in whichever scale the code already used. So the
-- pin is asserted here first, in its own file, against its own module -- before a single
-- predicate exists to be mis-scaled.
--
-- Individual `test*` functions, never a `run()` aggregator: the offline runner counts a
-- `run()` suite as ONE unit, which would hide how many boundary cases actually exist.

local Fraction = require("kernel/cond/fraction")
local T = require("tests/test_util")

local M = {}

-- ============================================================================
-- THE PIN ITSELF
-- ============================================================================

--- The canonical scale is 0-1, chosen to match the snapshot rather than the SDK, because
--- the snapshot is what predicates actually read. Stated as an executable fact so that
--- changing the pin requires changing a test that says PIN in its name -- invariant 3
--- ("if a pin must change, STOP and report") needs somewhere loud to stop.
function M.test_the_pin_is_zero_to_one()
    T.assert_equal(Fraction.MIN, 0, "the canonical fraction floor is 0")
    T.assert_equal(Fraction.MAX, 1, "the canonical fraction ceiling is 1 -- NOT 100")
end

-- ============================================================================
-- THRESHOLDS -- the call-site side of the mis-scale
-- ============================================================================
--
-- `health_below(30)` meaning "30 percent" is the exact defect this rejects. Under a 0-1
-- pin it is not merely wrong, it is ALWAYS TRUE: every real health_pct is <= 1 < 30. A
-- gate that never gates is invisible in review and invisible in play. So it raises.

function M.test_a_fraction_threshold_is_accepted()
    T.assert_equal(Fraction.threshold(0.30, "test"), 0.30, "0.30 is a valid fraction")
    T.assert_equal(Fraction.threshold(0, "test"), 0, "0 is a valid fraction")
    T.assert_equal(Fraction.threshold(1, "test"), 1, "1 is a valid fraction")
end

--- The headline case from the brief. 30 is a percentage, not a fraction.
function M.test_a_percentage_threshold_raises_rather_than_never_gating()
    local ok, err = pcall(Fraction.threshold, 30, "health_below")
    T.assert_false(ok, "threshold(30) must raise -- under a 0-1 pin it would never gate")
    T.assert_true(tostring(err):find("0%-1") ~= nil,
        "the error must name the expected scale, got: " .. tostring(err))
    T.assert_true(tostring(err):find("health_below") ~= nil,
        "the error must name the caller so the fix site is obvious, got: " .. tostring(err))
end

--- 100 is the other end of the same mistake -- `health_below(100)` reading as "below full".
function M.test_one_hundred_raises_as_a_threshold()
    T.assert_false(pcall(Fraction.threshold, 100, "health_below"),
        "threshold(100) must raise")
end

--- Just past the ceiling. Guards the comparison in `threshold` being `>` and not `>=`,
--- which would reject the legitimate 1.0.
function M.test_just_above_one_raises_but_exactly_one_does_not()
    T.assert_false(pcall(Fraction.threshold, 1.0001, "test"), "1.0001 is not a fraction")
    T.assert_true(pcall(Fraction.threshold, 1.0, "test"), "1.0 IS a fraction")
end

function M.test_a_negative_threshold_raises()
    T.assert_false(pcall(Fraction.threshold, -0.1, "test"), "a negative fraction is not a fraction")
end

function M.test_a_non_number_threshold_raises()
    T.assert_false(pcall(Fraction.threshold, "0.3", "test"),
        "a numeric string is not a number -- do not tonumber() at the boundary")
    T.assert_false(pcall(Fraction.threshold, nil, "test"), "nil is not a threshold")
    T.assert_false(pcall(Fraction.threshold, true, "test"), "a boolean is not a threshold")
end

-- ============================================================================
-- SOURCE VALUES -- the other side of the mis-scale
-- ============================================================================
--
-- A threshold guard alone only catches the mistake a rotation author makes. It does NOT
-- catch a SENSOR that starts writing 0-100 into `health_pct`. That direction is worse:
-- every threshold stays a legal fraction, so nothing raises, and every gate silently
-- inverts. `read` closes it -- a source value outside the pin is UNREADABLE, not a
-- number to be trusted, so it becomes nil and the predicate above it returns Unknown.

function M.test_a_fraction_source_value_reads_through()
    T.assert_equal(Fraction.read(0.29), 0.29, "0.29 is a readable fraction")
    T.assert_equal(Fraction.read(0), 0, "0 (dead) is readable, and is NOT nil")
    T.assert_equal(Fraction.read(1), 1, "1 (full) is readable")
end

--- The mis-scaled-sensor case. 30 arriving where a fraction belongs means the source
--- changed scale underneath us; answering "is 30 below 0.30" with False would be a
--- confident wrong answer. Unreadable is the honest one.
function M.test_a_percentage_source_value_reads_as_unreadable()
    T.assert_nil(Fraction.read(30), "30 is not on the 0-1 pin -- it must not be trusted")
    T.assert_nil(Fraction.read(100), "100 is not on the 0-1 pin")
    T.assert_nil(Fraction.read(-1), "a negative health fraction is not readable")
end

--- ADR 08 §9.3 -- an unreadable vital is nil, never a plausible-looking zero.
function M.test_a_missing_source_value_reads_as_unreadable()
    T.assert_nil(Fraction.read(nil), "nil in, nil out -- never a defaulted 0 or 1")
    T.assert_nil(Fraction.read("0.5"), "a string is not a readable number")
    T.assert_nil(Fraction.read(true), "a boolean is not a readable number")
end

-- ============================================================================
-- THE SINGLE CONVERSION POINT
-- ============================================================================
--
-- The brief requires the conversion to live "in exactly one place you can point at".
-- This is the place. If a percentage ever has to cross into the kernel, it crosses here
-- and nowhere else -- see test_cond_no_stray_scale_factors, which enforces that by
-- scanning the kernel/cond tree for any other `/ 100` or `* 100`.

function M.test_from_percent_is_the_conversion()
    T.assert_equal(Fraction.from_percent(100), 1, "100% is the full fraction 1")
    T.assert_equal(Fraction.from_percent(0), 0, "0% is the empty fraction 0")
    T.assert_near(Fraction.from_percent(29), 0.29, 1e-9, "29% is 0.29")
    T.assert_near(Fraction.from_percent(31), 0.31, 1e-9, "31% is 0.31")
end

--- Round-trip: whatever `from_percent` produces must be something `read` accepts, or the
--- two halves of the boundary disagree and the conversion has no consumer.
function M.test_from_percent_produces_values_read_accepts()
    for _, percent in ipairs({ 0, 1, 29, 30, 31, 50, 99, 100 }) do
        T.assert_not_nil(Fraction.read(Fraction.from_percent(percent)),
            "from_percent(" .. percent .. ") must land inside the pin")
    end
end

function M.test_from_percent_rejects_out_of_range_percentages()
    T.assert_false(pcall(Fraction.from_percent, 101), "101% is not a percentage")
    T.assert_false(pcall(Fraction.from_percent, -1), "-1% is not a percentage")
    T.assert_false(pcall(Fraction.from_percent, "50"), "a string is not a percentage")
end

return M
