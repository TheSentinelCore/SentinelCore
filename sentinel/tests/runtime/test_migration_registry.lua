-- sentinel/tests/runtime/test_migration_registry.lua
-- Tests for runtime/migration_registry.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Runtime MigrationRegistry Tests ===")

    -- Clear package cache
    package.loaded["runtime/migration_registry"] = nil
    local MigrationRegistry = require("runtime/migration_registry")

    -- =====================================================================
    -- Test 1: Construction and default version
    -- =====================================================================
    print("Test 1: Construction and default version")
    local mr = MigrationRegistry:new()
    T.assert_equal(mr:get_current_version(), "1.0.0",
        "default version should be 1.0.0 (from built-in migration)")
    local history = mr:get_version_history()
    T.assert_true(#history > 0, "should have built-in migration in history")
    T.assert_equal(history[1].from, "0.0.0")
    T.assert_equal(history[1].to, "1.0.0")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Register a custom migration
    -- =====================================================================
    print("Test 2: Register a custom migration")
    local mr2 = MigrationRegistry:new()
    mr2:register("1.0.0", "2.0.0", function(profile)
        profile.schema_version = "2.0"
        profile.metadata.compiler_version = "2.0.0"
        return { profile = profile, errors = {}, warnings = {} }
    end)
    T.assert_equal(mr2:get_current_version(), "2.0.0",
        "current version should update after registration")
    local history2 = mr2:get_version_history()
    T.assert_equal(#history2, 2, "should have 2 migrations in history")
    T.assert_equal(history2[2].from, "1.0.0")
    T.assert_equal(history2[2].to, "2.0.0")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Built-in v0→v1 migration adds metadata
    -- =====================================================================
    print("Test 3: Built-in v0→v1 migration adds metadata")
    local mr3 = MigrationRegistry:new()
    local profile_v0 = {
        name = "Test Profile",
        author = "Test Author",
    }
    local result = mr3:migrate(profile_v0)
    -- profile_v0 should now have metadata
    T.assert_equal(#result.errors, 0, "should have no errors")
    T.assert_not_nil(result.profile.metadata, "metadata should exist")
    T.assert_equal(result.profile.metadata.compiler_version, "1.0.0",
        "compiler_version should be set")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Built-in v0→v1 adds schema_version
    -- =====================================================================
    print("Test 4: Built-in v0→v1 adds schema_version")
    local mr4 = MigrationRegistry:new()
    local profile_v0_4 = {
        name = "Test Profile",
        author = "Test Author",
    }
    local result4 = mr4:migrate(profile_v0_4)
    T.assert_equal(#result4.errors, 0, "should have no errors")
    T.assert_equal(result4.profile.schema_version, "1.0",
        "schema_version should be set to 1.0")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Built-in v0→v1 ensures operations array
    -- =====================================================================
    print("Test 5: Built-in v0→v1 ensures operations array")
    local mr5 = MigrationRegistry:new()
    local no_ops = { name = "Test", author = "Author" }
    local result5 = mr5:migrate(no_ops)
    T.assert_equal(#result5.errors, 0, "should have no errors")
    T.assert_equal(type(result5.profile.operations), "table",
        "operations should be a table")
    T.assert_equal(#result5.profile.operations, 0,
        "operations should be empty")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Migration detects version downgrade (M-1003)
    -- =====================================================================
    print("Test 6: Migration detects version downgrade (M-1003)")
    local mr6 = MigrationRegistry:new()
    local downgrade_profile = {
        name = "Test",
        author = "Author",
        schema_version = "2.0.0",
    }
    local result6 = mr6:migrate(downgrade_profile)
    T.assert_true(#result6.errors > 0, "should have errors for downgrade")
    local found_m1003 = false
    for _, e in ipairs(result6.errors) do
        if e.code == "M-1003" then
            found_m1003 = true
            break
        end
    end
    T.assert_true(found_m1003, "should have M-1003 error for version downgrade")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Migration not found for version jump (M-1001)
    -- =====================================================================
    print("Test 7: Migration not found for version jump (M-1001)")
    local mr7 = MigrationRegistry:new()
    -- Remove built-in migration to simulate no path
    -- Create a completely fresh registry with no migrations
    local MigrationRegistry2 = require("runtime/migration_registry")
    -- We'll use the raw metatable to bypass auto-setup
    local raw_registry = setmetatable({}, { __index = MigrationRegistry2 })
    raw_registry._migrations = {}
    raw_registry._version_chain = {}
    raw_registry._latest_version = "5.0.0"

    local jump_profile = {
        name = "Test",
        author = "Author",
        schema_version = "2.0.0",
    }
    local result7 = raw_registry:migrate(jump_profile)
    T.assert_true(#result7.errors > 0, "should have errors for missing migration path")
    local found_m1001 = false
    for _, e in ipairs(result7.errors) do
        if e.code == "M-1001" then
            found_m1001 = true
            break
        end
    end
    T.assert_true(found_m1001, "should have M-1001 error for missing migration")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Migration function fails (M-1002)
    -- =====================================================================
    print("Test 8: Migration function fails (M-1002)")
    local mr8 = MigrationRegistry:new()
    -- Register a migration that errors
    mr8:register("1.0.0", "2.0.0", function(profile)
        error("deliberate migration failure")
    end)
    local profile_m8 = {
        name = "Test",
        author = "Author",
        schema_version = "1.0.0",
        metadata = { compiler_version = "1.0.0" },
        operations = {},
    }
    local result8 = mr8:migrate(profile_m8)
    T.assert_true(#result8.errors > 0, "should have errors for failed migration")
    local found_m1002 = false
    for _, e in ipairs(result8.errors) do
        if e.code == "M-1002" then
            found_m1002 = true
            break
        end
    end
    T.assert_true(found_m1002, "should have M-1002 error for migration failure")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Unknown profile version format (M-1004)
    -- =====================================================================
    print("Test 9: Unknown profile version format (M-1004)")
    local mr9 = MigrationRegistry:new()
    local bad_version_profile = {
        name = "Test",
        author = "Author",
        schema_version = 123,  -- not a string
    }
    local result9 = mr9:migrate(bad_version_profile)
    T.assert_true(#result9.errors > 0, "should have errors for bad version format")
    local found_m1004 = false
    for _, e in ipairs(result9.errors) do
        if e.code == "M-1004" then
            found_m1004 = true
            break
        end
    end
    T.assert_true(found_m1004, "should have M-1004 error for bad version format")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Migration generates IDs for operations without them
    -- =====================================================================
    print("Test 10: Migration generates IDs for operations without them")
    local mr10 = MigrationRegistry:new()
    local profile_no_ids = {
        name = "Test",
        author = "Author",
        operations = {
            { name = "Op1" },
            { name = "Op2" },
        },
    }
    local result10 = mr10:migrate(profile_no_ids)
    T.assert_equal(#result10.errors, 0, "should have no errors")
    T.assert_not_nil(result10.profile.operations[1].id,
        "operation 1 should have generated id")
    T.assert_not_nil(result10.profile.operations[2].id,
        "operation 2 should have generated id")
    T.assert_true(result10.profile.operations[1].id ~= result10.profile.operations[2].id,
        "generated IDs should be unique, got " .. tostring(result10.profile.operations[1].id)
        .. " and " .. tostring(result10.profile.operations[2].id))
    print("  PASS")

    print("\n=== All MigrationRegistry Tests PASSED ===")
end

return M
