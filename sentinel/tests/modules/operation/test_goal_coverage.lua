-- sentinel/tests/modules/operation/test_goal_coverage.lua
-- Tests for SENT-5.1: Goal Coverage Checking

local T = require("tests/test_util")

local M = {}

function M.test_check_action_coverage_for_complete_quest()
    print("Test: check_action_coverage_for_goal - CompleteQuest")

    local GoalCoverage = require("modules/operation/goal_coverage")

    local goal = { type = "CompleteQuest", quest_id = 33 }

    T.assert_true(GoalCoverage.check_action_coverage_for_goal({ type = "PickupQuest", quest_id = 33 }, goal),
        "PickupQuest should cover CompleteQuest goal")
    T.assert_true(GoalCoverage.check_action_coverage_for_goal({ type = "TurnInQuest", quest_id = 33 }, goal),
        "TurnInQuest should cover CompleteQuest goal")
    T.assert_false(GoalCoverage.check_action_coverage_for_goal({ type = "PickupQuest", quest_id = 34 }, goal),
        "PickupQuest for different quest should not cover")

    print("  PASS")
end

function M.test_check_action_coverage_for_complete_quest_chain()
    print("Test: check_action_coverage_for_goal - CompleteQuestChain")

    local GoalCoverage = require("modules/operation/goal_coverage")

    local goal = { type = "CompleteQuestChain", quest_ids = { 33, 34, 35 } }

    T.assert_true(GoalCoverage.check_action_coverage_for_goal({ type = "TurnInQuest", quest_id = 33 }, goal),
        "TurnInQuest 33 should cover chain goal")
    T.assert_true(GoalCoverage.check_action_coverage_for_goal({ type = "PickupQuest", quest_id = 34 }, goal),
        "PickupQuest 34 should cover chain goal")
    T.assert_false(GoalCoverage.check_action_coverage_for_goal({ type = "PickupQuest", quest_id = 99 }, goal),
        "PickupQuest 99 should not cover chain goal")

    print("  PASS")
end

function M.test_check_action_coverage_for_acquire_item()
    print("Test: check_action_coverage_for_goal - AcquireItem")

    local GoalCoverage = require("modules/operation/goal_coverage")

    local goal = { type = "AcquireItem", entry = 1234, count = 5 }

    T.assert_true(GoalCoverage.check_action_coverage_for_goal({ type = "Loot", entry = 1234 }, goal),
        "Loot action should cover AcquireItem goal")
    T.assert_true(GoalCoverage.check_action_coverage_for_goal({ type = "PickupItem", entry = 1234 }, goal),
        "PickupItem action should cover AcquireItem goal")
    T.assert_false(GoalCoverage.check_action_coverage_for_goal({ type = "Loot", entry = 5678 }, goal),
        "Loot for wrong entry should not cover")

    print("  PASS")
end

function M.test_check_action_coverage_for_kill_count()
    print("Test: check_action_coverage_for_goal - KillCount")

    local GoalCoverage = require("modules/operation/goal_coverage")

    local goal = { type = "KillCount", entry = 555, count = 10 }

    T.assert_true(GoalCoverage.check_action_coverage_for_goal({ type = "Kill", entry = 555 }, goal),
        "Kill action should cover KillCount goal")
    T.assert_true(GoalCoverage.check_action_coverage_for_goal({ type = "GrindArea", creature_entry = 555 }, goal),
        "GrindArea action should cover KillCount goal")
    T.assert_false(GoalCoverage.check_action_coverage_for_goal({ type = "Kill", entry = 999 }, goal),
        "Kill for wrong entry should not cover")

    print("  PASS")
end

function M.test_is_statically_checkable()
    print("Test: is_statically_checkable")

    local GoalCoverage = require("modules/operation/goal_coverage")

    T.assert_true(GoalCoverage.is_statically_checkable("CompleteQuest"),
        "CompleteQuest should be statically checkable")
    T.assert_true(GoalCoverage.is_statically_checkable("AcquireItem"),
        "AcquireItem should be statically checkable")
    T.assert_true(GoalCoverage.is_statically_checkable("KillCount"),
        "KillCount should be statically checkable")
    T.assert_false(GoalCoverage.is_statically_checkable("ReachLevel"),
        "ReachLevel should NOT be statically checkable (informational)")
    T.assert_false(GoalCoverage.is_statically_checkable("GainXp"),
        "GainXp should NOT be statically checkable (informational)")

    print("  PASS")
end

function M.test_analyze_goal_coverage()
    print("Test: analyze_goal_coverage")

    local GoalCoverage = require("modules/operation/goal_coverage")

    local operation = {
        goals = {
            { type = "CompleteQuest", quest_id = 33, required = true },
            { type = "ReachLevel", level = 5, required = false },
        },
        actions = {
            { type = "PickupQuest", quest_id = 33 },
            { type = "TurnInQuest", quest_id = 33 },
        }
    }

    local result = GoalCoverage.analyze_goal_coverage(operation)

    T.assert_true(result.all_covered, "All required goals should be covered")
    T.assert_equal(#result.uncovered_required, 0, "No required goals uncovered")
    T.assert_equal(#result.informational, 1, "ReachLevel should be informational")

    print("  PASS")
end

function M.test_analyze_goal_coverage_uncovered()
    print("Test: analyze_goal_coverage - uncovered required goal")

    local GoalCoverage = require("modules/operation/goal_coverage")

    local operation = {
        goals = {
            { type = "CompleteQuest", quest_id = 99, required = true },
        },
        actions = {
            { type = "PickupQuest", quest_id = 33 },
        }
    }

    local result = GoalCoverage.analyze_goal_coverage(operation)

    T.assert_false(result.all_covered, "Should not be fully covered")
    T.assert_equal(#result.uncovered_required, 1, "One required goal uncovered")

    print("  PASS")
end

function M.run()
    print("=== Goal Coverage Tests ===")
    M.test_check_action_coverage_for_complete_quest()
    M.test_check_action_coverage_for_complete_quest_chain()
    M.test_check_action_coverage_for_acquire_item()
    M.test_check_action_coverage_for_kill_count()
    M.test_is_statically_checkable()
    M.test_analyze_goal_coverage()
    M.test_analyze_goal_coverage_uncovered()
    print("\n=== All Goal Coverage Tests PASSED ===")
end

return M