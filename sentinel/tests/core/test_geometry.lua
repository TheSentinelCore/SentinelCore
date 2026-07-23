-- F5: Geometry.distance / Geometry.distance_sq must both use math.huge as the
-- single "unmeasurable" sentinel, consistently, so nothing in the codebase
-- keeps a private 99999/999999999 sentinel that disagrees with it.
local Geometry = require("core/geometry")
local T = require("tests/test_util")

local M = {}

function M.run()
    local a = { x = 0, y = 0, z = 0 }
    local b = { x = 3, y = 4, z = 0 }

    -- Sane inputs: distance and distance_sq agree (sqrt(distance_sq) == distance).
    T.assert_near(Geometry.distance(a, b), 5.0, 0.0001, "3-4-5 triangle distance")
    T.assert_near(Geometry.distance_sq(a, b), 25.0, 0.0001, "3-4-5 triangle distance_sq")

    -- Unmeasurable inputs: both functions return math.huge, for every kind of bad input.
    T.assert_equal(Geometry.distance(nil, b), math.huge, "distance(nil, b) is math.huge")
    T.assert_equal(Geometry.distance(a, nil), math.huge, "distance(a, nil) is math.huge")
    T.assert_equal(Geometry.distance(nil, nil), math.huge, "distance(nil, nil) is math.huge")
    T.assert_equal(Geometry.distance(false, b), math.huge, "distance(false, b) is math.huge")
    T.assert_equal(Geometry.distance("not a table", b), math.huge, "distance(string, b) is math.huge")

    T.assert_equal(Geometry.distance_sq(nil, b), math.huge, "distance_sq(nil, b) is math.huge")
    T.assert_equal(Geometry.distance_sq(a, nil), math.huge, "distance_sq(a, nil) is math.huge")
    T.assert_equal(Geometry.distance_sq(nil, nil), math.huge, "distance_sq(nil, nil) is math.huge")
    T.assert_equal(Geometry.distance_sq(false, b), math.huge, "distance_sq(false, b) is math.huge")
    T.assert_equal(Geometry.distance_sq("not a table", b), math.huge, "distance_sq(string, b) is math.huge")

    -- The two sentinels must be THE SAME value (consistency across the module),
    -- not merely "both very large".
    T.assert_equal(Geometry.distance(nil, b), Geometry.distance_sq(nil, b), "distance and distance_sq share one sentinel")

    -- distance_sq must stay usable as a nearest-neighbor comparator even when
    -- one side is unmeasurable: a real point must always compare "nearer" than
    -- an unmeasurable one.
    T.assert_true(Geometry.distance_sq(a, b) < Geometry.distance_sq(a, nil), "measurable distance_sq sorts before math.huge")
end

return M
