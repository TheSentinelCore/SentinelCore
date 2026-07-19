-- sentinel/tests/modules/quest/test_goal_checking.lua
-- Tests for goal checking implementation

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.test_complete_quest_goal_returns_true_when_completed()
    print("Test: CompleteQuest goal returns true when quest completed")
    package.loaded["modules/quest/init"] = nil
    package.loaded["modules/quest/goal_checker"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    bb:set("player.completed_quests", { 33, 34, 35 })
    local eb = EventBus:new()

    local quest = QuestModule:new(bb, eb, {})
    quest:init()

    local operation = {
        id = "op-1",
        goals = {
            { type = "CompleteQuest", quest_id = 33 }
        }
    }

    local result = quest:check_goals(operation)
    T.assert_true(result.all_met, "all_met should be true for completed quest")
    T.assert_equal(#result.uncovered, 0, "uncovered should be empty")
    print("  PASS")
end

function M.test_complete_quest_goal_returns_false_when_not_completed()
    print("Test: CompleteQuest goal returns false when quest not completed")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    bb:set("player.completed_quests", { 34, 35 })
    local eb = EventBus:new()

    local quest = QuestModule:new(bb, eb, {})
    quest:init()

    local operation = {
        id = "op-2",
        goals = {
            { type = "CompleteQuest", quest_id = 33 }
        }
    }

    local result = quest:check_goals(operation)
    T.assert_false(result.all_met, "all_met should be false for uncompleted quest")
    T.assert_equal(#result.uncovered, 1, "uncovered should have 1 goal")
    T.assert_equal(result.uncovered[1].type, "CompleteQuest", "uncovered goal type should match")
    print("  PASS")
end

function M.test_complete_quest_chain_goal()
    print("Test: CompleteQuestChain goal checks all quests")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    bb:set("player.completed_quests", { 33, 34 })
    local eb = EventBus:new()

    local quest = QuestModule:new(bb, eb, {})
    quest:init()

    -- All quests completed
    local op_all = {
        id = "op-all",
        goals = {
            { type = "CompleteQuestChain", quest_ids = { 33, 34 } }
        }
    }
    local result_all = quest:check_goals(op_all)
    T.assert_true(result_all.all_met, "all_met should be true when all chain quests complete")

    -- One quest missing
    local op_partial = {
        id = "op-partial",
        goals = {
            { type = "CompleteQuestChain", quest_ids = { 33, 34, 35 } }
        }
    }
    local result_partial = quest:check_goals(op_partial)
    T.assert_false(result_partial.all_met, "all_met should be false when chain incomplete")
    print("  PASS")
end

function M.test_reach_level_goal()
    print("Test: ReachLevel goal checks player level")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local eb = EventBus:new()

    -- Player at level 10, goal is level 5
    local bb_met = Blackboard:new()
    bb_met:set("player.level", 10)
    local quest_met = QuestModule:new(bb_met, eb, {})
    quest_met:init()

    local operation_met = {
        id = "op-met",
        goals = {
            { type = "ReachLevel", level = 5 }
        }
    }
    local result_met = quest_met:check_goals(operation_met)
    T.assert_true(result_met.all_met, "all_met should be true when level reached")

    -- Player at level 3, goal is level 5
    local bb_not_met = Blackboard:new()
    bb_not_met:set("player.level", 3)
    local quest_not_met = QuestModule:new(bb_not_met, eb, {})
    quest_not_met:init()

    local operation_not_met = {
        id = "op-not-met",
        goals = {
            { type = "ReachLevel", level = 5 }
        }
    }
    local result_not_met = quest_not_met:check_goals(operation_not_met)
    T.assert_false(result_not_met.all_met, "all_met should be false when level not reached")
    print("  PASS")
end

function M.test_acquire_item_goal()
    print("Test: AcquireItem goal checks inventory")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local eb = EventBus:new()

    -- Player has 5 items, goal is 3
    local bb_met = Blackboard:new()
    bb_met:set("player.inventory", {
        { entry = 1234, count = 5 }
    })
    local quest_met = QuestModule:new(bb_met, eb, {})
    quest_met:init()

    local operation_met = {
        id = "op-acquire-met",
        goals = {
            { type = "AcquireItem", entry = 1234, count = 3 }
        }
    }
    local result_met = quest_met:check_goals(operation_met)
    T.assert_true(result_met.all_met, "all_met should be true when item count sufficient")

    -- Player has 2 items, goal is 5
    local bb_not_met = Blackboard:new()
    bb_not_met:set("player.inventory", {
        { entry = 1234, count = 2 }
    })
    local quest_not_met = QuestModule:new(bb_not_met, eb, {})
    quest_not_met:init()

    local operation_not_met = {
        id = "op-acquire-not-met",
        goals = {
            { type = "AcquireItem", entry = 1234, count = 5 }
        }
    }
    local result_not_met = quest_not_met:check_goals(operation_not_met)
    T.assert_false(result_not_met.all_met, "all_met should be false when item count insufficient")
    print("  PASS")
end

function M.test_unlock_flight_path_goal()
    print("Test: UnlockFlightPath goal checks flight paths")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    bb:set("player.flight_paths", { 10, 11, 12 })
    local eb = EventBus:new()

    local quest = QuestModule:new(bb, eb, {})
    quest:init()

    -- Flight path known
    local op_met = {
        id = "op-fp-met",
        goals = {
            { type = "UnlockFlightPath", node_id = 10 }
        }
    }
    local result_met = quest:check_goals(op_met)
    T.assert_true(result_met.all_met, "all_met should be true when flight path known")

    -- Flight path not known
    local op_not_met = {
        id = "op-fp-not-met",
        goals = {
            { type = "UnlockFlightPath", node_id = 99 }
        }
    }
    local result_not_met = quest:check_goals(op_not_met)
    T.assert_false(result_not_met.all_met, "all_met should be false when flight path unknown")
    print("  PASS")
end

function M.test_multiple_goals_all_uncovered()
    print("Test: Multiple goals with some uncovered")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    bb:set("player.level", 5)
    bb:set("player.completed_quests", {})
    bb:set("player.inventory", {})
    local eb = EventBus:new()

    local quest = QuestModule:new(bb, eb, {})
    quest:init()

    local operation = {
        id = "op-multi",
        goals = {
            { type = "ReachLevel", level = 10 },
            { type = "CompleteQuest", quest_id = 33 },
            { type = "AcquireItem", entry = 1234, count = 1 }
        }
    }

    local result = quest:check_goals(operation)
    T.assert_false(result.all_met, "all_met should be false")
    T.assert_equal(#result.uncovered, 3, "all 3 goals should be uncovered")
    print("  PASS")
end

function M.test_empty_goals_returns_all_met()
    print("Test: Empty goals returns all_met true")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    local eb = EventBus:new()

    local quest = QuestModule:new(bb, eb, {})
    quest:init()

    local operation = {
        id = "op-empty",
        goals = {}
    }

    local result = quest:check_goals(operation)
    T.assert_true(result.all_met, "all_met should be true for empty goals")
    T.assert_equal(#result.uncovered, 0, "uncovered should be empty")
    print("  PASS")
end

function M.run()
    print("=== Goal Checking Tests ===")
    M.test_complete_quest_goal_returns_true_when_completed()
    M.test_complete_quest_goal_returns_false_when_not_completed()
    M.test_complete_quest_chain_goal()
    M.test_reach_level_goal()
    M.test_acquire_item_goal()
    M.test_unlock_flight_path_goal()
    M.test_multiple_goals_all_uncovered()
    M.test_empty_goals_returns_all_met()
    print("\n=== All Goal Checking Tests PASSED ===")
end

return M