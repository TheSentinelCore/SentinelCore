-- tests/modules/questing/test_quest_log_space.lua
-- Quest-log-full recovery: pure sacrificial-quest selection (quest_log_space.lua)
-- and the QuestingModule game:ui_error handler that abandons via core.quests.

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local QuestingModule = require("modules/questing/module")
local QuestLogSpace = require("modules/questing/quest_log_space")
local T = require("tests/test_util")

local M = {}

local function op_with(actions)
    return { actions = actions }
end

local function accept(qid) return { type = "AcceptQuest", payload = { quest_id = qid, npc_entry = 1 } } end
local function turnin(qid) return { type = "TurnInQuest", payload = { quest_id = qid, npc_entry = 1 } } end

function M.test_selection_prefers_nonroute_incomplete()
    local ops = {
        op_with({ accept(10) }),
        op_with({ turnin(11), { type = "Condition",
            payload = { role = "Completion", condition = { type = "QuestCompleted", payload = 12 } } } }),
    }
    -- Log: route quest 10, non-route complete 21 (listed first), non-route incomplete 20.
    local entries = {
        { index = 1, quest_id = 21, is_complete = 1 },
        { index = 2, quest_id = 10, is_complete = 0 },
        { index = 3, quest_id = 20, is_complete = 0 },
    }
    local pick = QuestLogSpace.select_sacrificial_quest(entries, ops, 1)
    T.assert_equal(pick and pick.quest_id, 20,
        "must prefer the non-route quest whose is_complete flag is 0")

    -- Only complete non-route quests left: still better than nothing.
    local entries2 = {
        { index = 1, quest_id = 10, is_complete = 0 },
        { index = 2, quest_id = 21, is_complete = 1 },
    }
    local pick2 = QuestLogSpace.select_sacrificial_quest(entries2, ops, 1)
    T.assert_equal(pick2 and pick2.quest_id, 21,
        "a complete non-route quest is the fallback sacrifice")
end

function M.test_numeric_flag_normalization()
    -- is_complete = 0 is truthy in Lua; it must read as INCOMPLETE.
    local ops = { op_with({ accept(10) }) }
    local entries = {
        { index = 1, quest_id = 30, is_complete = 1 },
        { index = 2, quest_id = 31, is_complete = 0 },
    }
    local pick = QuestLogSpace.select_sacrificial_quest(entries, ops, 1)
    T.assert_equal(pick and pick.quest_id, 31, "is_complete=0 must be treated as incomplete")
    T.assert_true(QuestLogSpace.quest_flag(1), "1 is complete")
    T.assert_true(QuestLogSpace.quest_flag(true), "true is complete")
    T.assert_false(QuestLogSpace.quest_flag(0), "0 is incomplete")
    T.assert_false(QuestLogSpace.quest_flag(nil), "nil is incomplete")
end

function M.test_condition_and_guard_references_are_route_relevant()
    local ops = {
        op_with({
            { type = "Condition", payload = { role = "Completion",
                condition = { type = "Not", payload = { type = "QuestRewarded", payload = 30 } } } },
            { type = "Travel", payload = {},
                guard = { type = "All", payload = {
                    { type = "QuestAccepted", payload = 31 },
                    { type = "ObjectiveComplete", payload = { 32, 1 } },
                } } },
        }),
    }
    local entries = {
        { index = 1, quest_id = 30, is_complete = 0 },
        { index = 2, quest_id = 31, is_complete = 0 },
        { index = 3, quest_id = 32, is_complete = 0 },
    }
    T.assert_equal(QuestLogSpace.select_sacrificial_quest(entries, ops, 1), nil,
        "quests referenced via conditions and guards are route-relevant")
end

function M.test_operations_before_current_are_not_route_relevant()
    local ops = {
        op_with({ accept(40) }),
        op_with({ accept(41) }),
    }
    local entries = { { index = 1, quest_id = 40, is_complete = 0 } }
    local pick = QuestLogSpace.select_sacrificial_quest(entries, ops, 2)
    T.assert_equal(pick and pick.quest_id, 40,
        "a quest only referenced BEFORE the current op is sacrificial")
end

-- ======================================================================
-- End-to-end: module handler wiring
-- ======================================================================

local function with_quests_mock(log_rows, fn)
    local prev = _G.core.quests
    local calls = { selected = {}, set_abandon = 0, abandon = 0 }
    _G.core.quests = {
        get_num_quest_log_entries = function() return #log_rows end,
        get_quest_log_title = function(i) return log_rows[i] end,
        select_quest_log_entry = function(i) calls.selected[#calls.selected + 1] = i end,
        set_abandon_quest = function() calls.set_abandon = calls.set_abandon + 1 end,
        abandon_quest = function() calls.abandon = calls.abandon + 1 end,
    }
    local ok, err = pcall(fn, calls)
    _G.core.quests = prev
    if not ok then error(err) end
end

local function make_module_with_executor(ops, action_type)
    local bb, bus = Blackboard:new(), EventBus:new()
    local q = QuestingModule:new(bb, bus)
    local logged = {}
    q._executor = {
        _profile = { operations = ops },
        _current_operation_idx = 1,
        _current_action_idx = 1,
        _log_event = function(_self, event, data)
            logged[#logged + 1] = { event = event, data = data or {} }
        end,
    }
    if action_type then
        ops[1].actions[1].type = action_type
    end
    return q, bus, logged
end

function M.test_handler_abandons_and_logs()
    local ops = { op_with({ accept(10) }) }
    with_quests_mock({
        { quest_id = 20, is_complete = 0 },
        { quest_id = 10, is_complete = 0 },
    }, function(calls)
        local _, bus, logged = make_module_with_executor(ops)
        bus:publish("game:ui_error", { message = "Your quest log is full." })
        T.assert_equal(#calls.selected, 1, "exactly one log entry selected for abandon")
        T.assert_equal(calls.selected[1], 1, "the non-route quest's log index is selected")
        T.assert_equal(calls.set_abandon, 1, "set_abandon_quest must be called")
        T.assert_equal(calls.abandon, 1, "abandon_quest must be called")
        T.assert_equal(#logged, 1, "one event logged")
        T.assert_equal(logged[1].event, "quest_abandoned_for_space", "event name")
        T.assert_equal(logged[1].data.quest_id, 20, "event carries the abandoned quest id")
    end)
end

function M.test_handler_unrecoverable_when_all_route_relevant()
    local ops = {
        op_with({ accept(10) }),
        op_with({ turnin(20) }),
    }
    with_quests_mock({
        { quest_id = 10, is_complete = 0 },
        { quest_id = 20, is_complete = 0 },
    }, function(calls)
        local _, bus, logged = make_module_with_executor(ops)
        bus:publish("game:ui_error", { message = "Your quest log is full." })
        T.assert_equal(calls.abandon, 0, "route-relevant-only log must abandon nothing")
        T.assert_equal(#logged, 1, "one event logged")
        T.assert_equal(logged[1].event, "quest_log_full_unrecoverable", "event name")
    end)
end

function M.test_handler_ignores_error_outside_accept()
    local ops = { op_with({ { type = "Travel", payload = {} } }) }
    with_quests_mock({
        { quest_id = 20, is_complete = 0 },
    }, function(calls)
        local _, bus, logged = make_module_with_executor(ops)
        bus:publish("game:ui_error", { message = "Your quest log is full." })
        T.assert_equal(calls.abandon, 0, "only an in-flight AcceptQuest may trigger an abandon")
        T.assert_equal(#logged, 0, "no event when the error is not ours to handle")
    end)
end

local tests = {
    test_selection_prefers_nonroute_incomplete = M.test_selection_prefers_nonroute_incomplete,
    test_numeric_flag_normalization = M.test_numeric_flag_normalization,
    test_condition_and_guard_references_are_route_relevant = M.test_condition_and_guard_references_are_route_relevant,
    test_operations_before_current_are_not_route_relevant = M.test_operations_before_current_are_not_route_relevant,
    test_handler_abandons_and_logs = M.test_handler_abandons_and_logs,
    test_handler_unrecoverable_when_all_route_relevant = M.test_handler_unrecoverable_when_all_route_relevant,
    test_handler_ignores_error_outside_accept = M.test_handler_ignores_error_outside_accept,
}

function M.run()
    local names = {}
    for name in pairs(tests) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(tests[name])
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
