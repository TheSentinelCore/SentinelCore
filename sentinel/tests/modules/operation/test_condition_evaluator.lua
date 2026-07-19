-- sentinel/tests/modules/operation/test_condition_evaluator.lua
-- Tests for SENT-5.2: Entry/Exit Condition Evaluation Engine

local T = require("tests/test_util")
local Blackboard = require("core/blackboard")

local M = {}

function M.test_evaluate_race_condition()
    print("Test: evaluate RaceIs condition")

    local ConditionEvaluator = require("modules/operation/condition_evaluator")
    local bb = Blackboard:new()
    bb:set("player.race", 1)

    local eval = ConditionEvaluator:new(bb)

    T.assert_true(eval:evaluate({ type = "RaceIs", race = 1 }, {}), "Should be true for matching race")
    T.assert_false(eval:evaluate({ type = "RaceIs", race = 2 }, {}), "Should be false for non-matching race")

    print("  PASS")
end

function M.test_evaluate_level_condition()
    print("Test: evaluate LevelAbove/LevelBelow conditions")

    local ConditionEvaluator = require("modules/operation/condition_evaluator")
    local bb = Blackboard:new()
    bb:set("player.level", 10)

    local eval = ConditionEvaluator:new(bb)

    T.assert_true(eval:evaluate({ type = "LevelAbove", level = 5 }, {}), "Level 10 > 5")
    T.assert_false(eval:evaluate({ type = "LevelAbove", level = 15 }, {}), "Level 10 not > 15")
    T.assert_true(eval:evaluate({ type = "LevelBelow", level = 15 }, {}), "Level 10 < 15")
    T.assert_false(eval:evaluate({ type = "LevelBelow", level = 5 }, {}), "Level 10 not < 5")

    print("  PASS")
end

function M.test_evaluate_quest_condition()
    print("Test: evaluate QuestCompleted condition")

    local ConditionEvaluator = require("modules/operation/condition_evaluator")
    local bb = Blackboard:new()
    bb:set("player.completed_quests", { 33, 34, 35 })

    local eval = ConditionEvaluator:new(bb)

    T.assert_true(eval:evaluate({ type = "QuestCompleted", quest_id = 33 }, {}), "Quest 33 is completed")
    T.assert_false(eval:evaluate({ type = "QuestCompleted", quest_id = 99 }, {}), "Quest 99 not completed")

    print("  PASS")
end

function M.test_evaluate_has_item_condition()
    print("Test: evaluate HasItem condition")

    local ConditionEvaluator = require("modules/operation/condition_evaluator")
    local bb = Blackboard:new()
    bb:set("player.inventory", {
        { entry = 1234, count = 5 },
        { entry = 5678, count = 2 }
    })

    local eval = ConditionEvaluator:new(bb)

    T.assert_true(eval:evaluate({ type = "HasItem", entry = 1234, count = 3 }, {}), "Have 5 of item 1234, need 3")
    T.assert_false(eval:evaluate({ type = "HasItem", entry = 1234, count = 10 }, {}), "Have 5, need 10")
    T.assert_false(eval:evaluate({ type = "HasItem", entry = 9999, count = 1 }, {}), "Don't have item 9999")

    print("  PASS")
end

function M.test_evaluate_has_spell_condition()
    print("Test: evaluate HasSpell condition")

    local ConditionEvaluator = require("modules/operation/condition_evaluator")
    local bb = Blackboard:new()
    bb:set("player.spells", { 12345, 67890 })

    local eval = ConditionEvaluator:new(bb)

    T.assert_true(eval:evaluate({ type = "HasSpell", spell_id = 12345 }, {}), "Spell 12345 known")
    T.assert_false(eval:evaluate({ type = "HasSpell", spell_id = 99999 }, {}), "Spell 99999 not known")

    print("  PASS")
end

function M.test_evaluate_operation_status_condition()
    print("Test: evaluate OperationCompleted/Skipped/Failed conditions")

    local ConditionEvaluator = require("modules/operation/condition_evaluator")
    local bb = Blackboard:new()
    bb:set("operation.op-1.status", "Completed")
    bb:set("operation.op-2.status", "Skipped")
    bb:set("operation.op-3.status", "Failed")

    local eval = ConditionEvaluator:new(bb)

    T.assert_true(eval:evaluate({ type = "OperationCompleted", operation_id = "op-1" }, {}), "op-1 completed")
    T.assert_true(eval:evaluate({ type = "OperationSkipped", operation_id = "op-2" }, {}), "op-2 skipped")
    T.assert_true(eval:evaluate({ type = "OperationFailed", operation_id = "op-3" }, {}), "op-3 failed")
    T.assert_false(eval:evaluate({ type = "OperationCompleted", operation_id = "op-2" }, {}), "op-2 not completed")

    print("  PASS")
end

function M.test_evaluate_compound_conditions()
    print("Test: evaluate And/Or/Not compound conditions")

    local ConditionEvaluator = require("modules/operation/condition_evaluator")
    local bb = Blackboard:new()
    bb:set("player.level", 10)
    bb:set("player.race", 1)

    local eval = ConditionEvaluator:new(bb)

    T.assert_true(eval:evaluate({
        type = "And",
        conditions = {
            { type = "LevelAbove", level = 5 },
            { type = "RaceIs", race = 1 }
        }
    }, {}), "And: both conditions true")

    T.assert_false(eval:evaluate({
        type = "And",
        conditions = {
            { type = "LevelAbove", level = 5 },
            { type = "RaceIs", race = 2 }
        }
    }, {}), "And: one condition false")

    T.assert_true(eval:evaluate({
        type = "Or",
        conditions = {
            { type = "RaceIs", race = 2 },
            { type = "LevelAbove", level = 5 }
        }
    }, {}), "Or: second condition true")

    T.assert_false(eval:evaluate({
        type = "Or",
        conditions = {
            { type = "RaceIs", race = 2 },
            { type = "LevelBelow", level = 5 }
        }
    }, {}), "Or: both conditions false")

    T.assert_true(eval:evaluate({
        type = "Not",
        condition = { type = "LevelBelow", level = 5 }
    }, {}), "Not: LevelAbove(5) is true, so Not(LevelBelow(5)) is true")

    print("  PASS")
end

function M.test_evaluate_entry_conditions()
    print("Test: evaluate_entry_conditions")

    local ConditionEvaluator = require("modules/operation/condition_evaluator")
    local bb = Blackboard:new()
    bb:set("player.race", 1)
    bb:set("player.level", 3)

    local eval = ConditionEvaluator:new(bb)

    local operation = {
        entry_conditions = {
            { type = "RaceIs", race = 1 },
            { type = "LevelBelow", level = 6 }
        }
    }

    local result = eval:evaluate_entry_conditions(operation, {})
    T.assert_true(result.eligible, "Entry conditions met")
    T.assert_equal(#result.blocking_conditions, 0, "No blocking conditions")

    local operation2 = {
        entry_conditions = {
            { type = "RaceIs", race = 2 },
            { type = "LevelBelow", level = 6 }
        }
    }

    local result2 = eval:evaluate_entry_conditions(operation2, {})
    T.assert_false(result2.eligible, "Entry conditions not met")
    T.assert_equal(#result2.blocking_conditions, 1, "One blocking condition")

    print("  PASS")
end

function M.test_evaluate_exit_conditions()
    print("Test: evaluate_exit_conditions")

    local ConditionEvaluator = require("modules/operation/condition_evaluator")
    local bb = Blackboard:new()

    local eval = ConditionEvaluator:new(bb)

    local operation = {
        id = "test-op",
        exit_conditions = {
            success = {
                { type = "QuestCompleted", quest_id = 33 }
            },
            failure = {
                { type = "QuestCompleted", quest_id = 99 }
            },
            abort = {
                { type = "LevelAbove", level = 200 }
            }
        }
    }

    bb:set("player.completed_quests", { 33 })
    local result = eval:evaluate_exit_conditions(operation, {})
    T.assert_true(result.success, "Success condition met")
    T.assert_equal(result.status, "Completed", "Status should be Completed")

    bb:set("player.completed_quests", { 99 })
    local result2 = eval:evaluate_exit_conditions(operation, {})
    T.assert_true(result2.failure, "Failure condition met")
    T.assert_equal(result2.status, "Failed", "Status should be Failed")

    print("  PASS")
end

function M.run()
    print("=== Condition Evaluator Tests ===")
    M.test_evaluate_race_condition()
    M.test_evaluate_level_condition()
    M.test_evaluate_quest_condition()
    M.test_evaluate_has_item_condition()
    M.test_evaluate_has_spell_condition()
    M.test_evaluate_operation_status_condition()
    M.test_evaluate_compound_conditions()
    M.test_evaluate_entry_conditions()
    M.test_evaluate_exit_conditions()
    print("\n=== All Condition Evaluator Tests PASSED ===")
end

return M
