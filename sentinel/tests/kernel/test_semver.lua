-- tests/kernel/test_semver.lua
-- The version gate. ADR 08 §8.2: `api = "^1.0"` checked against Sentinel.API_VERSION.
--
-- This is isolated into its own module and its own test file for one reason: a silently wrong
-- range check ADMITS INCOMPATIBLE PLUGINS, which is the exact failure the gate exists to
-- prevent. A gate that is wrong is worse than no gate, because it also stops anyone looking.
--
-- The named failure mode is string comparison: lexically "1.10" < "1.9", so a comparison that
-- never parses to numbers silently rejects every version past .9.

local Semver = require("kernel/semver")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

function M.test_parses_full_versions()
    local v = Semver.parse("1.2.3")
    T.assert_equal(v.major, 1)
    T.assert_equal(v.minor, 2)
    T.assert_equal(v.patch, 3)
end

--- "1.0" must mean 1.0.0. Manifests are written by hand and will omit the patch.
function M.test_parses_partial_versions_as_zero_filled()
    local v = Semver.parse("1.0")
    T.assert_equal(v.major, 1)
    T.assert_equal(v.minor, 0)
    T.assert_equal(v.patch, 0)

    local w = Semver.parse("2")
    T.assert_equal(w.major, 2)
    T.assert_equal(w.minor, 0)
    T.assert_equal(w.patch, 0)
end

function M.test_rejects_garbage_by_name()
    for _, bad in ipairs({ "", "abc", "1.x", "1.2.3.4", "-1.0.0", "1..2", nil, 12 }) do
        local v, reason = Semver.parse(bad)
        T.assert_nil(v, "must reject " .. tostring(bad))
        T.assert_equal(reason, "invalid_version")
    end
end

--- Pre-release identifiers are refused rather than half-supported. Their ordering rules are
--- intricate and nothing in this project needs them; accepting and then mis-ordering them
--- would be the same class of bug as string comparison.
function M.test_prerelease_versions_are_refused_by_name()
    local v, reason = Semver.parse("1.0.0-beta.1")
    T.assert_nil(v)
    T.assert_equal(reason, "prerelease_not_supported")
end

-- ---------------------------------------------------------------------------
-- Comparison -- THE named failure mode
-- ---------------------------------------------------------------------------

--- Lexically "1.10" < "1.9". Numerically 1.10 > 1.9. If this test passes, the comparison
--- parses; if the implementation ever regresses to string compare, this is what catches it.
function M.test_compares_numerically_not_lexically()
    T.assert_equal(Semver.compare("1.10.0", "1.9.0"), 1,
        "1.10.0 must be GREATER than 1.9.0 -- lexically it is not")
    T.assert_equal(Semver.compare("1.9.0", "1.10.0"), -1)
    T.assert_equal(Semver.compare("1.2.10", "1.2.9"), 1, "patch must compare numerically too")
    T.assert_equal(Semver.compare("2.0.0", "10.0.0"), -1, "major must compare numerically too")
end

function M.test_equal_versions_compare_zero()
    T.assert_equal(Semver.compare("1.2.3", "1.2.3"), 0)
    T.assert_equal(Semver.compare("1.0", "1.0.0"), 0, "a zero-filled partial equals its full form")
end

function M.test_compare_orders_by_major_then_minor_then_patch()
    T.assert_equal(Semver.compare("2.0.0", "1.99.99"), 1)
    T.assert_equal(Semver.compare("1.3.0", "1.2.99"), 1)
    T.assert_equal(Semver.compare("1.2.3", "1.2.2"), 1)
end

-- ---------------------------------------------------------------------------
-- Caret ranges -- the exit criterion
-- ---------------------------------------------------------------------------

--- "^1.0 accepts 1.5, rejects 2.0, rejects 0.9."
function M.test_caret_one_zero_accepts_the_one_series()
    T.assert_true(Semver.satisfies("1.0.0", "^1.0"), "the floor is included")
    T.assert_true(Semver.satisfies("1.5.0", "^1.0"))
    T.assert_true(Semver.satisfies("1.10.0", "^1.0"), "1.10 must satisfy ^1.0 -- the lexical trap")
    T.assert_true(Semver.satisfies("1.99.99", "^1.0"))
end

function M.test_caret_one_zero_rejects_the_next_major()
    T.assert_false(Semver.satisfies("2.0.0", "^1.0"), "a major bump is a breaking change")
    T.assert_false(Semver.satisfies("2.0.0", "^1.5"))
end

function M.test_caret_one_zero_rejects_anything_below_the_floor()
    T.assert_false(Semver.satisfies("0.9.0", "^1.0"), "0.9 is below the floor")
    T.assert_false(Semver.satisfies("0.99.99", "^1.0"))
end

--- A caret floor above the actual version must reject: ^1.5 means ">=1.5.0 <2.0.0", so 1.2
--- does not satisfy it even though the majors agree.
function M.test_a_caret_floor_above_the_version_rejects()
    T.assert_false(Semver.satisfies("1.2.0", "^1.5"), "1.2 is below the ^1.5 floor")
    T.assert_true(Semver.satisfies("1.5.0", "^1.5"))
    T.assert_true(Semver.satisfies("1.6.0", "^1.5"))
end

function M.test_caret_respects_the_patch_floor()
    T.assert_false(Semver.satisfies("1.2.2", "^1.2.3"))
    T.assert_true(Semver.satisfies("1.2.3", "^1.2.3"))
    T.assert_true(Semver.satisfies("1.2.4", "^1.2.3"))
end

-- ---------------------------------------------------------------------------
-- The pre-1.0 rule, stated explicitly
-- ---------------------------------------------------------------------------

--- Under 1.0.0 there is no stable public API, so semver gives the MINOR the breaking-change
--- role: ^0.9 means ">=0.9.0 <0.10.0", not "<1.0.0". Implemented rather than hand-waved,
--- because the wrong reading would admit 0.10 into a plugin written against 0.9 -- and pre-1.0
--- is exactly when that break is most likely.
function M.test_caret_below_one_pins_the_minor()
    T.assert_true(Semver.satisfies("0.9.0", "^0.9"))
    T.assert_true(Semver.satisfies("0.9.7", "^0.9"), "patches within the minor are compatible")
    T.assert_false(Semver.satisfies("0.10.0", "^0.9"),
        "under 1.0.0 a MINOR bump is breaking -- ^0.9 must not accept 0.10")
    T.assert_false(Semver.satisfies("1.0.0", "^0.9"))
    T.assert_false(Semver.satisfies("0.8.9", "^0.9"))
end

--- ^0.0.z is narrower still: with no stable major or minor, only the exact patch is compatible.
function M.test_caret_zero_zero_pins_the_patch()
    T.assert_true(Semver.satisfies("0.0.3", "^0.0.3"))
    T.assert_false(Semver.satisfies("0.0.4", "^0.0.3"))
    T.assert_false(Semver.satisfies("0.1.0", "^0.0.3"))
end

-- ---------------------------------------------------------------------------
-- Exact ranges and refusals
-- ---------------------------------------------------------------------------

function M.test_an_exact_range_matches_only_itself()
    T.assert_true(Semver.satisfies("1.2.3", "1.2.3"))
    T.assert_false(Semver.satisfies("1.2.4", "1.2.3"))
    T.assert_true(Semver.satisfies("1.0.0", "1.0"), "a partial exact range zero-fills")
end

--- Any operator we have not implemented is REFUSED, not approximated. A `~1.2` silently read
--- as `^1.2` would widen the gate without anyone noticing.
function M.test_unsupported_range_operators_are_refused_by_name()
    for _, range in ipairs({ "~1.2", ">=1.0", "<2.0", "1.x", "*", ">1.0 <2.0", "1.0 || 2.0" }) do
        local ok, reason = Semver.satisfies("1.5.0", range)
        T.assert_false(ok, range .. " must not be accepted")
        T.assert_equal(reason, "unsupported_range", range .. " must be refused by name")
    end
end

function M.test_a_malformed_range_is_refused_by_name()
    local ok, reason = Semver.satisfies("1.5.0", "^banana")
    T.assert_false(ok)
    T.assert_equal(reason, "invalid_range")
end

function M.test_a_malformed_version_fails_the_gate_rather_than_passing_it()
    local ok, reason = Semver.satisfies("banana", "^1.0")
    T.assert_false(ok, "an unparseable version must fail closed")
    T.assert_equal(reason, "invalid_version")
end

--- The gate must not be bypassable by omission.
function M.test_a_missing_range_is_refused()
    local ok, reason = Semver.satisfies("1.5.0", nil)
    T.assert_false(ok)
    T.assert_equal(reason, "invalid_range")
end

return M
