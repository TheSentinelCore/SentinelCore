-- SentinelCore/tests/test_sc031_positioning_service.lua
local T = require("tests/TestUtil")

local M = {}

function M.run()
    local env = T.install_core_stub()
    local PS = require("services/PositioningService")

    -- centroid: averages 3 positions
    local c = PS.centroid({
        { x = 0, y = 0, z = 0 },
        { x = 6, y = 12, z = 3 },
        { x = 3, y = 6, z = 6 },
    })
    assert(c, "centroid should not be nil")
    T.assert_eq(c.x, 3, "centroid x")
    T.assert_eq(c.y, 6, "centroid y")
    T.assert_eq(c.z, 3, "centroid z")

    -- centroid: nil for empty
    T.assert_eq(PS.centroid({}), nil, "centroid of empty is nil")
    T.assert_eq(PS.centroid(nil), nil, "centroid of nil is nil")

    -- kite_position: correct direction and distance
    local player = { x = 10, y = 0, z = 0 }
    local threat = { x = 0, y = 0, z = 0 }
    local kite = PS.kite_position(player, threat, 5)
    assert(kite, "kite should not be nil")
    -- Direction from threat to player is +x, so kite should be further in +x
    T.assert_true(kite.x > player.x, "kite x > player x")
    local kite_dist_from_player = math.sqrt(
        (kite.x - player.x)^2 + (kite.y - player.y)^2 + (kite.z - player.z)^2
    )
    T.assert_true(math.abs(kite_dist_from_player - 5) < 0.01, "kite distance is 5 yards")

    -- kite_position: handles zero overlap (same position)
    local overlap = PS.kite_position({ x = 5, y = 5, z = 0 }, { x = 5, y = 5, z = 0 }, 3)
    assert(overlap, "overlap kite should not be nil")
    -- Should produce a valid position offset by distance
    local overlap_dist = math.sqrt(
        (overlap.x - 5)^2 + (overlap.y - 5)^2 + (overlap.z - 0)^2
    )
    T.assert_true(math.abs(overlap_dist - 3) < 0.01, "overlap kite distance is 3 yards")

    -- aoe_center: returns centroid within range
    local aoe = PS.aoe_center(
        { x = 0, y = 0, z = 0 },
        {
            { x = 5, y = 0, z = 0 },
            { x = 7, y = 0, z = 0 },
        },
        30
    )
    assert(aoe, "aoe_center should not be nil")
    T.assert_eq(aoe.x, 6, "aoe center x is centroid")
    T.assert_eq(aoe.y, 0, "aoe center y is centroid")

    -- aoe_center: clamps when out of range
    local aoe_clamped = PS.aoe_center(
        { x = 0, y = 0, z = 0 },
        {
            { x = 40, y = 0, z = 0 },
            { x = 60, y = 0, z = 0 },
        },
        30
    )
    assert(aoe_clamped, "aoe_clamped should not be nil")
    local clamped_dist = math.sqrt(
        aoe_clamped.x^2 + aoe_clamped.y^2 + aoe_clamped.z^2
    )
    T.assert_true(math.abs(clamped_dist - 30) < 0.01,
        "clamped aoe distance should be 30, got " .. tostring(clamped_dist))

    -- in_range: true when within
    T.assert_true(
        PS.in_range({ x = 3, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, 5),
        "3 yards should be in range of 5"
    )

    -- in_range: false when outside
    T.assert_true(
        not PS.in_range({ x = 10, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, 5),
        "10 yards should NOT be in range of 5"
    )

    -- in_range: nil inputs
    T.assert_true(not PS.in_range(nil, { x = 0, y = 0, z = 0 }, 5), "nil pos returns false")
    T.assert_true(not PS.in_range({ x = 0, y = 0, z = 0 }, nil, 5), "nil ref returns false")

    env.restore()
    return true
end

return M
