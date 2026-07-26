-- tests/modules/questing/test_runtime_arch_polish.lua
-- Tests for ADR-017 Wave 4 (Tickets 15-18): Runtime Architecture Polish
-- Covers: editor extraction, variable init, hot reload, v2 persistence

local RuntimeProfile = require("modules/questing/runtime_profile")
local RuntimeAction = require("modules/questing/runtime_action")
local T = require("tests/test_util")

local M = {}

-- ============================================================================
-- Mock globals and helpers
-- ============================================================================

local written_files = {}
local file_mtimes = {}
local file_contents = {}

local function mock_globals()
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    _G.core.unit = _G.core.unit or {}
    _G.core.input = _G.core.input or {}
    _G.core.quests = _G.core.quests or {}
    _G.core.inventory = _G.core.inventory or {}
    _G.core.time = function() return os.clock() end

    -- File I/O mocks
    -- Sylvannas signature: core.write_data_file(filename, data) — NO self (see persistence suite).
    _G.core.write_data_file = function(path, content)
        written_files[path] = content
        file_contents[path] = content  -- sync so read can find it
        return true
    end
    _G.core.read_data_file = function(path)
        return file_contents[path] or written_files[path]
    end
    _G.core.write_file = function(path, content)
        written_files[path] = content
        file_contents[path] = content
        return true
    end

    -- File info mock (for hot reload mtime)
    _G.core.get_file_info = function(path)
        local mtime = file_mtimes[path]
        if mtime then
            return { mtime = mtime }
        end
        return nil
    end

    -- JSON mock backed by the SHIPPED parser (core/JSON) — the same one the runtime uses in-game.
    -- This previously emitted Lua literals (`{["k"]=v}`) and parsed them with `load()`, which only
    -- worked because runtime_profile carried a matching `load("return "..json)` fallback. That
    -- fallback is dead in the Sylvannas sandbox (no global JSON, no usable `load`), so the runtime
    -- could not read a real compiled profile in-game at all. Fixtures must be real JSON for these
    -- tests to mean anything.
    local CoreJson = select(2, pcall(require, "core/JSON"))
    _G.JSON = _G.JSON or {}
    _G.JSON.parse = function(str)
        if type(str) ~= "string" then return nil end
        local ok, result = pcall(CoreJson.decode, str)
        if ok then return result end
        return nil
    end
    _G.JSON.stringify = function(tbl)
        local ok, str = pcall(CoreJson.encode, tbl)
        if ok then return str end
        return nil
    end

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

local function reset_mocks()
    written_files = {}
    file_mtimes = {}
    file_contents = {}
end

local function make_profile(overrides)
    overrides = overrides or {}
    return {
        content_hash = overrides.content_hash or "testhash",
        variables = overrides.variables or {},
        operations = {
            {
                id = 1,
                actions = {
                    { type = overrides.action_type or "Comment", payload = overrides.action_payload or { text = "test" } },
                },
                next_condition = "auto",
            },
        },
    }
end

local function create_profile(profile_data, json_path)
    mock_globals()
    reset_mocks()
    json_path = json_path or "test_profile.json"
    -- Make the file readable
    local json_str = _G.JSON.stringify(profile_data or make_profile())
    file_contents[json_path] = json_str
    file_mtimes[json_path] = 1000

    local profile = RuntimeProfile:new(json_path)
    -- Bypass load() to set profile directly for testing
    -- (load() would try to read the file and parse it)
    profile._profile = profile_data or make_profile()
    profile._save_path = profile:_compute_save_path()

    -- Initialize variables from profile defaults (same as load() does)
    profile._variables = {}
    if profile._profile.variables then
        for _, v in ipairs(profile._profile.variables) do
            profile._variables[v.name] = v.default_value or 0
        end
    end

    return profile
end

-- ============================================================================
-- T17 — Task 2.2: Variable initialization from profile defaults
-- ============================================================================

function M.test_variable_init_from_profile_defaults()
    mock_globals()
    reset_mocks()

    local json_path = "test_profile.json"
    local profile_data = make_profile({
        variables = {
            { name = "counter", default_value = 0 },
            { name = "target_count", default_value = 10 },
            { name = "use_auto_loot", default_value = 1 },
        },
    })
    file_contents[json_path] = _G.JSON.stringify(profile_data)
    file_mtimes[json_path] = 1000

    local profile = RuntimeProfile:new(json_path)
    profile._profile = profile_data
    profile._save_path = profile:_compute_save_path()

    -- Call load() which should init variables
    -- But we need to properly set up the mock for read_data_file first
    local result = profile:load()

    T.assert_true(result, "load() should succeed")

    -- Check variables initialized from defaults
    T.assert_equal(profile._variables.counter, 0,
        "counter should default to 0")
    T.assert_equal(profile._variables.target_count, 10,
        "target_count should default to 10")
    T.assert_equal(profile._variables.use_auto_loot, 1,
        "use_auto_loot should default to 1")
end

function M.test_variable_init_missing_defaults_use_zero()
    mock_globals()
    reset_mocks()

    local json_path = "test_profile.json"
    local profile_data = make_profile({
        variables = {
            { name = "no_default" },           -- no default_value
            { name = "explicit_zero", default_value = 0 },
        },
    })
    file_contents[json_path] = _G.JSON.stringify(profile_data)
    file_mtimes[json_path] = 1000

    local profile = RuntimeProfile:new(json_path)
    profile._profile = profile_data
    profile._save_path = profile:_compute_save_path()

    profile:load()

    T.assert_equal(profile._variables.no_default, 0,
        "Missing default_value should use 0")
    T.assert_equal(profile._variables.explicit_zero, 0,
        "Explicit 0 default should be 0")
end

-- ============================================================================
-- T16 — Task 3.3: Hot reload preserves _variables across profile swap
-- ============================================================================

function M.test_hot_reload_swap_preserves_variables()
    mock_globals()
    reset_mocks()

    local json_path = "test_profile.json"
    local initial_hash = "hash_v1"
    local new_hash = "hash_v2"

    -- Set up initial profile in the file
    local initial_profile = make_profile({
        content_hash = initial_hash,
        variables = {
            { name = "counter", default_value = 0 },
            { name = "target_count", default_value = 10 },
        },
        action_type = "Comment",
    })
    file_contents[json_path] = _G.JSON.stringify(initial_profile)
    file_mtimes[json_path] = 1000

    -- Create profile instance
    local profile = RuntimeProfile:new(json_path)
    profile._profile = initial_profile
    profile._save_path = profile:_compute_save_path()
    profile._json_mtime = nil  -- will be set on first check

    -- Init variables from defaults
    profile._variables = {}
    if profile._profile.variables then
        for _, v in ipairs(profile._profile.variables) do
            profile._variables[v.name] = v.default_value or 0
        end
    end

    -- Set some runtime values on variables
    profile._variables.counter = 42
    profile._variables.target_count = 5

    -- Now change the file contents (new hash, different variables)
    local new_profile = make_profile({
        content_hash = new_hash,
        variables = {
            { name = "counter", default_value = 0 },
            { name = "target_count", default_value = 20 },
            { name = "new_var", default_value = 99 },
        },
        action_type = "Comment",
    })
    file_contents[json_path] = _G.JSON.stringify(new_profile)
    file_mtimes[json_path] = 2000  -- mtime changed

    -- Trigger hot reload
    profile:_check_hot_reload()

    -- Verify profile was swapped
    T.assert_equal(profile._profile.content_hash, new_hash,
        "Profile should be swapped to new hash")

    -- Verify preserved variables kept their runtime values
    T.assert_equal(profile._variables.counter, 42,
        "counter should preserve runtime value 42")
    T.assert_equal(profile._variables.target_count, 5,
        "target_count should preserve runtime value 5")

    -- Verify new variable got its default
    T.assert_equal(profile._variables.new_var, 99,
        "new_var should get default value 99 from new profile")
end

function M.test_hot_reload_guards_on_state()
    mock_globals()
    reset_mocks()

    local json_path = "test_profile.json"
    local initial_hash = "hash_v1"

    local initial_profile = make_profile({ content_hash = initial_hash })
    file_contents[json_path] = _G.JSON.stringify(initial_profile)
    file_mtimes[json_path] = 1000

    local profile = RuntimeProfile:new(json_path)
    profile._profile = initial_profile
    profile._save_path = profile:_compute_save_path()
    profile._state = "failed"  -- Not running!

    -- Set a new file
    local new_profile = make_profile({ content_hash = "hash_v2" })
    file_contents[json_path] = _G.JSON.stringify(new_profile)
    file_mtimes[json_path] = 2000

    profile:_check_hot_reload()

    -- Profile should NOT have swapped because state != "running"
    T.assert_equal(profile._profile.content_hash, initial_hash,
        "Profile should NOT swap when state is not 'running'")
end

function M.test_hot_reload_skips_on_hash_match()
    mock_globals()
    reset_mocks()

    local json_path = "test_profile.json"
    local hash = "same_hash"

    local profile_data = make_profile({ content_hash = hash })
    file_contents[json_path] = _G.JSON.stringify(profile_data)
    file_mtimes[json_path] = 1000

    local profile = RuntimeProfile:new(json_path)
    profile._profile = profile_data
    profile._save_path = profile:_compute_save_path()
    profile._json_mtime = 500  -- old mtime
    profile._variables.counter = 5

    -- Same hash, new mtime
    file_mtimes[json_path] = 2000

    profile:_check_hot_reload()

    -- Profile should NOT swap since hash is the same
    T.assert_equal(profile._profile.content_hash, hash,
        "Profile should NOT swap when content_hash is the same")
    T.assert_equal(profile._variables.counter, 5,
        "Variables should be untouched")
end

-- ============================================================================
-- T18 — Task 4.3: v2 save/load round-trip (all 7 fields)
-- ============================================================================

function M.test_v2_serialize_includes_all_fields()
    mock_globals()
    reset_mocks()

    local profile_data = make_profile({ content_hash = "testhash" })
    local profile = create_profile(profile_data)

    -- Set v2 state fields
    profile._current_action_idx = 3
    profile._completed_quests = { ["33"] = true, ["45"] = true }
    profile._temporary_variables = { temp_key = "temp_val" }
    profile._visited_vendors = { ["1000"] = true }
    profile._known_flight_paths = { ["The Sepulcher"] = true }
    profile._known_hearth_location = { x = -9000, y = 100, z = 50 }
    profile._execution_log = {
        { event = "action_success", timestamp = 1000 },
    }

    local state = profile:_serialize_state()

    T.assert_equal(state.version, 2, "Version should be 2")
    T.assert_equal(state.current_action_idx, 3, "current_action_idx should match")
    -- Count keys in dict table (can't use # on dicts)
    local quest_count = 0
    for _ in pairs(state.completed_quests) do quest_count = quest_count + 1 end
    T.assert_equal(quest_count, 2, "completed_quests should have 2 entries")
    T.assert_true(state.completed_quests["33"], "completed_quests should contain '33'")
    T.assert_equal(state.temporary_variables.temp_key, "temp_val",
        "temporary_variables should preserve values")
    T.assert_true(state.visited_vendors["1000"], "visited_vendors should be set")
    T.assert_true(state.known_flight_paths["The Sepulcher"],
        "known_flight_paths should be set")
    T.assert_equal(state.known_hearth_location.x, -9000,
        "known_hearth_location should preserve x")
    T.assert_equal(#state.execution_history, 1,
        "execution_history should have 1 entry")
    T.assert_equal(state.execution_history[1].event, "action_success",
        "execution_history entry should preserve event type")
end

function M.test_v2_round_trip_save_and_load()
    mock_globals()
    reset_mocks()

    local profile_data = make_profile({ content_hash = "roundtriphash" })
    local json_path = "roundtrip_profile.json"
    file_contents[json_path] = _G.JSON.stringify(profile_data)
    file_mtimes[json_path] = 1000

    local profile = RuntimeProfile:new(json_path)
    profile._profile = profile_data
    profile._save_path = profile:_compute_save_path()

    -- Set v2 state fields
    profile._current_action_idx = 3
    profile._current_operation_idx = 2
    profile._variables = { my_var = "hello" }
    profile._completed_quests = { ["33"] = true }
    profile._temporary_variables = { tmp = 1 }
    profile._visited_vendors = { ["2000"] = true }
    profile._known_flight_paths = { ["Tarren Mill"] = true }
    profile._known_hearth_location = { x = 100, y = 200, z = 30 }
    profile._execution_log = {
        { event = "action_success", timestamp = 5000 },
    }

    -- Save to file via mock
    local save_ok = profile:_save()
    T.assert_true(save_ok, "v2 save should succeed")

    -- Now create a new profile that will load from the save
    local profile2 = RuntimeProfile:new(json_path)
    profile2._profile = profile_data
    profile2._save_path = profile2:_compute_save_path()

    -- Load save
    local restored = profile2:_load_save()
    T.assert_true(restored, "v2 save should restore successfully")

    -- Verify all fields
    -- Resume deliberately restarts the operation rather than restoring the action index: actions
    -- run Travel-then-work, so resuming mid-operation drops the character onto (say) a Kill while
    -- standing wherever the last session ended. Re-running the leading Travels is cheap.
    T.assert_equal(profile2._current_action_idx, 1,
        "resume restarts the operation so its positioning Travels re-run")
    T.assert_equal(profile2._current_operation_idx, 2,
        "current_operation_idx should be restored")
    T.assert_equal(profile2._variables.my_var, "hello",
        "variables should be restored")
    T.assert_true(profile2._completed_quests["33"],
        "completed_quests should be restored")
    T.assert_equal(profile2._temporary_variables.tmp, 1,
        "temporary_variables should be restored")
    T.assert_true(profile2._visited_vendors["2000"],
        "visited_vendors should be restored")
    T.assert_true(profile2._known_flight_paths["Tarren Mill"],
        "known_flight_paths should be restored")
    T.assert_equal(profile2._known_hearth_location.x, 100,
        "known_hearth_location should be restored")
    -- execution_log has original entry + save_restored event from _load_save
    T.assert_true(#profile2._execution_log >= 1,
        "execution_log should have at least the save_restored event")
    T.assert_equal(profile2._execution_log[1].event, "action_success",
        "Original execution_log entry should be preserved")
end

-- ============================================================================
-- T18 — Task 4.4: v1 save file gracefully triggers fresh start
-- ============================================================================

function M.test_v1_save_triggers_fingerprint_mismatch()
    mock_globals()
    reset_mocks()

    local json_path = "test_profile.json"
    local profile_data = make_profile({ content_hash = "current_hash" })
    file_contents[json_path] = _G.JSON.stringify(profile_data)
    file_mtimes[json_path] = 1000

    -- Create a v1-format save file manually
    local v1_save = {
        version = 1,
        profile_fingerprint = "old_hash",  -- different from current_hash
        current_operation_idx = 5,
        variables = { some_var = 1 },
        saved_at = 1000,
    }
    local save_path = "test_profile.save.json"
    written_files[save_path] = _G.JSON.stringify(v1_save)
    -- Also set up core.read_data_file to return it
    file_contents[save_path] = written_files[save_path]

    local profile = RuntimeProfile:new(json_path)
    profile._profile = profile_data
    profile._save_path = profile:_compute_save_path()
    profile._current_operation_idx = 1

    -- Load save — should fail due to fingerprint mismatch
    local restored = profile:_load_save()
    T.assert_false(restored,
        "v1 save with mismatched fingerprint should NOT restore")
    T.assert_equal(profile._current_operation_idx, 1,
        "Operation index should remain at 1 (fresh start)")
end

function M.test_v1_save_no_fingerprint_starts_fresh()
    mock_globals()
    reset_mocks()

    local json_path = "test_profile.json"
    local profile_data = make_profile({ content_hash = "myhash" })
    file_contents[json_path] = _G.JSON.stringify(profile_data)
    file_mtimes[json_path] = 1000

    local save_path = "test_profile.save.json"
    local v1_save = {
        version = 1,
        -- no profile_fingerprint
        current_operation_idx = 5,
        variables = { x = 1 },
        saved_at = 1000,
    }
    file_contents[save_path] = _G.JSON.stringify(v1_save)

    local profile = RuntimeProfile:new(json_path)
    profile._profile = profile_data
    profile._save_path = profile:_compute_save_path()

    local restored = profile:_load_save()
    T.assert_false(restored,
        "Save with no fingerprint should NOT restore")
end

-- ============================================================================
-- T18 — Task 4.4: v1 save with matching fingerprint and v2 fields absent
-- ============================================================================

function M.test_v1_save_gracefully_handles_missing_v2_fields()
    mock_globals()
    reset_mocks()

    local json_path = "test_profile.json"
    local profile_data = make_profile({ content_hash = "match_hash" })
    file_contents[json_path] = _G.JSON.stringify(profile_data)
    file_mtimes[json_path] = 1000

    local save_path = "test_profile.save.json"
    local v1_save = {
        version = 1,
        profile_fingerprint = "match_hash",
        current_operation_idx = 3,
        variables = { migrated = true },
        saved_at = 1000,
        -- No v2 fields at all
    }
    file_contents[save_path] = _G.JSON.stringify(v1_save)

    local profile = RuntimeProfile:new(json_path)
    profile._profile = profile_data
    profile._save_path = profile:_compute_save_path()

    -- Load v1 save — should still restore (fingerprint matches)
    -- v2 fields should be nil-safe defaults
    local restored = profile:_load_save()
    T.assert_true(restored,
        "v1 save with matching fingerprint should restore")
    T.assert_equal(profile._current_operation_idx, 3,
        "Operation index should restore from v1 save")
    T.assert_equal(profile._variables.migrated, true,
        "Variables should restore from v1 save")
    -- v2 fields should have been initialized as empty/nil
    T.assert_equal(profile._current_action_idx, 1,
        "v2 field current_action_idx should default to 1")
    T.assert_equal(type(profile._completed_quests), "table",
        "v2 field completed_quests should be a table")
    -- execution_log has the save_restored event appended by _load_save
    T.assert_true(#profile._execution_log >= 1,
        "execution_log should contain save_restored event")
end

-- ============================================================================
-- T17/T18 — Task 5.3: Integration — SetVariable -> save -> reload -> assert
-- ============================================================================

function M.test_setvariable_save_reload_roundtrip()
    mock_globals()
    reset_mocks()

    local json_path = "integration_profile.json"
    local profile_data = make_profile({
        content_hash = "integ_hash",
        variables = {
            { name = "my_var", default_value = 0 },
        },
        action_type = "SetVariable",
        action_payload = { name = "my_var", value = 42 },
    })
    file_contents[json_path] = _G.JSON.stringify(profile_data)
    file_mtimes[json_path] = 1000

    local profile = RuntimeProfile:new(json_path)
    profile._profile = profile_data
    profile._save_path = profile:_compute_save_path()

    -- Initialize variables from profile defaults
    profile._variables = {}
    if profile._profile.variables then
        for _, v in ipairs(profile._profile.variables) do
            profile._variables[v.name] = v.default_value or 0
        end
    end

    -- Execute SetVariable action
    local ctx = profile:create_context()
    local action = profile._profile.operations[1].actions[1]
    local status = RuntimeAction.execute(action, ctx)
    T.assert_equal(status, "success", "SetVariable should succeed")
    T.assert_equal(profile._variables.my_var, 42,
        "Variable should be set to 42 after execution")

    -- Save state
    local save_ok = profile:_save()
    T.assert_true(save_ok, "Save should succeed")

    -- Create a new profile instance (simulating reload)
    file_contents[json_path] = _G.JSON.stringify(profile_data)
    file_contents[profile._save_path] = written_files[profile._save_path]

    local profile2 = RuntimeProfile:new(json_path)
    profile2._profile = profile_data
    profile2._save_path = profile2:_compute_save_path()

    -- Init variables from defaults (as load() would)
    profile2._variables = {}
    if profile2._profile.variables then
        for _, v in ipairs(profile2._profile.variables) do
            profile2._variables[v.name] = v.default_value or 0
        end
    end

    -- Load save
    local restored = profile2:_load_save()
    T.assert_true(restored, "Save should restore after reload")

    -- Assert SetVariable value is preserved across save/load
    T.assert_equal(profile2._variables.my_var, 42,
        "SetVariable value 42 should survive save/reload")
end

-- ============================================================================
-- Task 5.2: SetVariable writes to ctx.variables (ref to profile._variables)
-- ============================================================================

function M.test_setvariable_writes_to_ctx_variables_ref()
    mock_globals()
    reset_mocks()

    local profile = create_profile(make_profile({ content_hash = "test" }))

    local ctx = profile:create_context()
    local action = { type = "SetVariable", payload = { name = "ref_test", value = 99 } }
    local status = RuntimeAction.execute(action, ctx)

    T.assert_equal(status, "success", "SetVariable should succeed")
    -- ctx.variables IS profile._variables (same table reference)
    T.assert_equal(ctx.variables.ref_test, 99,
        "ctx.variables should have the value")
    T.assert_equal(profile._variables.ref_test, 99,
        "profile._variables should have the value (same ref)")
end

-- ============================================================================
-- Run all tests
-- ============================================================================

local tests = {
    -- T17 — Variable initialization
    test_variable_init_from_profile_defaults = M.test_variable_init_from_profile_defaults,
    test_variable_init_missing_defaults_use_zero = M.test_variable_init_missing_defaults_use_zero,

    -- T16 — Hot reload
    test_hot_reload_swap_preserves_variables = M.test_hot_reload_swap_preserves_variables,
    test_hot_reload_guards_on_state = M.test_hot_reload_guards_on_state,
    test_hot_reload_skips_on_hash_match = M.test_hot_reload_skips_on_hash_match,

    -- T18 — v2 persistence
    test_v2_serialize_includes_all_fields = M.test_v2_serialize_includes_all_fields,
    test_v2_round_trip_save_and_load = M.test_v2_round_trip_save_and_load,
    test_v1_save_triggers_fingerprint_mismatch = M.test_v1_save_triggers_fingerprint_mismatch,
    test_v1_save_no_fingerprint_starts_fresh = M.test_v1_save_no_fingerprint_starts_fresh,
    test_v1_save_gracefully_handles_missing_v2_fields = M.test_v1_save_gracefully_handles_missing_v2_fields,

    -- Integration
    test_setvariable_writes_to_ctx_variables_ref = M.test_setvariable_writes_to_ctx_variables_ref,
    test_setvariable_save_reload_roundtrip = M.test_setvariable_save_reload_roundtrip,
}

function M.run()
    -- Deterministic order: `pairs` iteration varies per run, which turned shared-fixture leakage
    -- between these tests into a failure that moved around and looked flaky. Sorting makes any
    -- remaining ordering dependency reproducible instead of intermittent.
    local names = {}
    for name in pairs(tests) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(tests[name])
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
