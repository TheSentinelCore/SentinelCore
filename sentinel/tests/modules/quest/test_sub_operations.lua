-- sentinel/tests/modules/quest/test_sub_operations.lua
-- Tests for sub-operation support (Volume 7 §17)

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.test_sub_operation_state_stored_in_blackboard()
    print("Test: Sub-operation state stored in blackboard")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    local eb = EventBus:new()

    local quest = QuestModule:new(bb, eb, {})
    quest:init()

    local operation = {
        id = "parent-op",
        name = "Quest Hub",
        sub_operations = {
            { id = "sub-1", name = "Sub Op 1", priority = 10, actions = {} },
            { id = "sub-2", name = "Sub Op 2", priority = 5, actions = {} }
        }
    }

    -- Initialize sub-operations
    quest:_init_sub_operations(operation)

    local sub_ops = bb:get("module.quest.sub_ops")
    T.assert_not_nil(sub_ops, "sub_ops should be set in blackboard")
    T.assert_true(sub_ops["parent-op"] ~= nil, "parent operation should have sub_ops entry")
    print("  PASS")
end

function M.test_parent_considers_child_goals()
    print("Test: Parent operation considers child operation goals")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    bb:set("player.completed_quests", { 33 })  -- Only quest 33 done
    local eb = EventBus:new()

    local quest = QuestModule:new(bb, eb, {})
    quest:init()

    local operation = {
        id = "parent-op",
        goals = {
            { type = "CompleteQuest", quest_id = 99 }  -- Not completed
        },
        sub_operations = {
            {
                id = "sub-1",
                goals = {
                    { type = "CompleteQuest", quest_id = 33 }  -- Completed
                }
            }
        }
    }

    local result = quest:check_goals(operation)
    -- Parent goal (quest 99) is not met, so all_met should be false
    T.assert_false(result.all_met, "all_met should be false when parent goal unmet")
    print("  PASS")
end

function M.test_sub_operation_completion_marks_in_blackboard()
    print("Test: Sub-operation completion updates blackboard")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    local eb = EventBus:new()

    local quest = QuestModule:new(bb, eb, {})
    quest:init()

    -- Initialize sub-operation tracking for a parent (using correct key format)
    bb:set("module.quest.sub_ops", {
        ["parent-op"] = {
            current_sub = "sub-1",
            completed_subs = {}
        }
    })

    -- Complete a sub-operation
    quest:_complete_sub_operation("parent-op", "sub-1")

    local sub_ops = bb:get("module.quest.sub_ops")
    T.assert_not_nil(sub_ops, "sub_ops should exist in blackboard")
    T.assert_true(sub_ops["parent-op"].completed_subs["sub-1"] ~= nil, "sub-1 should be marked completed")
    print("  PASS")
end

function M.test_get_active_sub_operation()
    print("Test: Get active sub-operation returns correct one")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    bb:set("player.completed_quests", {})
    bb:set("player.inventory", {})
    local eb = EventBus:new()

    local quest = QuestModule:new(bb, eb, {})
    quest:init()

    local operation = {
        id = "parent-op",
        sub_operations = {
            { id = "sub-1", priority = 10, goals = { { type = "CompleteQuest", quest_id = 99 } } },
            { id = "sub-2", priority = 20, goals = { { type = "CompleteQuest", quest_id = 88 } } },
        }
    }

    quest:_init_sub_operations(operation)

    -- Highest priority sub-op should be active
    local active = quest:_get_active_sub_operation("parent-op")
    T.assert_equal(active.id, "sub-2", "highest priority sub should be active initially")
    print("  PASS")
end

function M.run()
    print("=== Sub-Operation Tests ===")
    M.test_sub_operation_state_stored_in_blackboard()
    M.test_parent_considers_child_goals()
    M.test_sub_operation_completion_marks_in_blackboard()
    M.test_get_active_sub_operation()
    print("\n=== All Sub-Operation Tests PASSED ===")
end

return M