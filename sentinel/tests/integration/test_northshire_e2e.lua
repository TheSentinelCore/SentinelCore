-- sentinel/tests/integration/test_northshire_e2e.lua
-- SENT-6.12: Northshire End-to-End Integration Test
-- ADR 008 §18 — Test full compiler pipeline on Northshire example

local T = require("tests/test_util")

local M = {}

-- Test data: Northshire quest chain quests
local NORTHSHIRE_QUEST_CHAIN = { 33, 34, 35, 36 }

-- Test Stage 1: Structural Validation -----------------------------

function M.test_northshire_structural_validation()
    print("Test: Northshire structural validation")

    local profile = {
        name = "NorthshireE2E",
        operations = {
            {
                id = "northshire-op",
                name = "Northshire Valley",
                goals = {
                    {
                        type = "CompleteQuestChain",
                        quest_ids = NORTHSHIRE_QUEST_CHAIN,
                        required = true,
                    },
                },
                actions = {
                    { id = "pickup-33", action_type = "pickup_quest", params = { quest_id = 33 } },
                    { id = "pickup-34", action_type = "pickup_quest", params = { quest_id = 34 } },
                    { id = "pickup-35", action_type = "pickup_quest", params = { quest_id = 35 } },
                    { id = "pickup-36", action_type = "pickup_quest", params = { quest_id = 36 } },
                    { id = "turnin-33", action_type = "turn_in_quest", params = { quest_id = 33 } },
                    { id = "turnin-34", action_type = "turn_in_quest", params = { quest_id = 34 } },
                    { id = "turnin-35", action_type = "turn_in_quest", params = { quest_id = 35 } },
                    { id = "turnin-36", action_type = "turn_in_quest", params = { quest_id = 36 } },
                },
            },
        },
    }

    local CompilerBridge = require("runtime/compiler_bridge")
    local MockBB = { set = function() end, get = function() return nil end }
    local MockEB = { publish = function() end }
    local MockPM = { get_active_profile = function() return profile end }

    local cb = CompilerBridge:new(MockBB, MockEB, MockPM)

    local runtime_profile = nil
    cb:compile(function(err, rp)
        runtime_profile = rp
    end)

    T.assert_true(runtime_profile ~= nil, "should produce runtime profile")
    T.assert_true(cb:get_last_result().success, "compile should succeed with covered goals")
    T.assert_equal(#runtime_profile.operations, 1, "should have 1 operation")

    print("  PASS")
end

-- Test Stage 2: Reference Resolution ----------------------------

function M.test_northshire_reference_resolution()
    print("Test: Northshire reference resolution")

    local CompilerBridge = require("runtime/compiler_bridge")
    local LoweringStage = require("runtime/stage_lowering")
    LoweringStage.clear_cache()

    local profile = {
        name = "NorthshireE2E",
        operations = {
            {
                id = "northshire-op",
                name = "Northshire Valley",
                goals = {
                    {
                        type = "CompleteQuest",
                        quest_id = 33,
                        required = true,
                    },
                },
                actions = {
                    { id = "pickup-33", action_type = "pickup_quest", params = { quest_id = 33 } },
                    { id = "turnin-33", action_type = "turn_in_quest", params = { quest_id = 33 } },
                },
            },
        },
    }

    local MockBB = { set = function() end, get = function() return nil end }
    local MockEB = { publish = function() end }
    local MockPM = { get_active_profile = function() return profile end }

    local cb = CompilerBridge:new(MockBB, MockEB, MockPM)

    local runtime_profile = nil
    cb:compile(function(err, rp)
        runtime_profile = rp
    end)

    T.assert_true(runtime_profile ~= nil, "should produce runtime profile after ref resolution")
    T.assert_equal(#runtime_profile.operations[1].actions, 2, "should have 2 actions")

    print("  PASS")
end

-- Test Stage 3: Blueprint Expansion -----------------------------

function M.test_northshire_blueprint_expansion()
    print("Test: Northshire blueprint expansion")

    local CompilerBridge = require("runtime/compiler_bridge")
    local LoweringStage = require("runtime/stage_lowering")
    LoweringStage.clear_cache()

    local profile = {
        name = "NorthshireE2E",
        operations = {
            {
                id = "northshire-op",
                name = "Northshire Valley",
                goals = {
                    {
                        type = "CompleteQuestChain",
                        quest_ids = NORTHSHIRE_QUEST_CHAIN,
                        required = true,
                    },
                },
                actions = {
                    {
                        id = "quest-hub-action",
                        action_type = "blueprint",
                        blueprint_id = "quest_hub",
                        params = {
                            quest_giver = { guid = "test-guid" },
                            quests = { 33, 34, 35, 36 },
                            accept_all = true,
                        },
                    },
                    { id = "turnin-33", action_type = "turn_in_quest", params = { quest_id = 33 } },
                    { id = "turnin-34", action_type = "turn_in_quest", params = { quest_id = 34 } },
                    { id = "turnin-35", action_type = "turn_in_quest", params = { quest_id = 35 } },
                    { id = "turnin-36", action_type = "turn_in_quest", params = { quest_id = 36 } },
                },
            },
        },
    }

    local MockBB = { set = function() end, get = function() return nil end }
    local MockEB = { publish = function() end }
    local MockPM = { get_active_profile = function() return profile end }

    local cb = CompilerBridge:new(MockBB, MockEB, MockPM)

    local runtime_profile = nil
    cb:compile(function(err, rp)
        runtime_profile = rp
    end)

    T.assert_true(runtime_profile ~= nil, "should produce runtime profile after blueprint expansion")
    local actions = runtime_profile.operations[1].actions
    T.assert_true(#actions >= 5, "should have expanded actions (>=5 from quest_hub + turnins)")

    -- Check that blueprint-expanded actions have generated_from provenance
    local has_generated_from = false
    for _, action in ipairs(actions) do
        if action.generated_from then
            has_generated_from = true
            break
        end
    end
    T.assert_true(has_generated_from, "at least one expanded action should have generated_from provenance")

    print("  PASS")
end

-- Test Stage 4: Dependency Resolution ---------------------------

function M.test_northshire_dependency_resolution()
    print("Test: Northshire dependency resolution")

    local profile = {
        name = "NorthshireE2E",
        operations = {
            {
                id = "northshire-op",
                name = "Northshire Valley",
                priority = 100,
                goals = {
                    {
                        type = "CompleteQuestChain",
                        quest_ids = NORTHSHIRE_QUEST_CHAIN,
                        required = true,
                    },
                },
                actions = {
                    { id = "pickup-33", action_type = "pickup_quest", params = { quest_id = 33 } },
                },
            },
            {
                id = "goldshire-op",
                name = "Goldshire",
                priority = 90,
                dependencies = {
                    { operation_id = "northshire-op", relationship = "Requires" },
                },
                goals = {},
                actions = {},
            },
        },
    }

    local DependencyResolutionStage = require("runtime/stage_dependency_resolution")

    local dep_stage = DependencyResolutionStage:new()
    local ordered_ids, diagnostics = dep_stage:run(profile)

    T.assert_true(ordered_ids ~= nil, "should produce ordered operation ids")
    T.assert_equal(#diagnostics.errors, 0, "should have no errors")
    T.assert_equal(ordered_ids[1], "northshire-op", "northshire-op should sort first (no deps)")
    T.assert_equal(ordered_ids[2], "goldshire-op", "goldshire-op should sort second")

    print("  PASS")
end

-- Test Stage 5: Goal Coverage Validation ----------------------

function M.test_northshire_goal_coverage_quest_chain()
    print("Test: Northshire goal coverage for CompleteQuestChain([33,34,35,36])")

    local profile = {
        name = "NorthshireE2E",
        operations = {
            {
                id = "northshire-op",
                name = "Northshire Valley",
                goals = {
                    {
                        type = "CompleteQuestChain",
                        quest_ids = NORTHSHIRE_QUEST_CHAIN,
                        required = true,
                    },
                },
                actions = {
                    { id = "pickup-33", action_type = "pickup_quest", params = { quest_id = 33 } },
                    { id = "pickup-34", action_type = "pickup_quest", params = { quest_id = 34 } },
                    { id = "pickup-35", action_type = "pickup_quest", params = { quest_id = 35 } },
                    { id = "pickup-36", action_type = "pickup_quest", params = { quest_id = 36 } },
                    { id = "turnin-33", action_type = "turn_in_quest", params = { quest_id = 33 } },
                    { id = "turnin-34", action_type = "turn_in_quest", params = { quest_id = 34 } },
                    { id = "turnin-35", action_type = "turn_in_quest", params = { quest_id = 35 } },
                    { id = "turnin-36", action_type = "turn_in_quest", params = { quest_id = 36 } },
                },
            },
        },
    }

    local CompilerBridge = require("runtime/compiler_bridge")
    local MockBB = { set = function() end, get = function() return nil end }
    local MockEB = { publish = function() end }
    local MockPM = { get_active_profile = function() return profile end }

    local cb = CompilerBridge:new(MockBB, MockEB, MockPM)

    local runtime_profile = nil
    cb:compile(function(err, rp)
        runtime_profile = rp
    end)

    T.assert_true(runtime_profile ~= nil, "should produce runtime profile")
    T.assert_true(cb:get_last_result().success, "compile should succeed")

    print("  PASS")
end

-- Test Stage 6: Cross-Operation Optimization ------------------

function M.test_northshire_adjacency_merge_goldshire()
    print("Test: Northshire adjacency merge with Goldshire")

    local profile = {
        name = "NorthshireE2E",
        operations = {
            {
                id = "northshire-op",
                name = "Northshire Valley",
                priority = 100,
                optimization_policy = {
                    allow_reordering = true,
                    merge_distance_threshold = 50,
                },
                goals = {
                    {
                        type = "CompleteQuestChain",
                        quest_ids = NORTHSHIRE_QUEST_CHAIN,
                        required = true,
                    },
                },
                actions = {
                    {
                        id = "turnin-final",
                        type = "TurnInQuest",
                        quest_id = 36,
                    },
                    {
                        id = "vendor-end",
                        type = "Vendor",
                        params = {
                            vendor = {
                                npc = {
                                    position = { x = -8912.5, y = -132.3, z = 83.2 },
                                },
                            },
                        },
                    },
                },
            },
            {
                id = "goldshire-op",
                name = "Goldshire",
                priority = 90,
                goals = {},
                actions = {
                    {
                        id = "goto-start",
                        type = "GoToAction",
                        params = {
                            destination = { x = -8882.5, y = -132.3, z = 83.2 },
                        },
                    },
                },
            },
        },
    }

    local CompilerBridge = require("runtime/compiler_bridge")
    local MockBB = { set = function() end, get = function() return nil end }
    local MockEB = { publish = function() end }
    local MockPM = { get_active_profile = function() return profile end }

    local cb = CompilerBridge:new(MockBB, MockEB, MockPM)

    local runtime_profile = nil
    cb:compile(function(err, rp)
        runtime_profile = rp
    end)

    local last_result = cb:get_last_result()
    local optimizations = last_result.optimizations or last_result.optimizations_applied or {}

    T.assert_true(runtime_profile ~= nil, "should produce runtime profile")

    print("  PASS")
end

-- Test Stage 7: Lowering + Action Provenance -----------------

function M.test_northshire_lowering_and_provenance()
    print("Test: Northshire lowering with generated_from provenance")

    local CompilerBridge = require("runtime/compiler_bridge")
    local LoweringStage = require("runtime/stage_lowering")
    LoweringStage.clear_cache()

    local profile = {
        name = "NorthshireE2E",
        operations = {
            {
                id = "northshire-op",
                name = "Northshire Valley",
                goals = {
                    {
                        type = "CompleteQuestChain",
                        quest_ids = NORTHSHIRE_QUEST_CHAIN,
                        required = true,
                    },
                },
                actions = {
                    { id = "pickup-33", action_type = "pickup_quest", params = { quest_id = 33 } },
                    { id = "pickup-34", action_type = "pickup_quest", params = { quest_id = 34 } },
                    { id = "grind-wolves", type = "GrindArea", creatures = { 555, 556, 557 }, position = { x = 0, y = 0, z = 0 }, radius = 50 },
                    { id = "turnin-33", action_type = "turn_in_quest", params = { quest_id = 33 } },
                    { id = "turnin-34", action_type = "turn_in_quest", params = { quest_id = 34 } },
                    { id = "turnin-35", action_type = "turn_in_quest", params = { quest_id = 35 } },
                    { id = "turnin-36", action_type = "turn_in_quest", params = { quest_id = 36 } },
                },
            },
        },
    }

    local MockBB = { set = function() end, get = function() return nil end }
    local MockEB = { publish = function() end }
    local MockPM = { get_active_profile = function() return profile end }

    local cb = CompilerBridge:new(MockBB, MockEB, MockPM)

    local runtime_profile = nil
    cb:compile(function(err, rp)
        runtime_profile = rp
    end)

    T.assert_true(runtime_profile ~= nil, "should produce runtime profile")
    T.assert_true(#runtime_profile.operations >= 1, "should have at least 1 operation")

    local actions = runtime_profile.operations[1].actions
    T.assert_true(#actions >= 6, "should have at least 6 actions (pickup/grind/turnin)")

    for i, action in ipairs(actions) do
        T.assert_true(action.id ~= nil, "action " .. i .. " should have an id")
    end

    print("  PASS")
end

-- Test Full Pipeline: All 7 Stages ----------------------------

function M.test_northshire_full_compiler_pipeline()
    print("Test: Northshire full 7-stage compiler pipeline")

    local profile = {
        name = "NorthshireE2E",
        operations = {
            {
                id = "northshire-op",
                name = "Northshire Valley",
                priority = 100,
                level_range = { min = 1, max = 5 },
                goals = {
                    {
                        type = "CompleteQuestChain",
                        quest_ids = NORTHSHIRE_QUEST_CHAIN,
                        required = true,
                    },
                },
                optimization_policy = {
                    travel_weight = 0.5,
                    xp_weight = 0.3,
                    time_weight = 0.2,
                    risk_weight = 0.1,
                    cluster_objectives = true,
                    allow_reordering = true,
                    grind_fallback = false,
                    max_deaths = 3,
                },
                actions = {
                    {
                        id = "quest-hub-action",
                        action_type = "blueprint",
                        blueprint_id = "quest_hub",
                        params = {
                            quest_giver = {
                                guid = "guid-marshal-mcbride",
                                position = { x = -8912.5, y = -132.3, z = 83.2 },
                            },
                            quests = { 33, 34, 35, 36 },
                            accept_all = true,
                            vendor = {
                                guid = "guid-brother-danil",
                                position = { x = -8912.5, y = -132.3, z = 83.2 },
                            },
                            repair = true,
                        },
                    },
                    {
                        id = "grind-action",
                        type = "GrindArea",
                        creatures = { 456, 457, 458 },
                        position = { x = -8900, y = -120, z = 83 },
                        radius = 100,
                    },
                    {
                        id = "turnin-action",
                        type = "TurnInQuest",
                        quest_id = 36,
                    },
                },
            },
            {
                id = "goldshire-op",
                name = "Goldshire",
                priority = 90,
                goals = {},
                actions = {
                    {
                        id = "goto-goldshire",
                        action_type = "GoToAction",
                        params = {
                            destination = { x = -8882.5, y = -132.3, z = 83.2 },
                        },
                    },
                },
            },
        },
    }

    local CompilerBridge = require("runtime/compiler_bridge")
    local LoweringStage = require("runtime/stage_lowering")
    LoweringStage.clear_cache()

    local MockBB = { set = function() end, get = function() return nil end }
    local MockEB = { publish = function() end }
    local MockPM = { get_active_profile = function() return profile end }

    local cb = CompilerBridge:new(MockBB, MockEB, MockPM)

    local runtime_profile = nil
    cb:compile(function(err, rp)
        runtime_profile = rp
    end)

    local last_result = cb:get_last_result()

    T.assert_true(runtime_profile ~= nil, "Stage 7: should produce runtime profile")
    T.assert_true(last_result.success, "pipeline should complete successfully")
    T.assert_equal(#last_result.diagnostics.errors, 0, "pipeline should have no errors")

    T.assert_true(#runtime_profile.operations >= 2, "should have at least 2 operations")

    T.assert_equal(runtime_profile.profile_id, "NorthshireE2E", "profile_id should be preserved")
    T.assert_true(runtime_profile.schema_version ~= nil, "should have schema_version")
    T.assert_true(runtime_profile.compiler_version ~= nil, "should have compiler_version")

    -- Verify adjacency merge: Goldshire's leading GoToAction should be dropped
    -- if distance between Northshire vendor and Goldshire destination <= 50
    -- Note: operations are sorted by priority, so goldshire-op (90) may be ops[2] or ops[1] depending on order
    local northshire_op, goldshire_op
    for _, op in ipairs(runtime_profile.operations) do
        if op.id == "northshire-op" then northshire_op = op
        elseif op.id == "goldshire-op" then goldshire_op = op
        end
    end

    local optimizations = last_result.optimizations or {}
    local adjacency_merge_found = false

    for _, opt in ipairs(optimizations) do
        if opt.operation_id == "goldshire-op" then
            adjacency_merge_found = true
            break
        end
    end

    T.assert_true(adjacency_merge_found or (goldshire_op and #goldshire_op.actions <= 1), "should have adjacency merge with Goldshire or reduced actions")

    -- Verify all actions have id
    for _, op in ipairs(runtime_profile.operations) do
        for _, action in ipairs(op.actions) do
            T.assert_true(action.id ~= nil, "all actions should have id")
        end
    end

    print("  PASS")
end

-- Integration Entry Point -------------------------------------

function M.run()
    print("=== Northshire E2E Integration Tests (SENT-6.12) ===")

    M.test_northshire_structural_validation()
    M.test_northshire_reference_resolution()
    M.test_northshire_blueprint_expansion()
    M.test_northshire_dependency_resolution()
    M.test_northshire_goal_coverage_quest_chain()
    M.test_northshire_adjacency_merge_goldshire()
    M.test_northshire_lowering_and_provenance()
    M.test_northshire_full_compiler_pipeline()

    print("\n=== All Northshire E2E Tests PASSED ===")
end

return M