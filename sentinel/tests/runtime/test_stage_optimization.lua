-- sentinel/tests/runtime/test_stage_optimization.lua
-- Tests for SENT-6.7: Cross-Operation Optimization

local T = require("tests/test_util")

local M = {}

function M.test_vendor_repair_merge()
    print("Test: Vendor+Repair consecutive merge")

    package.loaded["runtime/stage_optimization"] = nil
    package.loaded["runtime/route_analysis"] = nil
    package.loaded["modules/operation/goal_coverage"] = nil
    package.loaded["core/geometry"] = nil

    local OptimizationStage = require("runtime/stage_optimization")

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Vendor Run",
                actions = {
                    { id = "act-1", action_type = "Vendor", name = "Buy" },
                    { id = "act-2", action_type = "Repair", name = "Repair" },
                },
            },
        },
    }

    local stage = OptimizationStage:new()
    local result = stage:run(profile, {})

    T.assert_equal(#result.optimizations_applied, 1, "Should apply one optimization")
    T.assert_true(result.optimizations_applied[1].description:find("Collapsed") ~= nil,
        "Should describe merge")
    T.assert_equal(#result.profile.operations[1].actions, 1, "Should have one action after merge")
    T.assert_equal(result.profile.operations[1].actions[1].params.repair, true,
        "Merged action should have repair flag")

    print("  PASS")
end

function M.test_vendor_repair_merge_with_goal_check()
    print("Test: Vendor+Repair merge respects goal coverage")

    package.loaded["runtime/stage_optimization"] = nil
    package.loaded["runtime/route_analysis"] = nil
    package.loaded["modules/operation/goal_coverage"] = nil

    local OptimizationStage = require("runtime/stage_optimization")

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Vendor Run",
                goals = {
                    { type = "RepairEquipment", required = true },
                },
                actions = {
                    { id = "act-1", action_type = "Vendor", name = "Buy" },
                    { id = "act-2", action_type = "Repair", name = "Repair" },
                },
            },
        },
    }

    local stage = OptimizationStage:new()
    local result = stage:run(profile, {})

    T.assert_equal(#result.profile.operations[1].actions, 2, "Should preserve actions for goal coverage")
    T.assert_true(#result.diagnostics.warnings > 0, "Should have warning for skipped merge")

    print("  PASS")
end

function M.test_redundant_goto_removal()
    print("Test: Adjacent redundant GoTo removal (50-yard threshold)")

    package.loaded["runtime/stage_optimization"] = nil
    package.loaded["runtime/route_analysis"] = nil

    local OptimizationStage = require("runtime/stage_optimization")

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Goldshire",
                actions = {
                    { id = "act-1", action_type = "Vendor", params = {
                        vendor = { position = { x = 100, y = 100, z = 0 } }
                    }},
                },
            },
            {
                id = "op-2",
                name = "Westbrook",
                actions = {
                    { id = "act-2", action_type = "GoToAction", params = {
                        destination = { x = 120, y = 115, z = 0 }
                    }},
                    { id = "act-3", action_type = "Kill", params = { position = { x = 120, y = 120, z = 0 } }},
                },
            },
        },
    }

    local stage = OptimizationStage:new()
    local result = stage:run(profile, { "op-1", "op-2" })

    -- Distance is sqrt((20)^2 + (15)^2) = ~25, under 50-yard threshold
    T.assert_equal(#result.profile.operations[2].actions, 1, "Should remove redundant GoTo")
    T.assert_true(result.optimizations_applied[1].description:find("Dropped") ~= nil,
        "Should describe dropped action")

    print("  PASS")
end

function M.test_redundant_goto_preserved_for_goals()
    print("Test: GoTo preserved when required by goal coverage")

    package.loaded["runtime/stage_optimization"] = nil
    package.loaded["runtime/route_analysis"] = nil
    package.loaded["modules/operation/goal_coverage"] = nil

    local OptimizationStage = require("runtime/stage_optimization")

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Goldshire",
                actions = {
                    { id = "act-1", action_type = "Vendor", params = {
                        vendor = { position = { x = 100, y = 100, z = 0, zone = "Goldshire" } }
                    }},
                },
            },
            {
                id = "op-2",
                name = "Zone Entry",
                goals = {
                    { type = "ReachZone", zone_name = "Westbrook", required = true },
                },
                actions = {
                    { id = "act-2", action_type = "GoToAction", params = {
                        destination = { x = 120, y = 115, z = 0, zone = "Westbrook" }
                    }},
                    { id = "act-3", action_type = "Kill", params = { position = { x = 120, y = 120, z = 0 } }},
                },
            },
        },
    }

    local stage = OptimizationStage:new()
    local result = stage:run(profile, { "op-1", "op-2" })

    -- GoTo should be preserved because it's the only action covering ReachZone goal
    T.assert_equal(#result.profile.operations[2].actions, 2, "Should preserve GoTo for goal")

    print("  PASS")
end

function M.test_goto_not_removed_outside_threshold()
    print("Test: GoTo not removed when outside 50-yard threshold")

    package.loaded["runtime/stage_optimization"] = nil
    package.loaded["runtime/route_analysis"] = nil

    local OptimizationStage = require("runtime/stage_optimization")

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Far Away",
                actions = {
                    { id = "act-1", action_type = "Vendor", params = {
                        vendor = { position = { x = 0, y = 0, z = 0 } }
                    }},
                },
            },
            {
                id = "op-2",
                name = "Distant",
                actions = {
                    { id = "act-2", action_type = "GoToAction", params = {
                        destination = { x = 200, y = 200, z = 0 }
                    }},
                    { id = "act-3", action_type = "Kill", params = { position = { x = 200, y = 200, z = 0 } }},
                },
            },
        },
    }

    local stage = OptimizationStage:new()
    local result = stage:run(profile, { "op-1", "op-2" })

    -- Distance is ~283 yards, over 50-yard threshold
    T.assert_equal(#result.profile.operations[2].actions, 2, "Should preserve distant GoTo")

    print("  PASS")
end

function M.test_reordering_placeholder()
    print("Test: Reordering placeholder with allow_reordering=true")

    package.loaded["runtime/stage_optimization"] = nil
    package.loaded["runtime/route_analysis"] = nil

    local OptimizationStage = require("runtime/stage_optimization")

    local profile = {
        operations = {
            {
                id = "op-1",
                name = "Reorder Test",
                optimization_policy = { allow_reordering = true },
                actions = {
                    { id = "act-1", action_type = "GoToAction", params = {
                        destination = { x = 100, y = 100, z = 0 }
                    }},
                    { id = "act-2", action_type = "GoToAction", params = {
                        destination = { x = 50, y = 50, z = 0 }
                    }},
                },
            },
        },
    }

    local stage = OptimizationStage:new()
    local result = stage:run(profile, { "op-1" })

    T.assert_equal(result.profile.operations[1].actions[1].id, "act-1",
        "Should preserve original order (reordering returns nil when no improvement)")

    print("  PASS")
end

function M.test_position_extraction()
    print("Test: Position extraction from various action types")

    package.loaded["runtime/stage_optimization"] = nil

    local OptimizationStage = require("runtime/stage_optimization")

    local stage = OptimizationStage:new()

    -- Test Vendor position
    local vendor_pos = stage:_extract_position_from_vendor({
        params = { vendor = { position = { x = 10, y = 20, z = 30 } } }
    })
    T.assert_equal(vendor_pos.x, 10, "Vendor position x")
    T.assert_equal(vendor_pos.y, 20, "Vendor position y")

    -- Test parameterized position
    local param_pos = stage:_extract_position_from_vendor({
        params = { x = 40, y = 50, z = 60 }
    })
    T.assert_equal(param_pos.x, 40, "Param position x")

    print("  PASS")
end

function M.test_deep_copy_preserves_structure()
    print("Test: Deep copy preserves profile structure")

    package.loaded["runtime/stage_optimization"] = nil

    local OptimizationStage = require("runtime/stage_optimization")

    local original = {
        operations = {
            {
                id = "op-1",
                actions = {
                    { id = "act-1", nested = { value = 42 } },
                },
            },
        },
    }

    local stage = OptimizationStage:new()
    local copy = stage:_deep_copy(original)

    T.assert_equal(copy.operations[1].id, "op-1", "Copy should preserve id")
    T.assert_true(copy ~= original, "Should be different table")
    T.assert_true(copy.operations ~= original.operations, "Nested should be different")
    T.assert_true(copy.operations[1].actions ~= original.operations[1].actions, "Actions should be different")
    T.assert_true(copy.operations[1].actions[1].nested ~= original.operations[1].actions[1].nested, "Deep nested should be different")

    print("  PASS")
end

function M.run()
    print("=== Stage Optimization Tests (SENT-6.7) ===")
    M.test_vendor_repair_merge()
    M.test_vendor_repair_merge_with_goal_check()
    M.test_redundant_goto_removal()
    M.test_redundant_goto_preserved_for_goals()
    M.test_goto_not_removed_outside_threshold()
    M.test_reordering_placeholder()
    M.test_position_extraction()
    M.test_deep_copy_preserves_structure()
    print("\n=== All Stage Optimization Tests PASSED ===")
end

return M