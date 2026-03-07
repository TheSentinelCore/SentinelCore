local ZoneProfile = require("modules/grind/zone_profile")
local T = require("tests/test_util")

local M = {}

local VALID_PROFILE_JSON = [[
{
    "id": "barrens_10_20",
    "name": "The Barrens (10-20)",
    "map_id": 1,
    "spots": [
        {
            "name": "Zhevra Fields",
            "center": { "x": -1248.5, "y": -3024.1, "z": 52.3 },
            "radius": 80,
            "level_min": 10,
            "level_max": 15,
            "aoe_enabled": false,
            "mob_whitelist": [],
            "mob_blacklist": ["Savannah Prowler"]
        },
        {
            "name": "Raptor Grounds",
            "center": { "x": -1400.0, "y": -3200.0, "z": 55.0 },
            "radius": 100,
            "level_min": 16,
            "level_max": 20,
            "aoe_enabled": true,
            "mob_whitelist": ["Sunscale Raptor"],
            "mob_blacklist": []
        }
    ],
    "rest_spot": { "x": -1300.0, "y": -2900.0, "z": 55.0 },
    "flee_spot": { "x": -1310.0, "y": -2910.0, "z": 56.0 }
}
]]

local NO_REST_FLEE_JSON = [[
{
    "id": "test_no_rest",
    "name": "Test No Rest/Flee",
    "map_id": 1,
    "spots": [
        {
            "name": "Only Spot",
            "center": { "x": 100.0, "y": 200.0, "z": 300.0 },
            "radius": 50,
            "level_min": 5,
            "level_max": 10
        }
    ]
}
]]

function M.run()
    -- Test: parse valid JSON with 2 spots
    local profile = ZoneProfile.parse(VALID_PROFILE_JSON)
    T.assert_not_nil(profile, "parse returns non-nil for valid JSON")
    T.assert_equal(profile.id, "barrens_10_20", "profile id")
    T.assert_equal(profile.name, "The Barrens (10-20)", "profile name")
    T.assert_equal(profile.map_id, 1, "profile map_id")
    T.assert_equal(#profile.spots, 2, "profile has 2 spots")

    -- Verify first spot
    T.assert_equal(profile.spots[1].name, "Zhevra Fields", "spot 1 name")
    T.assert_equal(profile.spots[1].center.x, -1248.5, "spot 1 center x")
    T.assert_equal(profile.spots[1].center.y, -3024.1, "spot 1 center y")
    T.assert_equal(profile.spots[1].center.z, 52.3, "spot 1 center z")
    T.assert_equal(profile.spots[1].radius, 80, "spot 1 radius")
    T.assert_equal(profile.spots[1].level_min, 10, "spot 1 level_min")
    T.assert_equal(profile.spots[1].level_max, 15, "spot 1 level_max")
    T.assert_false(profile.spots[1].aoe_enabled, "spot 1 aoe_enabled")
    T.assert_equal(#profile.spots[1].mob_blacklist, 1, "spot 1 blacklist count")

    -- Verify second spot
    T.assert_equal(profile.spots[2].name, "Raptor Grounds", "spot 2 name")
    T.assert_equal(profile.spots[2].level_min, 16, "spot 2 level_min")
    T.assert_equal(profile.spots[2].level_max, 20, "spot 2 level_max")
    T.assert_true(profile.spots[2].aoe_enabled, "spot 2 aoe_enabled")

    -- Verify rest_spot and flee_spot
    T.assert_equal(profile.rest_spot.x, -1300.0, "rest_spot x")
    T.assert_equal(profile.rest_spot.y, -2900.0, "rest_spot y")
    T.assert_equal(profile.flee_spot.x, -1310.0, "flee_spot x")
    T.assert_equal(profile.flee_spot.z, 56.0, "flee_spot z")

    -- Test: select_spot picks correct spot by level
    local spot_12 = ZoneProfile.select_spot(profile, 12)
    T.assert_equal(spot_12.name, "Zhevra Fields", "level 12 picks Zhevra Fields")

    local spot_18 = ZoneProfile.select_spot(profile, 18)
    T.assert_equal(spot_18.name, "Raptor Grounds", "level 18 picks Raptor Grounds")

    -- Test: select_spot boundary values
    local spot_10 = ZoneProfile.select_spot(profile, 10)
    T.assert_equal(spot_10.name, "Zhevra Fields", "level 10 (min) picks Zhevra Fields")

    local spot_15 = ZoneProfile.select_spot(profile, 15)
    T.assert_equal(spot_15.name, "Zhevra Fields", "level 15 (max) picks Zhevra Fields")

    local spot_16 = ZoneProfile.select_spot(profile, 16)
    T.assert_equal(spot_16.name, "Raptor Grounds", "level 16 picks Raptor Grounds")

    -- Test: select_spot falls back to first spot if no match
    local spot_60 = ZoneProfile.select_spot(profile, 60)
    T.assert_equal(spot_60.name, "Zhevra Fields", "level 60 falls back to first spot")

    -- Test: missing rest_spot/flee_spot defaults to first spot center
    local no_rest = ZoneProfile.parse(NO_REST_FLEE_JSON)
    T.assert_not_nil(no_rest, "parse no-rest profile")
    T.assert_equal(no_rest.rest_spot.x, 100.0, "default rest_spot x from first spot")
    T.assert_equal(no_rest.rest_spot.y, 200.0, "default rest_spot y from first spot")
    T.assert_equal(no_rest.rest_spot.z, 300.0, "default rest_spot z from first spot")
    T.assert_equal(no_rest.flee_spot.x, 100.0, "default flee_spot x from first spot")
    T.assert_equal(no_rest.flee_spot.y, 200.0, "default flee_spot y from first spot")
    T.assert_equal(no_rest.flee_spot.z, 300.0, "default flee_spot z from first spot")

    -- Test: parse returns nil for invalid data
    T.assert_true(ZoneProfile.parse(nil) == nil, "parse nil returns nil")
    T.assert_true(ZoneProfile.parse("") == nil, "parse empty string returns nil")
    T.assert_true(ZoneProfile.parse("not json") == nil, "parse invalid JSON returns nil")
    T.assert_true(ZoneProfile.parse("42") == nil, "parse non-table returns nil")
    T.assert_true(ZoneProfile.parse('{"spots": []}') == nil, "parse empty spots returns nil")
    T.assert_true(ZoneProfile.parse('{"spots": "bad"}') == nil, "parse non-array spots returns nil")
    T.assert_true(ZoneProfile.parse('{"spots": [{"center": null}]}') == nil, "parse spot without valid center returns nil")
    T.assert_true(ZoneProfile.parse('{"spots": ["bad"]}') == nil, "parse spot that is not a table returns nil")
end

return M
