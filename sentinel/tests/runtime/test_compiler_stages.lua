-- sentinel/tests/runtime/test_compiler_stages.lua
-- Tests for SENT-6.4, SENT-6.5, SENT-6.6, SENT-6.8: Compiler stages 4, 5, 6, 7

local T = require("tests/test_util")

local M = {}

-- Test Stage 4: Dependency Resolution -----------------------------------------

function M.test_stage4_topological_sort()
    print("Test: Stage4 topological_sort")

    local DependencyResolutionStage = require("runtime/stage_dependency_resolution")
    local DependencyGraph = require("modules/operation/dependency_graph")
    local stage = DependencyResolutionStage:new()

    -- Build dependency graph for proper operation tracking
    local profile = {
        operations = {
            { id = "northshire", name = "Northshire", priority = 100, dependencies = {} },
            { id = "goldshire", name = "Goldshire", priority = 90, dependencies = {
                { operation_id = "northshire", relationship = "Requires" }
            }},
            { id = "westbrook", name = "Westbrook", priority = 80, dependencies = {
                { operation_id = "goldshire", relationship = "SoftPrefers" }
            }},
        }
    }

    local ordered, diagnostics = stage:run(profile)

    T.assert_not_nil(ordered, "ordered should not be nil")
    T.assert_equal(#diagnostics.errors, 0, "should have no errors")
    T.assert_equal(ordered[1], "northshire", "northshire should come first (no deps)")
    T.assert_equal(ordered[2], "goldshire", "goldshire should come second")
    T.assert_equal(ordered[3], "westbrook", "westbrook should come third")

    print("  PASS")
end

function M.test_stage4_cycle_detection()
    print("Test: Stage4 cycle_detection")

    local DependencyResolutionStage = require("runtime/stage_dependency_resolution")
    local stage = DependencyResolutionStage:new()

    local profile = {
        operations = {
            { id = "op-a", name = "A", priority = 100, dependencies = {
                { operation_id = "op-b", relationship = "Requires" }
            }},
            { id = "op-b", name = "B", priority = 90, dependencies = {
                { operation_id = "op-a", relationship = "Requires" }
            }},
        }
    }

    local ordered, diagnostics = stage:run(profile)

    T.assert_true(ordered == nil, "ordered should be nil for cycle")
    T.assert_equal(#diagnostics.errors, 1, "should have one error")
    T.assert_equal(diagnostics.errors[1].code, "C-4001", "error code should be C-4001")
    T.assert_equal(diagnostics.errors[1].stage, "Operation Dependency Resolution", "error should have stage attribution")

    print("  PASS")
end

function M.test_stage4_excludes_with_conflict()
    print("Test: Stage4 excludes_with_conflict")

    local DependencyResolutionStage = require("runtime/stage_dependency_resolution")
    local stage = DependencyResolutionStage:new()

    local profile = {
        operations = {
            { id = "op-a", name = "A", priority = 100, dependencies = {
                { operation_id = "op-b", relationship = "ExcludesWith" }
            }},
            { id = "op-b", name = "B", priority = 90, dependencies = {} },
        }
    }

    local ordered, diagnostics = stage:run(profile)

    T.assert_true(ordered == nil, "ordered should be nil on ExcludesWith conflict")
    T.assert_equal(#diagnostics.errors, 1, "should have one error for conflict")
    T.assert_equal(diagnostics.errors[1].code, "C-4002", "error code should be C-4002")

    print("  PASS")
end

function M.test_stage4_excludes_with_no_conflict()
    print("Test: Stage4 excludes_with_no_conflict_when_races_differ")

    local DependencyResolutionStage = require("runtime/stage_dependency_resolution")
    local stage = DependencyResolutionStage:new()

    local profile = {
        operations = {
            { id = "op-a", name = "A", priority = 100,
                entry_conditions = { { type = "RaceIs", value = "Human" } },
                dependencies = {
                    { operation_id = "op-b", relationship = "ExcludesWith" }
                }
            },
            { id = "op-b", name = "B", priority = 90,
                entry_conditions = { { type = "RaceIs", value = "Dwarf" } },
                dependencies = {}
            },
        }
    }

    local ordered, diagnostics = stage:run(profile)

    T.assert_true(ordered ~= nil, "ordered should not be nil")
    T.assert_equal(#diagnostics.errors, 0, "should have no errors when races differ")

    print("  PASS")
end

-- Test Stage 5: Goal Coverage ------------------------------------------------

function M.test_stage5_required_goal_covered()
    print("Test: Stage5 required_goal_covered")

    local GoalCoverageStage = require("runtime/stage_goal_coverage")
    local stage = GoalCoverageStage:new()

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Northshire",
                goals = {
                    { type = "CompleteQuest", quest_id = 33, required = true },
                },
                actions = {
                    { type = "PickupQuest", quest_id = 33 },
                    { type = "TurnInQuest", quest_id = 33 },
                }
            }
        }
    }

    local diagnostics = stage:run(profile)

    T.assert_equal(#diagnostics.errors, 0, "no errors when quest is covered")

    print("  PASS")
end

function M.test_stage5_required_goal_uncovered()
    print("Test: Stage5 required_goal_uncovered")

    local GoalCoverageStage = require("runtime/stage_goal_coverage")
    local stage = GoalCoverageStage:new()

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Northshire",
                goals = {
                    { type = "CompleteQuest", quest_id = 99, required = true },
                },
                actions = {}
            }
        }
    }

    local diagnostics = stage:run(profile)

    T.assert_equal(#diagnostics.errors, 1, "one error when quest not covered")
    T.assert_equal(diagnostics.errors[1].code, "C-5001", "error code should be C-5001")
    T.assert_equal(diagnostics.errors[1].stage, "Goal Coverage Validation", "error should have stage attribution")
    T.assert_equal(diagnostics.errors[1].severity, "ERROR", "should have ERROR severity")

    print("  PASS")
end

function M.test_stage5_optional_goal_warning()
    print("Test: Stage5 optional_goal_warning")

    local GoalCoverageStage = require("runtime/stage_goal_coverage")
    local stage = GoalCoverageStage:new()

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Northshire",
                goals = {
                    { type = "CompleteQuest", quest_id = 99, required = false },
                },
                actions = {}
            }
        }
    }

    local diagnostics = stage:run(profile)

    T.assert_equal(#diagnostics.warnings, 1, "one warning for optional uncovered goal")
    T.assert_equal(diagnostics.warnings[1].code, "C-5001", "warning code should be C-5001")
    T.assert_equal(diagnostics.warnings[1].severity, "WARNING", "should have WARNING severity")

    print("  PASS")
end

function M.test_stage5_flight_path_covered()
    print("Test: Stage5 flight_path_covered")

    local GoalCoverageStage = require("runtime/stage_goal_coverage")
    local stage = GoalCoverageStage:new()

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Travel",
                goals = {
                    { type = "UnlockFlightPath", node_id = 100, required = true },
                },
                actions = {
                    { type = "FlightPath", from = { id = 50 }, to = { id = 100 } },
                }
            }
        }
    }

    local diagnostics = stage:run(profile)

    T.assert_equal(#diagnostics.errors, 0, "no errors when flight path is covered")

    print("  PASS")
end

function M.test_stage5_flight_path_uncovered()
    print("Test: Stage5 flight_path_uncovered")

    local GoalCoverageStage = require("runtime/stage_goal_coverage")
    local stage = GoalCoverageStage:new()

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Travel",
                goals = {
                    { type = "UnlockFlightPath", node_id = 100, required = true },
                },
                actions = {}
            }
        }
    }

    local diagnostics = stage:run(profile)

    T.assert_equal(#diagnostics.errors, 1, "one error when flight path not covered")
    T.assert_equal(diagnostics.errors[1].code, "C-5003", "error code should be C-5003")

    print("  PASS")
end

-- Test Stage 6: Optimization -------------------------------------------------

function M.test_stage6_vendor_repair_merge()
    print("Test: Stage6 vendor_repair_merge")

    local OptimizationStage = require("runtime/stage_optimization")
    local stage = OptimizationStage:new()

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "VendorOp",
                actions = {
                    { type = "Vendor", id = "a-1", name = "SellGreys", params = { repair = false } },
                    { type = "Repair", id = "a-2", name = "RepairGear", params = {} },
                }
            }
        }
    }

    local result = stage:run(profile, { "op-1" })

    T.assert_equal(#result.profile.operations[1].actions, 1, "should be merged to 1 action")
    T.assert_equal(#result.optimizations_applied, 1, "should have one optimization log")
    T.assert_true(result.profile.operations[1].actions[1].params.repair, "merged action should have repair=true")

    print("  PASS")
end

function M.test_stage6_adjacency_vendor_goto_merge()
    print("Test: Stage6 adjacency_vendor_goto_merge")

    local OptimizationStage = require("runtime/stage_optimization")
    local stage = OptimizationStage:new()

    local profile = {
        operations = {
            {
                id = "northshire",
                name = "Northshire",
                actions = {
                    { type = "Vendor", id = "a-1", name = "Vendor", params = {
                        vendor = {
                            npc = { position = { x = 0, y = 0, z = 0 } }
                        }
                    }},
                }
            },
            {
                id = "goldshire",
                name = "Goldshire",
                actions = {
                    { type = "GoToAction", id = "a-2", name = "GoToStart", params = {
                        destination = { x = 30, y = 40, z = 0 }
                    }},
                    { type = "TalkToNpc", id = "a-3", name = "Talk", params = {} },
                }
            }
        }
    }

    -- Distance between (0,0) and (30,40) = 50.0, exactly at threshold
    local result = stage:run(profile, { "northshire", "goldshire" })

    -- GoTo should be dropped since distance <= 50
    T.assert_equal(#result.profile.operations[2].actions, 1, "GoTo should be dropped")
    T.assert_equal(result.optimizations_applied[1].description:find("redundant") ~= nil, true, "should log redundant GoTo")

    print("  PASS")
end

function M.test_stage6_distant_goto_preserved()
    print("Test: Stage6 distant_goto_preserved")

    local OptimizationStage = require("runtime/stage_optimization")
    local stage = OptimizationStage:new()

    local profile = {
        operations = {
            {
                id = "northshire",
                name = "Northshire",
                actions = {
                    { type = "Vendor", id = "a-1", name = "Vendor", params = {
                        vendor = {
                            npc = { position = { x = 0, y = 0, z = 0 } }
                        }
                    }},
                }
            },
            {
                id = "goldshire",
                name = "Goldshire",
                actions = {
                    { type = "GoToAction", id = "a-2", name = "GoToStart", params = {
                        destination = { x = 500, y = 800, z = 0 }
                    }},
                    { type = "TalkToNpc", id = "a-3", name = "Talk", params = {} },
                }
            }
        }
    }

    -- Distance between (0,0) and (500,800) = ~943 yards, far above threshold
    local result = stage:run(profile, { "northshire", "goldshire" })

    T.assert_equal(#result.profile.operations[2].actions, 2, "GoTo should be preserved (distance > threshold)")

    print("  PASS")
end

function M.test_stage6_error_code_constants()
    print("Test: Stage6 error_code_constants")

    local OptimizationStage = require("runtime/stage_optimization")
    local Diagnostics = require("runtime/diagnostics")

    T.assert_equal(OptimizationStage.ErrorCodes.OptimizationRejected, "C-6001", "should have C-6001 error code")
    T.assert_equal(OptimizationStage.MERGE_DISTANCE_THRESHOLD, 50.0, "should have 50 yard threshold")
    T.assert_equal(Diagnostics.Severity.ERROR, "ERROR", "severity ERROR should be defined")
    T.assert_equal(Diagnostics.Severity.WARNING, "WARNING", "severity WARNING should be defined")
    T.assert_equal(Diagnostics.Severity.INFO, "INFO", "severity INFO should be defined")

    print("  PASS")
end

-- Test Stage 7: Lowering ------------------------------------------------------

function M.test_stage7_lower_to_runtime_profile()
    print("Test: Stage7 lower_to_runtime_profile")

    local LoweringStage = require("runtime/stage_lowering")
    local RuntimeTypes = require("runtime/runtime_types")
    local stage = LoweringStage:new()

    local optimized_profile = {
        id = "test-profile-1",
        name = "TestProfile",
        operations = {
            {
                id = "op-1",
                name = "Northshire",
                entry_conditions = {},
                goals = {},
                actions = {
                    { id = "act-1", action_type = "PickupQuest", params = { quest_id = 33 } },
                    { id = "act-2", action_type = "TurnInQuest", params = { quest_id = 33 } },
                }
            }
        }
    }

    local result = stage:run(optimized_profile, "test-profile-1")

    T.assert_true(result.runtime_profile ~= nil, "should produce runtime profile")
    T.assert_equal(#result.diagnostics.errors, 0, "should have no errors")
    T.assert_equal(result.runtime_profile.profile_id, "test-profile-1", "profile_id should be preserved")
    T.assert_equal(#result.runtime_profile.operations, 1, "should have one operation")
    T.assert_equal(result.runtime_profile.operations[1].actions[1].id, "act-1", "first action should be preserved")

    print("  PASS")
end

function M.test_stage7_runtime_action_generated_from()
    print("Test: Stage7 runtime_action_generated_from")

    local LoweringStage = require("runtime/stage_lowering")
    local stage = LoweringStage:new()

    local optimized_profile = {
        id = "test-profile-2",
        operations = {
            {
                id = "op-1",
                name = "VendorOp",
                actions = {
                    { id = "act-1", action_type = "Vendor", generated_from = "vendor-stop-blueprint" },
                }
            }
        }
    }

    local result = stage:run(optimized_profile, "test-profile-2")

    T.assert_true(result.runtime_profile ~= nil, "should produce runtime profile")
    T.assert_equal(result.runtime_profile.operations[1].actions[1].generated_from, "vendor-stop-blueprint", "generated_from should be preserved")

    print("  PASS")
end

function M.test_stage7_runtime_profile_validation()
    print("Test: Stage7 runtime_profile_validation")

    local RuntimeTypes = require("runtime/runtime_types")

    -- Test valid profile
    local valid_profile = {
        profile_id = "test",
        operations = {
            { id = "op-1", name = "TestOp", actions = {} },
        }
    }
    local validation = RuntimeTypes.validate_runtime_profile(valid_profile)
    T.assert_equal(#validation.errors, 0, "valid profile should have no errors")

    -- Test missing profile_id
    local invalid_profile = {
        operations = {
            { id = "op-1", name = "TestOp", actions = {} },
        }
    }
    validation = RuntimeTypes.validate_runtime_profile(invalid_profile)
    T.assert_equal(#validation.errors, 1, "missing profile_id should be error")
    T.assert_equal(validation.errors[1].code, "C-7001", "error code should be C-7001")

    -- Test missing operations
    invalid_profile = { profile_id = "test" }
    validation = RuntimeTypes.validate_runtime_profile(invalid_profile)
    T.assert_equal(#validation.errors, 1, "missing operations should be error")
    T.assert_equal(validation.errors[1].code, "C-7002", "error code should be C-7002")

    print("  PASS")
end

function M.test_stage7_c7xxx_error_codes()
    print("Test: Stage7 C-7xxx error codes")

    local LoweringStage = require("runtime/stage_lowering")

    T.assert_equal(LoweringStage.ErrorCodes.MissingProfileId, "C-7001", "should have C-7001 error code")
    T.assert_equal(LoweringStage.ErrorCodes.MissingOperations, "C-7002", "should have C-7002 error code")
    T.assert_equal(LoweringStage.ErrorCodes.InvalidOperation, "C-7003", "should have C-7003 error code")
    T.assert_equal(LoweringStage.ErrorCodes.InvalidAction, "C-7004", "should have C-7004 error code")

    print("  PASS")
end

-- Test Stage 7.10: Profile Caching (SENT-6.10) ----------------------------------------

function M.test_stage7_profile_cache_get_put()
    print("Test: Stage7 profile_cache_get_put")

    local LoweringStage = require("runtime/stage_lowering")
    
    LoweringStage.clear_cache()
    
    local profile = {
        profile_id = "cache-test-1",
        operations = {
            { id = "op-1", name = "TestOp", actions = { { id = "act-1", action_type = "PickupQuest" } } }
        }
    }
    
    T.assert_false(LoweringStage.has_cached_profile("cache-test-1"), "should not have cached profile initially")
    
    LoweringStage._profile_cache:put("cache-test-1", profile)
    
    T.assert_true(LoweringStage.has_cached_profile("cache-test-1"), "should have cached profile after put")
    
    local cached = LoweringStage.get_cached_profile("cache-test-1")
    T.assert_true(cached ~= nil, "should retrieve cached profile")
    T.assert_equal(cached.profile_id, "cache-test-1", "cached profile id should match")

    print("  PASS")
end

function M.test_stage7_lru_eviction()
    print("Test: Stage7 lru_eviction")

    local LoweringStage = require("runtime/stage_lowering")
    LoweringStage.clear_cache()
    
    for i = 1, 51 do
        local profile = {
            profile_id = "lru-test-" .. i,
            operations = { { id = "op-" .. i, name = "Op" .. i, actions = {} } }
        }
        LoweringStage._profile_cache:put("lru-test-" .. i, profile)
    end
    
    local stats = LoweringStage.get_cache_stats()
    T.assert_equal(stats.size, 50, "cache size should be capped at 50")
    
    T.assert_false(LoweringStage.has_cached_profile("lru-test-1"), "oldest entry should be evicted")
    T.assert_true(LoweringStage.has_cached_profile("lru-test-51"), "newest entry should be present")

    print("  PASS")
end

function M.test_stage7_cache_stats()
    print("Test: Stage7 cache_stats")

    local LoweringStage = require("runtime/stage_lowering")
    LoweringStage.clear_cache()
    
    local stats = LoweringStage.get_cache_stats()
    T.assert_equal(stats.size, 0, "empty cache should have size 0")
    T.assert_equal(stats.max_size, 50, "max cache size should be 50")

    for i = 1, 5 do
        LoweringStage._profile_cache:put("stats-test-" .. i, { profile_id = "stats-test-" .. i, operations = {} })
    end
    
    stats = LoweringStage.get_cache_stats()
    T.assert_equal(stats.size, 5, "cache should have 5 entries")

    LoweringStage.clear_cache()
    stats = LoweringStage.get_cache_stats()
    T.assert_equal(stats.size, 0, "cache should be empty after clear")

    print("  PASS")
end

-- Test Stage 7.11: Full Pipeline Integration (SENT-6.11) --------------------------------

function M.test_stage7_full_pipeline_validation()
    print("Test: Stage7 full_pipeline_validation")

    local CompilerBridge = require("runtime/compiler_bridge")
    local RuntimeTypes = require("runtime/runtime_types")

    local valid_runtime_profile = {
        profile_id = "test-pipeline-1",
        schema_version = "1.0",
        compiler_version = "0.1.0",
        operations = {
            { id = "op-1", name = "TestOp", actions = { { id = "act-1", action_type = "PickupQuest" } } },
        }
    }

    local validation = CompilerBridge:validate_runtime_profile(valid_runtime_profile)
    T.assert_equal(#validation.errors, 0, "valid profile should have no validation errors")

    local invalid_runtime_profile = {
        profile_id = "test-pipeline-2",
        operations = {
            { id = "op-1", name = "TestOp" }
        }
    }

    validation = CompilerBridge:validate_runtime_profile(invalid_runtime_profile)
    T.assert_true(#validation.errors > 0, "profile missing actions should have validation errors")

    print("  PASS")
end

function M.test_stage7_full_compiler_pipeline()
    print("Test: Stage7 full_compiler_pipeline")

    local CompilerBridge = require("runtime/compiler_bridge")
    local Blackboard = require("core/blackboard")
    local EventBus = require("core/event_bus")
    local ProfileManager = require("runtime/profile_manager")
    local LoweringStage = require("runtime/stage_lowering")

    LoweringStage.clear_cache()

    local bb = Blackboard:new()
    local eb = EventBus:new()
    local pm = ProfileManager:new()
    
    local profile = {
        name = "Pipeline Test Profile",
        operations = {
            {
                id = "op-1",
                name = "Northshire",
                action_type = "test",
                goals = {},
                actions = {
                    { id = "act-1", action_type = "PickupQuest", params = { quest_id = 33 } },
                    { id = "act-2", action_type = "TurnInQuest", params = { quest_id = 33 } },
                }
            }
        }
    }
    pm:set_active_profile(profile)
    
    local cb = CompilerBridge:new(bb, eb, pm)
    
    local runtime_profile = nil
    cb:compile(function(err, rp)
        runtime_profile = rp
    end)

    T.assert_true(runtime_profile ~= nil, "should produce runtime profile from full pipeline")
    T.assert_equal(runtime_profile.schema_version, "1.0", "schema_version should be 1.0")
    T.assert_equal(runtime_profile.profile_id, "Pipeline Test Profile", "profile_id should match")
    T.assert_equal(#runtime_profile.operations, 1, "should have 1 operation")
    T.assert_equal(#runtime_profile.operations[1].actions, 2, "operation should have 2 actions")

    print("  PASS")
end

function M.test_stage7_cache_hit_on_recompile()
    print("Test: Stage7 cache_hit_on_recompile")

    local CompilerBridge = require("runtime/compiler_bridge")
    local Blackboard = require("core/blackboard")
    local EventBus = require("core/event_bus")
    local ProfileManager = require("runtime/profile_manager")
    local LoweringStage = require("runtime/stage_lowering")

    LoweringStage.clear_cache()

    local bb = Blackboard:new()
    local eb = EventBus:new()
    local pm = ProfileManager:new()
    
    local profile = {
        name = "Cache Hit Test",
        operations = {
            { id = "op-1", name = "TestOp", actions = { { id = "act-1", action_type = "PickupQuest" } } }
        }
    }
    pm:set_active_profile(profile)
    
    local cb = CompilerBridge:new(bb, eb, pm)
    
    local first_result = nil
    cb:compile(function(err, rp) first_result = rp end)
    T.assert_true(first_result ~= nil, "first compile should succeed")

    local second_result = nil
    cb:compile(function(err, rp) second_result = rp end)
    T.assert_true(second_result ~= nil, "second compile should succeed")

    print("  PASS")
end

-- Test Diagnostics ------------------------------------------------------------

function M.test_diagnostics_severity_levels()
    print("Test: Diagnostics severity levels")

    local Diagnostics = require("runtime/diagnostics")

    T.assert_equal(Diagnostics.Severity.ERROR, "ERROR")
    T.assert_equal(Diagnostics.Severity.WARNING, "WARNING")
    T.assert_equal(Diagnostics.Severity.INFO, "INFO")

    local err = Diagnostics.error("C-7001", Diagnostics.Stage.Lowering, "test error")
    T.assert_equal(err.severity, "ERROR", "error should have ERROR severity")

    local warn = Diagnostics.warning("C-7002", Diagnostics.Stage.Lowering, "test warning")
    T.assert_equal(warn.severity, "WARNING", "warning should have WARNING severity")

    local info = Diagnostics.info("C-7003", Diagnostics.Stage.Lowering, "test info")
    T.assert_equal(info.severity, "INFO", "info should have INFO severity")

    print("  PASS")
end

function M.test_diagnostics_stage_attribution()
    print("Test: Diagnostics stage attribution")

    local Diagnostics = require("runtime/diagnostics")

    T.assert_equal(Diagnostics.Stage.StructuralValidation, "Structural Validation")
    T.assert_equal(Diagnostics.Stage.DependencyResolution, "Operation Dependency Resolution")
    T.assert_equal(Diagnostics.Stage.GoalCoverage, "Goal Coverage Validation")
    T.assert_equal(Diagnostics.Stage.Optimization, "Cross-Operation Optimization")
    T.assert_equal(Diagnostics.Stage.Lowering, "Lowering")

    print("  PASS")
end

function M.run()
    print("=== Compiler Stages 4-7 Tests ===")
    M.test_stage4_topological_sort()
    M.test_stage4_cycle_detection()
    M.test_stage4_excludes_with_conflict()
    M.test_stage4_excludes_with_no_conflict()
    M.test_stage5_required_goal_covered()
    M.test_stage5_required_goal_uncovered()
    M.test_stage5_optional_goal_warning()
    M.test_stage5_flight_path_covered()
    M.test_stage5_flight_path_uncovered()
    M.test_stage6_vendor_repair_merge()
    M.test_stage6_adjacency_vendor_goto_merge()
    M.test_stage6_distant_goto_preserved()
    M.test_stage6_error_code_constants()
    M.test_stage7_lower_to_runtime_profile()
    M.test_stage7_runtime_action_generated_from()
    M.test_stage7_runtime_profile_validation()
    M.test_stage7_c7xxx_error_codes()
    M.test_stage7_profile_cache_get_put()
    M.test_stage7_lru_eviction()
    M.test_stage7_cache_stats()
    M.test_stage7_full_pipeline_validation()
    M.test_stage7_full_compiler_pipeline()
    M.test_stage7_cache_hit_on_recompile()
    M.test_diagnostics_severity_levels()
    M.test_diagnostics_stage_attribution()
    print("\n=== All Compiler Stages Tests PASSED ===")
end

return M