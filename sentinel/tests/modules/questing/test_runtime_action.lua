-- tests/modules/questing/test_runtime_action.lua
-- Unit tests for runtime action execution and condition evaluation

local RuntimeAction = require("modules/questing/runtime_action")

local M = {}

-- ============================================================================
-- Helper: create a mock context with condition evaluation stubs
-- ============================================================================
local function mock_context(overrides)
    overrides = overrides or {}
    return {
        -- Quest tracking
        is_quest_completed = overrides.is_quest_completed or function() return false end,
        is_quest_active = overrides.is_quest_active or function() return false end,
        is_objective_complete = overrides.is_objective_complete or function() return false end,

        -- Player stats
        get_player_level = overrides.get_player_level or function() return 1 end,
        get_player_class = overrides.get_player_class or function() return "Unknown" end,
        get_player_race = overrides.get_player_race or function() return "Unknown" end,
        get_player_faction = overrides.get_player_faction or function() return "Neutral" end,

        -- Inventory
        get_item_count = overrides.get_item_count or function() return 0 end,
        get_money = overrides.get_money or function() return 0 end,

        -- Skills / reputation / cooldown
        get_skill_level = overrides.get_skill_level or function() return 0 end,
        is_item_ready = overrides.is_item_ready or function() return true end,
        get_reputation = overrides.get_reputation or function() return 0 end,

        -- Variables
        variables = overrides.variables or {},
        query = overrides.query or {},
    }
end

-- ============================================================================
-- Basic RuntimeAction tests
-- ============================================================================

function M.test_runtime_action_table()
    assert(type(RuntimeAction) == "table", "RuntimeAction should be a table")
    assert(type(RuntimeAction.execute) == "function", "RuntimeAction.execute should be a function")
end

function M.test_execute_comment()
    local ctx = mock_context()
    local action = { type = "Comment", payload = { text = "Test comment" } }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "success", "Comment action should succeed")
end

function M.test_execute_set_variable()
    local ctx = mock_context()
    local action = { type = "SetVariable", payload = { name = "test_var", value = 42 } }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "success", "SetVariable action should succeed")
    assert(ctx.variables.test_var == 42, "Variable should be set")
end

-- ============================================================================
-- evaluate_condition() tests
-- ============================================================================

function M.test_condition_always_true()
    local ctx = mock_context()
    local result = RuntimeAction.evaluate_condition(ctx, "AlwaysTrue")
    assert(result == true, "AlwaysTrue should return true")
end

function M.test_condition_quest_completed()
    local ctx = mock_context({
        is_quest_completed = function(self, entry)
            return entry == 33
        end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "QuestCompleted", payload = 33 }) == true,
        "QuestCompleted(33) with completed quest should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "QuestCompleted", payload = 99 }) == false,
        "QuestCompleted(99) with incomplete quest should be false")
end

function M.test_condition_quest_active()
    local ctx = mock_context({
        is_quest_active = function(self, entry)
            return entry == 42
        end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "QuestAccepted", payload = 42 }) == true,
        "QuestAccepted(42) with active quest should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "QuestAccepted", payload = 99 }) == false,
        "QuestAccepted(99) with inactive quest should be false")
end

function M.test_condition_level_at_least()
    local ctx = mock_context({
        get_player_level = function() return 60 end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelAtLeast", payload = 60 }) == true,
        "LevelAtLeast(60) at level 60 should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelAtLeast", payload = 70 }) == false,
        "LevelAtLeast(70) at level 60 should be false")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelAtLeast", payload = 10 }) == true,
        "LevelAtLeast(10) at level 60 should be true")
end

function M.test_condition_level_below()
    local ctx = mock_context({
        get_player_level = function() return 60 end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelBelow", payload = 70 }) == true,
        "LevelBelow(70) at level 60 should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelBelow", payload = 60 }) == false,
        "LevelBelow(60) at level 60 should be false")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelBelow", payload = 50 }) == false,
        "LevelBelow(50) at level 60 should be false")
end

function M.test_condition_has_item()
    local ctx = mock_context({
        get_item_count = function(self, entry)
            if entry == 6948 then return 1 end
            return 0
        end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "HasItem", payload = 6948 }) == true,
        "HasItem(6948) with item should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "HasItem", payload = 9999 }) == false,
        "HasItem(9999) without item should be false")
end

function M.test_condition_item_count_at_least()
    local ctx = mock_context({
        get_item_count = function(self, entry)
            if entry == 6948 then return 3 end
            return 0
        end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "ItemCountAtLeast", payload = { 6948, 3 } }) == true,
        "ItemCountAtLeast(6948, 3) with 3 items should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "ItemCountAtLeast", payload = { 6948, 5 } }) == false,
        "ItemCountAtLeast(6948, 5) with 3 items should be false")
end

function M.test_condition_gold_at_least()
    local ctx = mock_context({
        get_money = function() return 50000 end,  -- 5 gold
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "GoldAtLeast", payload = 50000 }) == true,
        "GoldAtLeast(50000) with 5g should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "GoldAtLeast", payload = 100000 }) == false,
        "GoldAtLeast(100000) with 5g should be false")
end

function M.test_condition_class_is()
    local ctx = mock_context({
        get_player_class = function() return "Priest" end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "ClassIs", payload = "Priest" }) == true,
        "ClassIs(Priest) for priest should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "ClassIs", payload = "Mage" }) == false,
        "ClassIs(Mage) for priest should be false")
end

function M.test_condition_race_is()
    local ctx = mock_context({
        get_player_race = function() return "Human" end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "RaceIs", payload = "Human" }) == true,
        "RaceIs(Human) for human should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "RaceIs", payload = "Orc" }) == false,
        "RaceIs(Orc) for human should be false")
end

function M.test_condition_faction_is()
    local ctx = mock_context({
        get_player_faction = function() return "Alliance" end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "FactionIs", payload = "Alliance" }) == true,
        "FactionIs(Alliance) for alliance should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "FactionIs", payload = "Horde" }) == false,
        "FactionIs(Horde) for alliance should be false")
end

function M.test_condition_not()
    local ctx = mock_context({
        get_player_class = function() return "Priest" end,
    })
    -- Not(ClassIs(Mage)) — priest is not a mage → true
    local cond = { type = "Not", payload = { type = "ClassIs", payload = "Mage" } }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == true,
        "Not(ClassIs(Mage)) for priest should be true")
    -- Not(ClassIs(Priest)) — priest IS a priest → false
    cond = { type = "Not", payload = { type = "ClassIs", payload = "Priest" } }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == false,
        "Not(ClassIs(Priest)) for priest should be false")
end

function M.test_condition_all()
    local ctx = mock_context({
        get_player_level = function() return 60 end,
        is_quest_completed = function(self, entry)
            return entry == 33
        end,
    })
    -- All(LevelAtLeast(10), QuestCompleted(33)) — both true → true
    local cond = {
        type = "All",
        payload = {
            { type = "LevelAtLeast", payload = 10 },
            { type = "QuestCompleted", payload = 33 },
        },
    }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == true,
        "All(true, true) should be true")

    -- All(LevelAtLeast(70), QuestCompleted(33)) — first false → false
    cond = {
        type = "All",
        payload = {
            { type = "LevelAtLeast", payload = 70 },
            { type = "QuestCompleted", payload = 33 },
        },
    }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == false,
        "All(false, true) should be false")
end

function M.test_condition_any()
    local ctx = mock_context({
        get_player_level = function() return 60 end,
        is_quest_completed = function(self, entry)
            return entry == 33
        end,
    })
    -- Any(LevelAtLeast(10), QuestCompleted(99)) — first true → true
    local cond = {
        type = "Any",
        payload = {
            { type = "LevelAtLeast", payload = 10 },
            { type = "QuestCompleted", payload = 99 },
        },
    }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == true,
        "Any(true, false) should be true")

    -- Any(LevelAtLeast(70), QuestCompleted(99)) — both false → false
    cond = {
        type = "Any",
        payload = {
            { type = "LevelAtLeast", payload = 70 },
            { type = "QuestCompleted", payload = 99 },
        },
    }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == false,
        "Any(false, false) should be false")
end

function M.test_condition_nested_logic()
    local ctx = mock_context({
        get_player_level = function() return 60 end,
        get_player_class = function() return "Priest" end,
        is_quest_completed = function(self, entry)
            return entry == 33
        end,
    })
    -- Not(All(LevelAtLeast(10), Not(ClassIs(Priest))))
    -- inner: All(LevelAtLeast(10)=true, Not(ClassIs(Priest)=false)=false) = false
    -- Not(false) = true
    local cond = {
        type = "Not",
        payload = {
            type = "All",
            payload = {
                { type = "LevelAtLeast", payload = 10 },
                { type = "Not", payload = { type = "ClassIs", payload = "Priest" } },
            },
        },
    }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == true,
        "Nested Not(All(Level≥10, Not(Priest))) should be true")
end

-- ============================================================================
-- execute_condition() mapping tests
-- ============================================================================

function M.test_execute_condition_gate_passes()
    local ctx = mock_context({
        is_quest_completed = function(self, entry) return entry == 33 end,
    })
    local action = {
        type = "Condition",
        payload = { condition = { type = "QuestCompleted", payload = 33 } },
    }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "success", "Condition gate should pass when condition is true")
end

function M.test_execute_condition_gate_skips()
    local ctx = mock_context({
        is_quest_completed = function(self, entry) return false end,
    })
    local action = {
        type = "Condition",
        payload = { condition = { type = "QuestCompleted", payload = 99 } },
    }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "skipped", "Condition gate should skip when condition is false")
end

-- ============================================================================
-- Unknown action type
-- ============================================================================

function M.test_execute_unknown_type()
    local ctx = mock_context()
    local action = { type = "NonExistentType", payload = {} }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "failed", "Unknown action type should return failed")
end

function M.test_evaluate_condition_unknown_type()
    local ctx = mock_context()
    -- Unknown condition types default to true (fails open)
    local result = RuntimeAction.evaluate_condition(ctx, { type = "MadeUpCondition", payload = "foo" })
    assert(result == true, "Unknown condition type should default to true")
end

-- ============================================================================
-- Run all tests
-- ============================================================================

local tests = {
    test_runtime_action_table = M.test_runtime_action_table,
    test_execute_comment = M.test_execute_comment,
    test_execute_set_variable = M.test_execute_set_variable,

    test_condition_always_true = M.test_condition_always_true,
    test_condition_quest_completed = M.test_condition_quest_completed,
    test_condition_quest_active = M.test_condition_quest_active,
    test_condition_level_at_least = M.test_condition_level_at_least,
    test_condition_level_below = M.test_condition_level_below,
    test_condition_has_item = M.test_condition_has_item,
    test_condition_item_count_at_least = M.test_condition_item_count_at_least,
    test_condition_gold_at_least = M.test_condition_gold_at_least,
    test_condition_class_is = M.test_condition_class_is,
    test_condition_race_is = M.test_condition_race_is,
    test_condition_faction_is = M.test_condition_faction_is,
    test_condition_not = M.test_condition_not,
    test_condition_all = M.test_condition_all,
    test_condition_any = M.test_condition_any,
    test_condition_nested_logic = M.test_condition_nested_logic,

    test_execute_condition_gate_passes = M.test_execute_condition_gate_passes,
    test_execute_condition_gate_skips = M.test_execute_condition_gate_skips,

    test_execute_unknown_type = M.test_execute_unknown_type,
    test_evaluate_condition_unknown_type = M.test_evaluate_condition_unknown_type,
}

function M.run()
    for name, fn in pairs(tests) do
        local ok, err = pcall(fn)
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M