-- sentinel/tests/runtime/test_profile_manager.lua
-- Tests for runtime/profile_manager.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Runtime ProfileManager Tests ===")

    -- Set up mock core with file I/O
    local _files = {}  -- path → content

    _G.core = _G.core or {}
    _G.core.read_data_file = function(path)
        return _files[path]
    end
    _G.core.write_data_file = function(path, data)
        _files[path] = data
        return true
    end
    _G.core.create_data_folder = function() end

    local function set_file(path, content)
        _files[path] = content
    end

    local function get_file(path)
        return _files[path]
    end

    local function clear_files()
        _files = {}
    end

    -- Clear package cache
    package.loaded["runtime/profile_manager"] = nil
    local ProfileManager = require("runtime/profile_manager")

    -- Helper: create a valid profile
    local function make_valid_profile(overrides)
        overrides = overrides or {}
        return {
            name = overrides.name or "Test Profile",
            author = overrides.author or "Agent",
            schema_version = overrides.schema_version or "1.0.0",
            operations = overrides.operations or {},
            metadata = overrides.metadata or {},
        }
    end

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local pm = ProfileManager.new()
    T.assert_equal(pm:get_profiles_dir(), "sentinel/profiles")
    T.assert_false(pm:is_dirty(), "should start clean")
    T.assert_nil(pm:get_active_profile_id(), "no active profile initially")
    T.assert_nil(pm:get_active_profile(), "no active profile table initially")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Custom profiles directory
    -- =====================================================================
    print("Test 2: Custom profiles directory")
    local pm2 = ProfileManager.new({ profiles_dir = "custom/path" })
    T.assert_equal(pm2:get_profiles_dir(), "custom/path")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Dirty tracking
    -- =====================================================================
    print("Test 3: Dirty tracking")
    local pm3 = ProfileManager.new()
    T.assert_false(pm3:is_dirty(), "should start clean")
    pm3:mark_dirty()
    T.assert_true(pm3:is_dirty(), "should be dirty after mark")
    pm3:clear_dirty()
    T.assert_false(pm3:is_dirty(), "should be clean after clear")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Validate nil profile
    -- =====================================================================
    print("Test 4: Validate nil profile")
    local errors = ProfileManager.validate(nil)
    T.assert_true(#errors > 0, "should report error for nil profile")
    T.assert_true(errors[1]:find("nil") ~= nil, "error should mention nil")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Validate empty profile
    -- =====================================================================
    print("Test 5: Validate empty profile")
    errors = ProfileManager.validate({})
    T.assert_true(#errors > 0, "should report errors for empty profile")
    local has_name_error = false
    for _, e in ipairs(errors) do
        if e:find("name") then has_name_error = true end
    end
    T.assert_true(has_name_error, "should report missing name")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Validate valid profile
    -- =====================================================================
    print("Test 6: Validate valid profile")
    errors = ProfileManager.validate(make_valid_profile())
    T.assert_equal(#errors, 0, "valid profile should have no errors: " .. table.concat(errors, "; "))
    print("  PASS")

    -- =====================================================================
    -- Test 7: Validate missing fields individually
    -- =====================================================================
    print("Test 7: Validate missing fields individually")
    -- Missing author
    errors = ProfileManager.validate({ name = "Test", schema_version = "1.0.0" })
    local has_author_error = false
    for _, e in ipairs(errors) do
        if e:find("author") then has_author_error = true end
    end
    T.assert_true(has_author_error, "should report missing author")

    -- Missing schema_version
    errors = ProfileManager.validate({ name = "Test", author = "Agent" })
    local has_version_error = false
    for _, e in ipairs(errors) do
        if e:find("schema_version") then has_version_error = true end
    end
    T.assert_true(has_version_error, "should report missing schema_version")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Validate duplicate operation IDs
    -- =====================================================================
    print("Test 8: Validate duplicate operation IDs")
    errors = ProfileManager.validate(make_valid_profile({
        operations = {
            { id = "op-1", name = "Op1" },
            { id = "op-1", name = "Op2" },
        }
    }))
    local has_dup_error = false
    for _, e in ipairs(errors) do
        if e:find("duplicate operation") then has_dup_error = true end
    end
    T.assert_true(has_dup_error, "should detect duplicate operation IDs")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Validate duplicate action IDs
    -- =====================================================================
    print("Test 9: Validate duplicate action IDs")
    errors = ProfileManager.validate(make_valid_profile({
        operations = {
            {
                id = "op-1",
                name = "Op1",
                actions = {
                    { id = "act-1", name = "Action1" },
                    { id = "act-1", name = "Action2" },
                }
            }
        }
    }))
    local has_action_dup = false
    for _, e in ipairs(errors) do
        if e:find("duplicate action") then has_action_dup = true end
    end
    T.assert_true(has_action_dup, "should detect duplicate action IDs")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Validate operation missing name
    -- =====================================================================
    print("Test 10: Validate operation missing name")
    errors = ProfileManager.validate(make_valid_profile({
        operations = {
            { id = "op-1" }
        }
    }))
    local has_op_name_error = false
    for _, e in ipairs(errors) do
        if e:find("missing name") then has_op_name_error = true end
    end
    T.assert_true(has_op_name_error, "should detect missing operation name")
    print("  PASS")

    -- =====================================================================
    -- Test 11: Load profile from disk
    -- =====================================================================
    print("Test 11: Load profile from disk")
    local pm11 = ProfileManager.new()
    set_file("test/profile.json", '{"name":"Loaded","author":"Test","schema_version":"1.0.0","operations":[]}')
    local profile, load_err = pm11:load("test/profile.json")
    T.assert_not_nil(profile, "should load profile")
    T.assert_nil(load_err, "should have no error")
    T.assert_equal(profile.name, "Loaded")
    T.assert_equal(profile.author, "Test")
    print("  PASS")

    -- =====================================================================
    -- Test 12: Load nonexistent file
    -- =====================================================================
    print("Test 12: Load nonexistent file")
    local pm12 = ProfileManager.new()
    local p12, err12 = pm12:load("nonexistent.json")
    T.assert_nil(p12, "should return nil for nonexistent file")
    T.assert_not_nil(err12, "should return error for nonexistent file")
    print("  PASS")

    -- =====================================================================
    -- Test 13: Load invalid JSON
    -- =====================================================================
    print("Test 13: Load invalid JSON")
    local pm13 = ProfileManager.new()
    set_file("bad.json", "not json {{{")
    local p13, err13 = pm13:load("bad.json")
    T.assert_nil(p13, "should return nil for invalid JSON")
    T.assert_not_nil(err13, "should return error for invalid JSON")
    print("  PASS")

    -- =====================================================================
    -- Test 14: Load profile that fails validation
    -- =====================================================================
    print("Test 14: Load profile that fails validation")
    local pm14 = ProfileManager.new()
    set_file("invalid.json", '{"operations":[]}')
    local p14, err14 = pm14:load("invalid.json")
    T.assert_nil(p14, "should return nil for invalid profile")
    T.assert_not_nil(err14, "should return validation error")
    print("  PASS")

    -- =====================================================================
    -- Test 15: Load with no path
    -- =====================================================================
    print("Test 15: Load with no path")
    local pm15 = ProfileManager.new()
    local p15, err15 = pm15:load(nil)
    T.assert_nil(p15, "should return nil for nil path")
    T.assert_not_nil(err15, "should return error for nil path")
    print("  PASS")

    -- =====================================================================
    -- Test 16: Save profile to disk
    -- =====================================================================
    print("Test 16: Save profile to disk")
    clear_files()
    local pm16 = ProfileManager.new()
    local ok16, save_err16 = pm16:save("profiles/test.json", make_valid_profile())
    T.assert_true(ok16, "should save successfully")
    T.assert_nil(save_err16, "should have no error")
    local saved = get_file("profiles/test.json")
    T.assert_not_nil(saved, "file should exist after save")
    -- Parse the saved JSON to verify it's valid
    local parsed = ProfileManager.parse_json(pm16, saved)
    T.assert_not_nil(parsed, "saved file should be valid JSON")
    T.assert_equal(parsed.name, "Test Profile")
    -- Metadata should have updated_at
    T.assert_not_nil(parsed.metadata.updated_at, "metadata should have updated_at")
    print("  PASS")

    -- =====================================================================
    -- Test 17: Save nil profile
    -- =====================================================================
    print("Test 17: Save nil profile")
    local pm17 = ProfileManager.new()
    local ok17, err17 = pm17:save("test.json", nil)
    T.assert_nil(ok17, "should return nil for nil profile")
    T.assert_not_nil(err17, "should return error for nil profile")
    print("  PASS")

    -- =====================================================================
    -- Test 18: Save clears dirty flag
    -- =====================================================================
    print("Test 18: Save clears dirty flag")
    clear_files()
    local pm18 = ProfileManager.new()
    pm18:mark_dirty()
    T.assert_true(pm18:is_dirty())
    pm18:save("test.json", make_valid_profile())
    T.assert_false(pm18:is_dirty(), "should be clean after save")
    print("  PASS")

    -- =====================================================================
    -- Test 19: Activate/deactivate profile
    -- =====================================================================
    print("Test 19: Activate/deactivate profile")
    local Blackboard = require("core/blackboard")
    local bb = Blackboard:new()
    local pm19 = ProfileManager.new()

    local ok19, act_err = pm19:activate(bb, "profile-abc")
    T.assert_true(ok19, "should activate successfully")
    T.assert_nil(act_err, "should have no error")
    T.assert_equal(pm19:get_active_profile_id(), "profile-abc")
    T.assert_equal(bb:get("module.runtime.active_profile"), "profile-abc")

    -- Deactivate
    local ok19d, deact_err = pm19:deactivate(bb)
    T.assert_true(ok19d, "should deactivate successfully")
    T.assert_nil(deact_err, "should have no error")
    T.assert_nil(pm19:get_active_profile_id(), "active profile should be nil")
    T.assert_nil(bb:get("module.runtime.active_profile"), "blackboard should be nil")
    print("  PASS")

    -- =====================================================================
    -- Test 20: Activate with nil params
    -- =====================================================================
    print("Test 20: Activate with nil params")
    local pm20 = ProfileManager.new()
    local ok20, err20 = pm20:activate(nil, "id")
    T.assert_nil(ok20, "should fail with nil blackboard")
    T.assert_not_nil(err20, "should return error")
    print("  PASS")

    -- =====================================================================
    -- Test 21: Set/get active profile table
    -- =====================================================================
    print("Test 21: Set/get active profile table")
    local pm21 = ProfileManager.new()
    T.assert_nil(pm21:get_active_profile(), "should start nil")
    local prof21 = make_valid_profile({ name = "Active Test" })
    pm21:set_active_profile(prof21)
    T.assert_not_nil(pm21:get_active_profile(), "should have active profile")
    T.assert_equal(pm21:get_active_profile().name, "Active Test")
    print("  PASS")

    -- =====================================================================
    -- Test 22: Compile (placeholder)
    -- =====================================================================
    print("Test 22: Compile (placeholder)")
    local pm22 = ProfileManager.new()
    local prof22 = make_valid_profile()
    local compiled, comp_err = pm22:compile(prof22)
    T.assert_not_nil(compiled, "compile should return profile")
    T.assert_nil(comp_err, "compile should have no error")
    T.assert_equal(compiled.name, prof22.name, "compiled should preserve data")
    print("  PASS")

    -- =====================================================================
    -- Test 23: Compile nil
    -- =====================================================================
    print("Test 23: Compile nil")
    local pm23 = ProfileManager.new()
    local c23, e23 = pm23:compile(nil)
    T.assert_nil(c23, "compile nil should return nil")
    T.assert_not_nil(e23, "compile nil should return error")
    print("  PASS")

    -- =====================================================================
    -- Test 24: List profiles (placeholder)
    -- =====================================================================
    print("Test 24: List profiles (placeholder)")
    local pm24 = ProfileManager.new()
    local list = pm24:list_profiles()
    T.assert_equal(type(list), "table", "should return a table")
    print("  PASS")

    -- =====================================================================
    -- Test 25: JSON encode/decode round-trip
    -- =====================================================================
    print("Test 25: JSON encode/decode round-trip")
    local pm25 = ProfileManager.new()
    local test_data = { name = "Test", numbers = { 1, 2, 3 }, nested = { key = "value" } }
    local encoded, enc_err = pm25:encode_json(test_data)
    T.assert_not_nil(encoded, "encode should succeed")
    T.assert_nil(enc_err, "encode should have no error")
    local decoded, dec_err = pm25:parse_json(encoded)
    T.assert_not_nil(decoded, "decode should succeed")
    T.assert_nil(dec_err, "decode should have no error")
    T.assert_equal(decoded.name, "Test")
    T.assert_equal(decoded.numbers[2], 2)
    T.assert_equal(decoded.nested.key, "value")
    print("  PASS")

    -- =====================================================================
    -- Test 26: Load empty path
    -- =====================================================================
    print("Test 26: Load empty path")
    local pm26 = ProfileManager.new()
    local p26, err26 = pm26:load("")
    T.assert_nil(p26, "should return nil for empty path")
    T.assert_not_nil(err26, "should return error for empty path")
    print("  PASS")

    -- =====================================================================
    -- Test 27: No core API available
    -- =====================================================================
    print("Test 27: No core API available")
    local saved_read = _G.core.read_data_file
    _G.core.read_data_file = nil
    local pm27 = ProfileManager.new()
    local p27, err27 = pm27:load("test.json")
    T.assert_nil(p27, "should return nil when API unavailable")
    T.assert_not_nil(err27, "should return error when API unavailable")
    _G.core.read_data_file = saved_read
    print("  PASS")

    print("\n=== All ProfileManager Tests PASSED ===")
end

return M
