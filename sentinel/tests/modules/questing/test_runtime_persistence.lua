-- tests/modules/questing/test_runtime_persistence.lua
-- Unit tests for progress persistence save/load (Wave 5)
-- Tests: serialization, save file creation, fingerprint matching, auto-save

local RuntimeProfile = require("modules/questing/runtime_profile")
local T = require("tests/test_util")

local M = {}

-- ============================================================================
-- Helpers
-- ============================================================================

--- File I/O mock: capture written data in a table.
--- NOTE: write_data_file is called via pcall(core.write_data_file, core, path, content)
--- so the mock receives (self, path, content).
--- read_data_file is called as core.read_data_file(path) (plain function, no self).
local written_files = {}

--- Set up minimal global state for testing.
local function mock_globals()
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    _G.core.unit = _G.core.unit or {}
    _G.core.input = _G.core.input or {}
    _G.core.write_data_file = function(self, path, content)
        written_files[path] = content
        return true
    end
    _G.core.read_data_file = function(path)
        return written_files[path]
    end
    _G.JSON = _G.JSON or {}
    _G.SentinelNavClient = {
        client = {
            move_to = function() return true end,
            stop = function() end,
            get_state = function() return "idle" end,
            get_full_state = function() return "idle" end,
            get_progress = function() return {} end,
            get_destination = function() return nil end,
            get_path_index = function() return 1 end,
            get_current_path = function() return {} end,
        },
    }
end

--- Create a minimal profile with a content_hash.
local function make_profile_ops(action_type, payload)
    return {
        content_hash = "abc123hash",
        operations = {
            {
                id = 1,
                action = { type = action_type or "Comment", payload = payload or { text = "test" } },
                next_condition = "auto",
            },
        },
    }
end

--- Create a RuntimeProfile with mocked profile data.
local function create_profile(profile_data)
    mock_globals()
    local profile = RuntimeProfile:new("test_profile.json")
    profile._profile = profile_data or make_profile_ops()
    -- Ensure save path is derived from the JSON path
    profile._save_path = profile:_compute_save_path()
    return profile
end

-- ============================================================================
-- W5.2 — Save/load state tests
-- ============================================================================

function M.test_save_creates_save_file()
    written_files = {}
    local profile = create_profile(make_profile_ops("Comment", { text = "hello" }))

    -- Advance to operation 2 (simulate progress)
    profile._current_operation_idx = 2
    profile._variables = { gold = 100 }

    local ok = profile:_save()
    T.assert_true(ok, "Save should succeed")

    -- Check the save file was written
    local save_path = profile._save_path
    local content = written_files[save_path]
    T.assert_not_nil(content, "Save file should exist")

    -- Verify content contains key fields
    T.assert_true(content:find("profile_fingerprint") ~= nil, "Save should have profile_fingerprint")
    T.assert_true(content:find("abc123hash") ~= nil, "Save should have correct fingerprint")
    T.assert_true(content:find("current_operation_idx") ~= nil, "Save should have operation index")
    T.assert_true(content:find("variables") ~= nil, "Save should have variables")
    T.assert_true(content:find("version") ~= nil, "Save should have version")
end

function M.test_restore_state_from_save()
    written_files = {}
    local profile = create_profile(make_profile_ops("Comment", { text = "test" }))

    -- Simulate progress and save
    profile._current_operation_idx = 3
    profile._variables = { quest_done = true }
    profile:_save()

    -- Create a new profile instance (as if restarting)
    local profile2 = create_profile(make_profile_ops("Comment", { text = "test" }))

    -- Load save
    local restored = profile2:_load_save()
    T.assert_true(restored, "Save should be restored successfully")
    T.assert_equal(profile2._current_operation_idx, 3,
        "Operation index should be restored from save")
    T.assert_equal(profile2._variables.quest_done, true,
        "Variables should be restored from save")
end

function M.test_fingerprint_mismatch_rejects_save()
    written_files = {}
    local profile = create_profile(make_profile_ops("Comment", { text = "v1" }))
    profile._current_operation_idx = 5
    profile:_save()

    -- Create profile with different fingerprint (simulating recompiled profile)
    local profile2 = create_profile({
        content_hash = "differentHash",
        operations = {
            { id = 1, action = { type = "Comment", payload = { text = "v2" } }, next_condition = "auto" },
        },
    })

    local restored = profile2:_load_save()
    T.assert_false(restored, "Save with mismatched fingerprint should not restore")
    T.assert_equal(profile2._current_operation_idx, 1,
        "Should start at operation 1 when fingerprint mismatch")
end

function M.test_empty_fingerprint_starts_fresh()
    written_files = {}
    -- Create profile without content_hash
    local profile = create_profile({
        operations = {
            { id = 1, action = { type = "Comment", payload = { text = "test" } }, next_condition = "auto" },
        },
    })
    -- profile._profile.content_hash should be nil

    -- Create a save file
    profile._current_operation_idx = 2
    profile:_save()

    -- Try to load on a fresh profile
    local profile2 = create_profile({
        operations = {
            { id = 1, action = { type = "Comment", payload = { text = "test" } }, next_condition = "auto" },
        },
    })
    local restored = profile2:_load_save()
    T.assert_false(restored, "Empty fingerprint should not restore")
end

function M.test_no_save_file_returns_false()
    written_files = {} -- Empty, no saves
    local profile = create_profile(make_profile_ops())
    local restored = profile:_load_save()
    T.assert_false(restored, "No save file should return false")
end

-- ============================================================================
-- W5.2 — Serialization tests
-- ============================================================================

function M.test_serialize_state_includes_all_fields()
    local profile = create_profile(make_profile_ops())
    profile._current_operation_idx = 4
    profile._variables = { key = "val" }

    local state = profile:_serialize_state()
    T.assert_equal(state.version, 1, "Version should be 1")
    T.assert_equal(state.profile_fingerprint, "abc123hash", "Fingerprint should match profile")
    T.assert_equal(state.current_operation_idx, 4, "Operation index should match")
    T.assert_equal(state.variables.key, "val", "Variables should match")
    T.assert_not_nil(state.saved_at, "saved_at timestamp should be present")
end

-- ============================================================================
-- W5.3 — Auto-save tests
-- ============================================================================

function M.test_auto_save_on_advance_operation()
    written_files = {}
    local profile = create_profile(make_profile_ops("Comment", { text = "op1" }))

    -- Execute (should succeed and advance via _advance_operation)
    profile:execute()

    -- Check if save was triggered
    local save_path = profile._save_path
    local content = written_files[save_path]
    -- After success, operation should be 2 (advanced past op 1)
    T.assert_equal(profile._current_operation_idx, 2,
        "Operation should have advanced")
end

function M.test_auto_save_on_skipped_advance()
    written_files = {}
    local profile = create_profile({
        content_hash = "testhash",
        operations = {
            {
                id = 1,
                action = { type = "Condition", payload = { condition = { type = "LevelAtLeast", payload = 100 } } },
                next_condition = "auto",
            },
        },
    })
    -- LevelAtLeast(100) will fail (mock context returns level 1), so it's "skipped"

    profile:execute()

    -- Operation should advance (skipped advances)
    T.assert_equal(profile._current_operation_idx, 2,
        "Skipped action should advance operation")
end

-- ============================================================================
-- Run all tests
-- ============================================================================

local tests = {
    test_save_creates_save_file = M.test_save_creates_save_file,
    test_restore_state_from_save = M.test_restore_state_from_save,
    test_fingerprint_mismatch_rejects_save = M.test_fingerprint_mismatch_rejects_save,
    test_empty_fingerprint_starts_fresh = M.test_empty_fingerprint_starts_fresh,
    test_no_save_file_returns_false = M.test_no_save_file_returns_false,
    test_serialize_state_includes_all_fields = M.test_serialize_state_includes_all_fields,
    test_auto_save_on_advance_operation = M.test_auto_save_on_advance_operation,
    test_auto_save_on_skipped_advance = M.test_auto_save_on_skipped_advance,
}

function M.run()
    for name, fn in pairs(tests) do
        local ok, err = pcall(fn)
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
