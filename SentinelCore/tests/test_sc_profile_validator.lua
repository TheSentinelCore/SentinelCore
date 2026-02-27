-- SentinelCore/tests/test_sc_profile_validator.lua
local T = require("tests/TestUtil")

local function run()
    T.install_core_stub({})

    local Validator = require("profiles/ProfileValidator")
    local Schema = require("profiles/ProfileSchema")

    -- Test 1: Valid minimal profile passes
    local minimal = Schema.defaults()
    minimal.metadata.name = "Test Profile"
    minimal.requirements.map_id = 530
    minimal.hotspots = {
        { id = "hs1", x = 100, y = 200, z = 50, radius = 40, label = "Spot 1" },
    }
    local ok, errors = Validator.validate(minimal)
    T.assert_true(ok == true, "valid minimal profile should pass")
    T.assert_eq(#errors, 0, "no errors for valid profile")

    -- Test 2: Missing version fails
    local no_version = Schema.defaults()
    no_version.version = nil
    no_version.requirements.map_id = 530
    no_version.hotspots = { { id = "hs1", x = 1, y = 2, z = 3, radius = 10 } }
    local ok2, errors2 = Validator.validate(no_version)
    T.assert_true(ok2 == false, "missing version should fail")

    -- Test 3: Missing map_id fails
    local no_map = Schema.defaults()
    no_map.requirements.map_id = nil
    no_map.hotspots = { { id = "hs1", x = 1, y = 2, z = 3, radius = 10 } }
    local ok3, errors3 = Validator.validate(no_map)
    T.assert_true(ok3 == false, "missing map_id should fail")

    -- Test 4: Empty hotspots fails
    local no_hs = Schema.defaults()
    no_hs.requirements.map_id = 530
    no_hs.hotspots = {}
    local ok4, errors4 = Validator.validate(no_hs)
    T.assert_true(ok4 == false, "empty hotspots should fail")

    -- Test 5: Hotspot missing coordinates fails
    local bad_hs = Schema.defaults()
    bad_hs.requirements.map_id = 530
    bad_hs.hotspots = { { id = "hs1" } }
    local ok5, errors5 = Validator.validate(bad_hs)
    T.assert_true(ok5 == false, "hotspot missing coords should fail")

    -- Test 6: Duplicate hotspot IDs fail
    local dup_hs = Schema.defaults()
    dup_hs.requirements.map_id = 530
    dup_hs.hotspots = {
        { id = "same", x = 1, y = 2, z = 3, radius = 10 },
        { id = "same", x = 4, y = 5, z = 6, radius = 10 },
    }
    local ok6, errors6 = Validator.validate(dup_hs)
    T.assert_true(ok6 == false, "duplicate hotspot IDs should fail")

    return {
        sc_validator_valid = true,
        sc_validator_no_version = true,
        sc_validator_no_map = true,
        sc_validator_no_hotspots = true,
        sc_validator_bad_hotspot = true,
        sc_validator_dup_ids = true,
    }
end

return { run = run }
