-- sentinel/tests/runtime/test_compiler_bridge.lua
-- Tests for runtime/compiler_bridge.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Runtime CompilerBridge Tests ===")

    -- Clear package cache
    package.loaded["runtime/compiler_bridge"] = nil
    package.loaded["runtime/migration_registry"] = nil

    local Blackboard = require("core/blackboard")
    local EventBus = require("core/event_bus")
    local CompilerBridge = require("runtime/compiler_bridge")
    local ProfileManager = require("runtime/profile_manager")

    -- Helper: create a valid profile
    local function make_profile(overrides)
        overrides = overrides or {}
        return {
            name = overrides.name or "Test Profile",
            author = overrides.author or "Test Author",
            schema_version = overrides.schema_version or "1.0.0",
            operations = overrides.operations or {},
            metadata = overrides.metadata or { compiler_version = "1.0.0" },
        }
    end

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local bb1 = Blackboard:new()
    local eb1 = EventBus:new()
    local pm1 = ProfileManager:new()
    local cb1 = CompilerBridge:new(bb1, eb1, pm1)
    T.assert_not_nil(cb1, "should construct")
    T.assert_false(cb1:is_compiling(), "should not be compiling initially")
    T.assert_nil(cb1:get_last_result(), "should have no last result initially")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Compile empty profile returns valid RuntimeProfile
    -- =====================================================================
    print("Test 2: Compile empty profile returns valid RuntimeProfile")
    local bb2 = Blackboard:new()
    local eb2 = EventBus:new()
    local pm2 = ProfileManager:new()
    local profile2 = make_profile()
    pm2:set_active_profile(profile2)
    local cb2 = CompilerBridge:new(bb2, eb2, pm2)

    local compile_result = nil
    local compile_error = nil
    cb2:compile(function(err, runtime_profile)
        compile_error = err
        compile_result = runtime_profile
    end)

    T.assert_nil(compile_error, "should compile without error")
    T.assert_not_nil(compile_result, "should return a runtime profile")
    T.assert_equal(compile_result.schema_version, "1.0",
        "schema_version should be 1.0")
    T.assert_equal(compile_result.compiler_version, "0.1.0",
        "compiler_version should be 0.1.0")
    T.assert_equal(compile_result.profile_id, "Test Profile",
        "profile_id should match profile name")
    T.assert_not_nil(compile_result.metadata.compiled_at,
        "should have compiled_at timestamp")
    T.assert_equal(#compile_result.operations, 0,
        "should have empty operations")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Compile with operations transforms them correctly
    -- =====================================================================
    print("Test 3: Compile with operations transforms them correctly")
    local bb3 = Blackboard:new()
    local eb3 = EventBus:new()
    local pm3 = ProfileManager:new()
    local profile3 = make_profile({
        operations = {
            {
                id = "op-1",
                name = "Grind",
                action_type = "grind",
                priority = 50,
                entry_conditions = {
                    { type = "health", operator = ">", value = 20 },
                },
                goals = {
                    { type = "xp", value = 100 },
                },
                actions = {
                    { id = "act-1", action_type = "move", params = { range = 30 } },
                    { id = "act-2", action_type = "attack", params = { target = "nearest" } },
                },
            },
        },
    })
    pm3:set_active_profile(profile3)
    local cb3 = CompilerBridge:new(bb3, eb3, pm3)

    local comp3_result = nil
    cb3:compile(function(err, rp)
        comp3_result = rp
    end)

    T.assert_not_nil(comp3_result, "should return runtime profile")
    T.assert_equal(#comp3_result.operations, 1, "should have 1 operation")
    T.assert_equal(comp3_result.operations[1].id, "op-1")
    T.assert_equal(comp3_result.operations[1].name, "Grind")
    T.assert_equal(#comp3_result.operations[1].entry_conditions, 1,
        "should preserve entry conditions")
    T.assert_equal(#comp3_result.operations[1].goals, 1,
        "should preserve goals")
    T.assert_equal(#comp3_result.operations[1].actions, 2,
        "should have 2 actions")
    T.assert_equal(comp3_result.operations[1].actions[1].id, "act-1")
    T.assert_equal(comp3_result.operations[1].actions[2].action_type, "attack")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Compile with duplicate IDs returns validation error
    -- =====================================================================
    print("Test 4: Compile with duplicate IDs returns validation error")
    local bb4 = Blackboard:new()
    local eb4 = EventBus:new()
    local pm4 = ProfileManager:new()
    local profile4 = make_profile({
        operations = {
            { id = "dup-1", name = "Op1" },
            { id = "dup-1", name = "Op2" },
        },
    })
    pm4:set_active_profile(profile4)
    local cb4 = CompilerBridge:new(bb4, eb4, pm4)

    local comp4_err = nil
    cb4:compile(function(err, rp)
        comp4_err = err
    end)

    T.assert_not_nil(comp4_err, "should have error for duplicate IDs")
    -- Check that the error contains a V-1006 error
    if type(comp4_err) == "table" and comp4_err[1] then
        local found_dup = false
        for _, e in ipairs(comp4_err) do
            if e.code == "V-1006" then
                found_dup = true
                break
            end
        end
        T.assert_true(found_dup, "should have V-1006 error for duplicate IDs")
    end
    print("  PASS")

    -- =====================================================================
    -- Test 5: get_last_result returns cached result
    -- =====================================================================
    print("Test 5: get_last_result returns cached result")
    local bb5 = Blackboard:new()
    local eb5 = EventBus:new()
    local pm5 = ProfileManager:new()
    local profile5 = make_profile()
    pm5:set_active_profile(profile5)
    local cb5 = CompilerBridge:new(bb5, eb5, pm5)

    cb5:compile(function() end)

    local last = cb5:get_last_result()
    T.assert_not_nil(last, "should have last result after compile")
    T.assert_true(last.success, "should be success")
    T.assert_not_nil(last.runtime_profile, "should have runtime profile")
    T.assert_true(last.duration_ms >= 0, "should have duration")
    -- Run another compile and verify it updates
    local profile5b = make_profile({ name = "Second Profile" })
    pm5:set_active_profile(profile5b)
    cb5:compile(function() end)
    local last2 = cb5:get_last_result()
    T.assert_equal(last2.runtime_profile.profile_id, "Second Profile",
        "last result should update after second compile")
    print("  PASS")

    -- =====================================================================
    -- Test 6: is_compiling returns correct state
    -- =====================================================================
    print("Test 6: is_compiling returns correct state")
    local bb6 = Blackboard:new()
    local eb6 = EventBus:new()
    local pm6 = ProfileManager:new()
    pm6:set_active_profile(make_profile())
    local cb6 = CompilerBridge:new(bb6, eb6, pm6)

    T.assert_false(cb6:is_compiling(), "should not be compiling before start")
    cb6:compile(function()
        T.assert_false(cb6:is_compiling(), "should not be compiling after callback")
    end)
    print("  PASS")

    -- =====================================================================
    -- Test 7: Events emitted during compile
    -- =====================================================================
    print("Test 7: Events emitted during compile")
    local bb7 = Blackboard:new()
    local events_log = {}
    local eb7 = EventBus:new()
    eb7:subscribe("compile:started", function(payload)
        table.insert(events_log, "compile:started")
    end)
    eb7:subscribe("compile:stage_complete", function(payload)
        table.insert(events_log, "compile:stage_complete:" .. payload.stage)
    end)
    eb7:subscribe("compile:completed", function(payload)
        table.insert(events_log, "compile:completed")
    end)
    eb7:subscribe("compile:failed", function(payload)
        table.insert(events_log, "compile:failed")
    end)

    local pm7 = ProfileManager:new()
    pm7:set_active_profile(make_profile())
    local cb7 = CompilerBridge:new(bb7, eb7, pm7)
    cb7:compile(function() end)

    T.assert_true(#events_log >= 3, "should have at least 3 events")
    local found_started = false
    local found_completed = false
    for _, evt in ipairs(events_log) do
        if evt == "compile:started" then found_started = true end
        if evt == "compile:completed" then found_completed = true end
    end
    T.assert_true(found_started, "should have compile:started event")
    T.assert_true(found_completed, "should have compile:completed event")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Compile with no active profile returns error
    -- =====================================================================
    print("Test 8: Compile with no active profile returns error")
    local bb8 = Blackboard:new()
    local eb8 = EventBus:new()
    local pm8 = ProfileManager:new()
    -- No profile set
    local cb8 = CompilerBridge:new(bb8, eb8, pm8)

    local comp8_err = nil
    cb8:compile(function(err, rp)
        comp8_err = err
    end)

    T.assert_not_nil(comp8_err, "should have error for no active profile")
    print("  PASS")

    -- =====================================================================
    -- Test 9: compile_async works (same as compile)
    -- =====================================================================
    print("Test 9: compile_async works (same as compile)")
    local bb9 = Blackboard:new()
    local eb9 = EventBus:new()
    local pm9 = ProfileManager:new()
    pm9:set_active_profile(make_profile())
    local cb9 = CompilerBridge:new(bb9, eb9, pm9)

    local async_result = nil
    cb9:compile_async(function(err, rp)
        async_result = rp
    end)

    T.assert_not_nil(async_result, "compile_async should produce result")
    T.assert_equal(async_result.schema_version, "1.0")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Compile stores result in blackboard
    -- =====================================================================
    print("Test 10: Compile stores result in blackboard")
    local bb10 = Blackboard:new()
    local eb10 = EventBus:new()
    local pm10 = ProfileManager:new()
    pm10:set_active_profile(make_profile({ name = "Blackboard Test" }))
    local cb10 = CompilerBridge:new(bb10, eb10, pm10)

    cb10:compile(function() end)

    local stored = bb10:get("module.runtime.last_compile")
    T.assert_not_nil(stored, "should store result in blackboard")
    T.assert_true(stored.success, "stored result should indicate success")
    T.assert_not_nil(stored.runtime_profile, "stored result should have profile")
    print("  PASS")

    print("\n=== All CompilerBridge Tests PASSED ===")
end

return M
