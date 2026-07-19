-- sentinel/tests/modules/operation/test_sub_operation_composer.lua
-- Tests for SENT-5.7: Sub-Operation Composition
-- ADR 007 §17

local T = require("tests/test_util")

local M = {}

function M.test_compute_parent_goals_simple()
    print("Test: compute_parent_goals - simple case")

    local SubOperationComposer = require("modules/operation/sub_operation_composer")
    local composer = SubOperationComposer:new()

    composer:register_operation({
        id = "sub-1",
        goals = {
            { type = "CompleteQuest", quest_id = 33, required = true },
            { type = "CompleteQuest", quest_id = 34, required = false }
        }
    })

    local parent = {
        id = "parent",
        goals = {
            { type = "CompleteQuest", quest_id = 35, required = true }
        },
        sub_operations = { "sub-1" }
    }

    local goals = composer:compute_parent_goals(parent)

    T.assert_true(#goals >= 2, "Should have at least 2 goals (33 and 35)")

    local has_33 = false
    local has_35 = false
    for _, g in ipairs(goals) do
        if g.quest_id == 33 then has_33 = true end
        if g.quest_id == 35 then has_35 = true end
    end
    T.assert_true(has_33, "Quest 33 included from sub-op")
    T.assert_true(has_35, "Quest 35 included from parent")

    print("  PASS")
end

function M.test_parent_goals_union_of_sub_ops()
    print("Test: parent goals = union of sub-operations required goals")

    local SubOperationComposer = require("modules/operation/sub_operation_composer")
    local composer = SubOperationComposer:new()

    composer:register_operation({
        id = "sub-a",
        goals = {
            { type = "CompleteQuest", quest_id = 100, required = true },
            { type = "CompleteQuest", quest_id = 101, required = true }
        }
    })

    composer:register_operation({
        id = "sub-b",
        goals = {
            { type = "CompleteQuest", quest_id = 101, required = true },
            { type = "CompleteQuest", quest_id = 102, required = true }
        }
    })

    local parent = {
        id = "parent",
        goals = {},
        sub_operations = { "sub-a", "sub-b" }
    }

    local goals = composer:compute_parent_goals(parent)

    local quest_ids = {}
    for _, g in ipairs(goals) do
        quest_ids[g.quest_id] = true
    end

    T.assert_true(quest_ids[100], "Quest 100 from sub-a")
    T.assert_true(quest_ids[101], "Quest 101 (shared between sub-a and sub-b)")
    T.assert_true(quest_ids[102], "Quest 102 from sub-b")

    print("  PASS")
end

function M.test_northshire_split_example()
    print("Test: Northshire split example from ADR 007 §17")

    local SubOperationComposer = require("modules/operation/sub_operation_composer")
    local composer = SubOperationComposer:new()

    composer:register_operation({
        id = "northshire-abbey",
        goals = {
            { type = "CompleteQuest", quest_id = 33, required = true }
        }
    })

    composer:register_operation({
        id = "northshire-valley",
        goals = {
            { type = "CompleteQuest", quest_id = 34, required = true },
            { type = "CompleteQuest", quest_id = 35, required = true },
            { type = "CompleteQuest", quest_id = 36, required = true }
        }
    })

    local parent = {
        id = "northshire",
        goals = {
            { type = "CompleteQuestChain", quest_ids = { 33, 34, 35, 36 }, required = true }
        },
        sub_operations = { "northshire-abbey", "northshire-valley" }
    }

    local goals = composer:compute_parent_goals(parent)

    local quest_ids = {}
    for _, g in ipairs(goals) do
        if g.quest_id then
            quest_ids[g.quest_id] = true
        end
    end

    T.assert_true(quest_ids[33], "Quest 33 covered")
    T.assert_true(quest_ids[34], "Quest 34 covered")
    T.assert_true(quest_ids[35], "Quest 35 covered")
    T.assert_true(quest_ids[36], "Quest 36 covered")

    print("  PASS")
end

function M.test_flatten_operations()
    print("Test: flatten_operations")

    local SubOperationComposer = require("modules/operation/sub_operation_composer")
    local composer = SubOperationComposer:new()

    composer:register_operation({
        id = "sub-a",
        goals = { { type = "CompleteQuest", quest_id = 99 } },
        sub_operations = { "sub-b" }
    })

    composer:register_operation({
        id = "sub-b",
        goals = { { type = "CompleteQuest", quest_id = 88 } }
    })

    local operations = {
        { id = "parent", sub_operations = { "sub-a" } }
    }

    local flattened = composer:flatten_operations(operations)

    T.assert_true(#flattened >= 1, "Should have flattened operations")

    print("  PASS")
end

function M.run()
    print("=== Sub-Operation Composer Tests ===")
    M.test_compute_parent_goals_simple()
    M.test_parent_goals_union_of_sub_ops()
    M.test_northshire_split_example()
    M.test_flatten_operations()
    print("\n=== All Sub-Operation Composer Tests PASSED ===")
end

return M