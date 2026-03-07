local ProfileValidator = require("modules/grind/profile_validator")
local T = require("tests/test_util")

local M = {}

local function make_valid_profile()
    return {
        schema_version = "2.0",
        metadata = { name = "Test Profile" },
        requirements = { map_id = 1 },
        hotspots = {
            { id = "spot_1", x = 100, y = 200, z = 10 }
        },
    }
end

function M.run()
    -- Valid minimal profile passes
    do
        local p = make_valid_profile()
        local valid, errors = ProfileValidator.validate(p)
        T.assert_true(valid, "valid minimal profile should pass")
        T.assert_equal(#errors, 0, "valid profile should have 0 errors")
    end

    -- Missing schema_version -> invalid
    do
        local p = make_valid_profile()
        p.schema_version = nil
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "missing schema_version should fail")
        T.assert_true(#errors > 0, "missing schema_version should produce errors")
    end

    -- Wrong schema_version -> invalid
    do
        local p = make_valid_profile()
        p.schema_version = "1.0"
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "wrong schema_version should fail")
    end

    -- Missing metadata -> invalid
    do
        local p = make_valid_profile()
        p.metadata = nil
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "missing metadata should fail")
    end

    -- Missing metadata.name -> invalid
    do
        local p = make_valid_profile()
        p.metadata = {}
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "missing metadata.name should fail")
    end

    -- Empty metadata.name -> invalid
    do
        local p = make_valid_profile()
        p.metadata.name = ""
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "empty metadata.name should fail")
    end

    -- Missing requirements -> invalid
    do
        local p = make_valid_profile()
        p.requirements = nil
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "missing requirements should fail")
    end

    -- Missing requirements.map_id -> invalid
    do
        local p = make_valid_profile()
        p.requirements = {}
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "missing requirements.map_id should fail")
    end

    -- Empty hotspots array -> invalid
    do
        local p = make_valid_profile()
        p.hotspots = {}
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "empty hotspots should fail")
    end

    -- Hotspot missing id -> invalid
    do
        local p = make_valid_profile()
        p.hotspots = { { x = 10, y = 20, z = 0 } }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "hotspot missing id should fail")
    end

    -- Hotspot missing x -> invalid
    do
        local p = make_valid_profile()
        p.hotspots = { { id = "s1", y = 20, z = 0 } }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "hotspot missing x should fail")
    end

    -- Duplicate hotspot IDs -> invalid
    do
        local p = make_valid_profile()
        p.hotspots = {
            { id = "dup", x = 1, y = 2, z = 3 },
            { id = "dup", x = 4, y = 5, z = 6 },
        }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "duplicate hotspot IDs should fail")
    end

    -- Valid NpcRef in npc_whitelist -> valid
    do
        local p = make_valid_profile()
        p.target_defaults = {
            npc_whitelist = {
                { npc_id = 1234, name = "Good Mob" },
            },
        }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_true(valid, "valid NpcRef in whitelist should pass")
    end

    -- Invalid NpcRef (missing npc_id) -> invalid
    do
        local p = make_valid_profile()
        p.target_defaults = {
            npc_whitelist = {
                { name = "No ID Mob" },
            },
        }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "NpcRef missing npc_id should fail")
    end

    -- Valid vendor -> valid
    do
        local p = make_valid_profile()
        p.vendors = {
            { npc_id = 100, name = "Vendor Bob", x = 10, y = 20, z = 0, services = { "repair" } },
        }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_true(valid, "valid vendor should pass")
    end

    -- Vendor with invalid service -> invalid
    do
        local p = make_valid_profile()
        p.vendors = {
            { npc_id = 100, name = "Vendor Bob", x = 10, y = 20, z = 0, services = { "dance" } },
        }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "vendor with invalid service should fail")
    end

    -- Valid blackspot -> valid
    do
        local p = make_valid_profile()
        p.blackspots = {
            { x = 50, y = 60, z = 0, radius = 10 },
        }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_true(valid, "valid blackspot should pass")
    end

    -- Blackspot with radius 0 -> invalid
    do
        local p = make_valid_profile()
        p.blackspots = {
            { x = 50, y = 60, z = 0, radius = 0 },
        }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "blackspot with radius 0 should fail")
    end

    -- Options with dry_spell_secs < 5 -> invalid
    do
        local p = make_valid_profile()
        p.options = { dry_spell_secs = 3 }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "dry_spell_secs < 5 should fail")
    end

    -- Multiple errors collected (not just first)
    do
        local p = {
            schema_version = "3.0",  -- wrong
            -- metadata missing
            -- requirements missing
            hotspots = {},           -- empty
        }
        local valid, errors = ProfileValidator.validate(p)
        T.assert_false(valid, "multiple issues should fail")
        T.assert_true(#errors > 1, "should collect multiple errors, got " .. #errors)
    end
end

return M
