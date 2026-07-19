-- sentinel/tests/unit/core/test_geometry.lua
-- Tests for core/geometry.lua

local Helpers = require("tests.harness.test_helpers")

local function run_tests()
    print("=== Testing core/geometry.lua ===\n")

    -- Clear module cache
    package.loaded["core/geometry"] = nil
    local Geometry = require("core/geometry")

    -- Test 1: distance basic
    print("Test 1: distance basic")
    local p1 = { x = 0, y = 0, z = 0 }
    local p2 = { x = 3, y = 4, z = 0 }
    local dist = Geometry.distance(p1, p2)
    Helpers.assert_near(dist, 5.0, 0.001, "3-4-5 triangle")
    print("  PASS")

    -- Test 2: distance 3D
    print("Test 2: distance 3D")
    p1 = { x = 0, y = 0, z = 0 }
    p2 = { x = 1, y = 2, z = 2 }
    dist = Geometry.distance(p1, p2)
    Helpers.assert_near(dist, 3.0, 0.001, "sqrt(1+4+4)=3")
    print("  PASS")

    -- Test 3: distance nil handling
    print("Test 3: distance nil handling")
    dist = Geometry.distance(nil, p2)
    Helpers.assert_equal(dist, math.huge, "nil first arg returns infinity")
    dist = Geometry.distance(p1, nil)
    Helpers.assert_equal(dist, math.huge, "nil second arg returns infinity")
    dist = Geometry.distance(nil, nil)
    Helpers.assert_equal(dist, math.huge, "both nil returns infinity")
    -- Empty tables return valid distance since they have x,y,z = 0
    dist = Geometry.distance({}, {})
    Helpers.assert_equal(dist, 0, "empty tables have x,y,z = 0")
    print("  PASS")

    -- Test 4: distance same point
    print("Test 4: distance same point")
    p1 = { x = 5, y = 10, z = 15 }
    dist = Geometry.distance(p1, p1)
    Helpers.assert_near(dist, 0, 0.001, "distance to self is 0")
    print("  PASS")

    -- Test 5: away_from basic
    print("Test 5: away_from basic")
    local center = { x = 0, y = 0, z = 0 }
    local position = { x = 10, y = 0, z = 0 }
    local away = Geometry.away_from(center, position, 5)
    Helpers.assert_not_nil(away)
    Helpers.assert_near(away.x, 15, 0.001, "x moved away by 5")
    Helpers.assert_near(away.y, 0, 0.001, "y unchanged")
    Helpers.assert_near(away.z, 0, 0.001, "z unchanged")
    print("  PASS")

    -- Test 6: away_from 2D diagonal
    print("Test 6: away_from 2D diagonal")
    center = { x = 0, y = 0, z = 0 }
    position = { x = 3, y = 4, z = 0 }
    away = Geometry.away_from(center, position, 5)
    Helpers.assert_not_nil(away)
    -- Position is at distance 5 from center, move 5 more away = distance 10
    local away_dist = Geometry.distance(center, away)
    Helpers.assert_near(away_dist, 10, 0.001, "moved 5 units further out")
    print("  PASS")

    -- Test 7: away_from nil handling
    print("Test 7: away_from nil handling")
    away = Geometry.away_from(nil, position, 5)
    Helpers.assert_nil(away, "nil center returns nil")
    away = Geometry.away_from(center, nil, 5)
    Helpers.assert_nil(away, "nil position returns nil")
    print("  PASS")

    -- Test 8: away_from too close to center
    print("Test 8: away_from too close to center")
    center = { x = 0, y = 0, z = 0 }
    position = { x = 0.1, y = 0.1, z = 0 }
    away = Geometry.away_from(center, position, 10)
    Helpers.assert_not_nil(away)
    -- Should default to moving along positive x
    Helpers.assert_near(away.x, 10.1, 0.1, "defaults to +x direction")
    Helpers.assert_near(away.y, 0.1, 0.1, "y preserved")
    print("  PASS")

    -- Test 9: away_from preserves z
    print("Test 9: away_from preserves z")
    center = { x = 0, y = 0, z = 10 }
    position = { x = 5, y = 5, z = 20 }
    away = Geometry.away_from(center, position, 10)
    Helpers.assert_not_nil(away)
    Helpers.assert_near(away.z, 20, 0.001, "z preserved from position")
    print("  PASS")

    print("=== All Geometry Tests PASSED ===\n")
end

run_tests()