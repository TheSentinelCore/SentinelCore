-- sentinel/tests/runtime/test_compile_pipeline.lua
-- Tests for runtime/compile_pipeline.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Runtime CompilePipeline Tests ===")

    -- Clear package cache
    package.loaded["runtime/compile_pipeline"] = nil
    package.loaded["runtime/compiler_bridge"] = nil
    package.loaded["runtime/migration_registry"] = nil

    local Blackboard = require("core/blackboard")
    local EventBus = require("core/event_bus")
    local ProfileManager = require("runtime/profile_manager")
    local CompilerBridge = require("runtime/compiler_bridge")
    local MigrationRegistry = require("runtime/migration_registry")
    local CompilePipeline = require("runtime/compile_pipeline")

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
    -- Test 1: Construction and initial state
    -- =====================================================================
    print("Test 1: Construction and initial state")
    local bb1 = Blackboard:new()
    local eb1 = EventBus:new()
    local pm1 = ProfileManager:new()
    local mr1 = MigrationRegistry:new()
    local cb1 = CompilerBridge:new(bb1, eb1, pm1)
    local cp1 = CompilePipeline:new(bb1, eb1, pm1, cb1, mr1)
    T.assert_not_nil(cp1, "should construct")
    T.assert_equal(cp1:get_pipeline_state(), "idle",
        "initial state should be idle")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Full pipeline: migrate → validate → compile → success
    -- =====================================================================
    print("Test 2: Full pipeline: migrate → validate → compile → success")
    local bb2 = Blackboard:new()
    local eb2 = EventBus:new()
    local pm2 = ProfileManager:new()
    local mr2 = MigrationRegistry:new()
    local profile2 = make_profile({
        name = "Pipeline Test",
        operations = {
            {
                id = "op-1",
                name = "Grind",
                action_type = "grind",
                actions = {
                    { id = "act-1", action_type = "move" },
                },
            },
        },
    })
    pm2:set_active_profile(profile2)
    local cb2 = CompilerBridge:new(bb2, eb2, pm2)
    local cp2 = CompilePipeline:new(bb2, eb2, pm2, cb2, mr2)

    local result2 = cp2:run()
    T.assert_true(result2.success, "pipeline should succeed")
    T.assert_not_nil(result2.runtime_profile, "should have runtime profile")
    T.assert_equal(result2.runtime_profile.schema_version, "1.0",
        "schema_version should be 1.0")
    T.assert_equal(result2.runtime_profile.operations[1].id, "op-1",
        "operation should be preserved")
    T.assert_equal(#result2.runtime_profile.operations[1].actions, 1,
        "actions should be preserved")
    T.assert_equal(cp2:get_pipeline_state(), "success",
        "pipeline state should be success")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Pipeline with invalid profile → validation error → no compile
    -- =====================================================================
    print("Test 3: Pipeline with invalid profile → validation error → no compile")
    local bb3 = Blackboard:new()
    local eb3 = EventBus:new()
    local pm3 = ProfileManager:new()
    local mr3 = MigrationRegistry:new()
    local invalid_profile = make_profile({
        operations = {
            { id = "dup", name = "Op1" },
            { id = "dup", name = "Op2" },
        },
    })
    pm3:set_active_profile(invalid_profile)
    local cb3 = CompilerBridge:new(bb3, eb3, pm3)
    local cp3 = CompilePipeline:new(bb3, eb3, pm3, cb3, mr3)

    local result3 = cp3:run()
    T.assert_false(result3.success, "pipeline should fail for invalid profile")
    T.assert_nil(result3.runtime_profile, "should not have runtime profile")
    T.assert_not_nil(result3.diagnostics, "should have diagnostics")
    T.assert_true(#result3.diagnostics.errors > 0, "should have errors")
    T.assert_equal(cp3:get_pipeline_state(), "error",
        "pipeline state should be error")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Pipeline rejects concurrent runs
    -- =====================================================================
    print("Test 4: Pipeline rejects concurrent runs")
    local bb4 = Blackboard:new()
    local eb4 = EventBus:new()
    local pm4 = ProfileManager:new()
    local mr4 = MigrationRegistry:new()
    pm4:set_active_profile(make_profile())
    local cb4 = CompilerBridge:new(bb4, eb4, pm4)
    local cp4 = CompilePipeline:new(bb4, eb4, pm4, cb4, mr4)

    -- First run succeeds
    local result4a = cp4:run()
    T.assert_true(result4a.success, "first pipeline run should succeed")

    -- Second run while already running (but state is now "success")
    -- Need to simulate concurrent by setting state manually
    local cp4b = CompilePipeline:new(bb4, eb4, pm4, cb4, mr4)
    -- Directly inject running state
    cp4b._state = "running"

    local result4b = cp4b:run()
    T.assert_false(result4b.success, "should reject concurrent run")
    T.assert_true(#result4b.diagnostics.errors > 0, "should have error")
    local found_p1001 = false
    for _, e in ipairs(result4b.diagnostics.errors) do
        if e.code == "P-1001" then
            found_p1001 = true
            break
        end
    end
    T.assert_true(found_p1001, "should have P-1001 error for concurrent run")
    print("  PASS")

    -- =====================================================================
    -- Test 5: validate_only - just migration + validation
    -- =====================================================================
    print("Test 5: validate_only - just migration + validation")
    local bb5 = Blackboard:new()
    local eb5 = EventBus:new()
    local pm5 = ProfileManager:new()
    local mr5 = MigrationRegistry:new()
    pm5:set_active_profile(make_profile({
        name = "Validate Only",
        operations = {
            { id = "valid-op", name = "Valid Op" },
        },
    }))
    local cb5 = CompilerBridge:new(bb5, eb5, pm5)
    local cp5 = CompilePipeline:new(bb5, eb5, pm5, cb5, mr5)

    local result5 = cp5:validate_only()
    T.assert_not_nil(result5.diagnostics, "should have diagnostics")
    T.assert_equal(#result5.diagnostics.errors, 0,
        "should have no errors for valid profile")
    T.assert_equal(cp5:get_pipeline_state(), "idle",
        "pipeline state should remain idle after validate_only")
    print("  PASS")

    -- =====================================================================
    -- Test 6: validate_only with invalid profile shows errors
    -- =====================================================================
    print("Test 6: validate_only with invalid profile shows errors")
    local bb6 = Blackboard:new()
    local eb6 = EventBus:new()
    local pm6 = ProfileManager:new()
    local mr6 = MigrationRegistry:new()
    pm6:set_active_profile(make_profile({
        operations = {
            { id = "dup", name = "A" },
            { id = "dup", name = "B" },
        },
    }))
    local cb6 = CompilerBridge:new(bb6, eb6, pm6)
    local cp6 = CompilePipeline:new(bb6, eb6, pm6, cb6, mr6)

    local result6 = cp6:validate_only()
    T.assert_true(#result6.diagnostics.errors > 0,
        "should have errors for invalid profile")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Pipeline events are emitted
    -- =====================================================================
    print("Test 7: Pipeline events are emitted")
    local bb7 = Blackboard:new()
    local events_log7 = {}
    local eb7 = EventBus:new()
    eb7:subscribe("pipeline:started", function() table.insert(events_log7, "started") end)
    eb7:subscribe("pipeline:migration_complete", function() table.insert(events_log7, "migration_complete") end)
    eb7:subscribe("pipeline:validation_complete", function() table.insert(events_log7, "validation_complete") end)
    eb7:subscribe("pipeline:compile_complete", function() table.insert(events_log7, "compile_complete") end)
    eb7:subscribe("pipeline:completed", function() table.insert(events_log7, "completed") end)
    eb7:subscribe("pipeline:failed", function() table.insert(events_log7, "failed") end)

    local pm7 = ProfileManager:new()
    local mr7 = MigrationRegistry:new()
    pm7:set_active_profile(make_profile())
    local cb7 = CompilerBridge:new(bb7, eb7, pm7)
    local cp7 = CompilePipeline:new(bb7, eb7, pm7, cb7, mr7)

    cp7:run()

    T.assert_true(#events_log7 >= 4, "should have at least 4 events for successful pipeline")
    local has_started = false
    local has_migration = false
    local has_validation = false
    local has_compile = false
    local has_completed = false
    for _, evt in ipairs(events_log7) do
        if evt == "started" then has_started = true end
        if evt == "migration_complete" then has_migration = true end
        if evt == "validation_complete" then has_validation = true end
        if evt == "compile_complete" then has_compile = true end
        if evt == "completed" then has_completed = true end
    end
    T.assert_true(has_started, "should emit pipeline:started")
    T.assert_true(has_migration, "should emit pipeline:migration_complete")
    T.assert_true(has_validation, "should emit pipeline:validation_complete")
    T.assert_true(has_compile, "should emit pipeline:compile_complete")
    T.assert_true(has_completed, "should emit pipeline:completed")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Pipeline emits failed events on error
    -- =====================================================================
    print("Test 8: Pipeline emits failed events on error")
    local bb8 = Blackboard:new()
    local events_log8 = {}
    local eb8 = EventBus:new()
    eb8:subscribe("pipeline:started", function() table.insert(events_log8, "started") end)
    eb8:subscribe("pipeline:failed", function() table.insert(events_log8, "failed") end)

    local pm8 = ProfileManager:new()
    local mr8 = MigrationRegistry:new()
    pm8:set_active_profile(make_profile({
        operations = {
            { id = "x", name = "A" },
            { id = "x", name = "B" },
        },
    }))
    local cb8 = CompilerBridge:new(bb8, eb8, pm8)
    local cp8 = CompilePipeline:new(bb8, eb8, pm8, cb8, mr8)

    cp8:run()

    local has_started = false
    local has_failed = false
    for _, evt in ipairs(events_log8) do
        if evt == "started" then has_started = true end
        if evt == "failed" then has_failed = true end
    end
    T.assert_true(has_started, "should emit pipeline:started even on failure")
    T.assert_true(has_failed, "should emit pipeline:failed on error")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Toolbar compile event triggers pipeline
    -- =====================================================================
    print("Test 9: Toolbar compile event triggers pipeline")
    local bb9 = Blackboard:new()
    local events_log9 = {}
    local eb9 = EventBus:new()
    eb9:subscribe("pipeline:started", function() table.insert(events_log9, "started") end)
    eb9:subscribe("pipeline:completed", function() table.insert(events_log9, "completed") end)

    local pm9 = ProfileManager:new()
    local mr9 = MigrationRegistry:new()
    pm9:set_active_profile(make_profile({
        name = "Toolbar Test",
        operations = {
            { id = "toolbar-op", name = "Toolbar Op" },
        },
    }))
    local cb9 = CompilerBridge:new(bb9, eb9, pm9)
    -- Create pipeline which subscribes to toolbar:compile
    local cp9 = CompilePipeline:new(bb9, eb9, pm9, cb9, mr9)

    -- Emit the toolbar:compile event
    eb9:publish("toolbar:compile", {})

    -- Check events
    local has_started = false
    local has_completed = false
    for _, evt in ipairs(events_log9) do
        if evt == "started" then has_started = true end
        if evt == "completed" then has_completed = true end
    end
    T.assert_true(has_started, "toolbar:compile should trigger pipeline:started")
    T.assert_true(has_completed, "toolbar:compile should trigger pipeline:completed")

    -- Verify profile was swapped
    local active_profile = pm9:get_active_profile()
    T.assert_not_nil(active_profile, "should have active profile after pipeline")
    T.assert_equal(active_profile.profile_id, "Toolbar Test",
        "active profile should be the runtime profile")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Pipeline with no active profile
    -- =====================================================================
    print("Test 10: Pipeline with no active profile")
    local bb10 = Blackboard:new()
    local eb10 = EventBus:new()
    local pm10 = ProfileManager:new()
    local mr10 = MigrationRegistry:new()
    -- No profile set
    local cb10 = CompilerBridge:new(bb10, eb10, pm10)
    local cp10 = CompilePipeline:new(bb10, eb10, pm10, cb10, mr10)

    local result10 = cp10:run()
    T.assert_false(result10.success, "should fail with no profile")
    T.assert_equal(cp10:get_pipeline_state(), "error",
        "state should be error")
    T.assert_not_nil(result10.diagnostics, "should have diagnostics")
    print("  PASS")

    print("\n=== All CompilePipeline Tests PASSED ===")
end

return M
