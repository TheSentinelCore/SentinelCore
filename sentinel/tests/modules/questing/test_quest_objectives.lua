-- tests/modules/questing/test_quest_objectives.lua
-- Pins the real Sylvannas quest-log leader board contract, captured live from the
-- client on 2026-07-23:
--
--   core.quests.get_quest_log_leader_board(objective_idx, quest_log_idx)
--     -> { objective_type = "item", description = "Tough Wolf Meat: 0/8", is_completed = false }
--
-- It returns a TABLE, not a string, and the description carries NO parentheses.
-- ctx:is_objective_complete previously did string.match() on that value, which
-- threw "bad argument #1 to 'match' (string expected, got table)" and aborted the
-- whole executor tick, so every operation gated by an ObjectiveComplete condition
-- was dead. is_completed is authoritative -- reconcile, never count.

local RuntimeProfile = require("modules/questing/runtime_profile")
local T = require("tests/test_util")

local M = {}

--- Install a quest log shaped exactly like the live client's.
--- Index 1 is a zone HEADER (quest_id 0, zero leader boards); real quests follow.
local function mock_quest_log(boards)
    _G.core = _G.core or {}
    _G.core.quests = _G.core.quests or {}

    local titles = {
        { quest_id = 0, title = "Northshire Valley" },
        { quest_id = 7, title = "Kobold Camp Cleanup" },
        { quest_id = 33, title = "Wolves Across the Border" },
    }

    _G.core.quests.get_num_quest_log_entries = function() return #titles end
    _G.core.quests.get_quest_log_title = function(i) return titles[i] end
    _G.core.quests.get_num_quest_leader_boards = function(i)
        return boards[i] and #boards[i] or 0
    end
    _G.core.quests.get_quest_log_leader_board = function(objective_idx, quest_idx)
        local list = boards[quest_idx]
        return list and list[objective_idx] or nil
    end
    _G.core.quests.is_on_quest = function() return true end
    _G.core.quests.is_quest_flagged_completed = function() return false end
end

local function make_ctx()
    local profile = RuntimeProfile:new("test.json", true)
    return profile:create_context()
end

function M.test_incomplete_objective_does_not_throw()
    mock_quest_log({
        [3] = {
            { objective_type = "item", description = "Tough Wolf Meat: 0/8", is_completed = false },
        },
    })
    local ctx = make_ctx()
    -- Before the fix this raised: bad argument #1 to 'match' (string expected, got table)
    local ok, result = pcall(ctx.is_objective_complete, ctx, 33, 1)
    T.assert_true(ok, "is_objective_complete must not throw on a table leader board")
    T.assert_false(result, "0/8 is not complete")
end

function M.test_complete_objective_uses_is_completed()
    mock_quest_log({
        [3] = {
            { objective_type = "item", description = "Tough Wolf Meat: 8/8", is_completed = true },
        },
    })
    local ctx = make_ctx()
    T.assert_true(ctx:is_objective_complete(33, 1), "is_completed=true is authoritative")
end

--- The live description format is "Name: cur/need" -- no parentheses. The old
--- regex "%((%d+)/(%d+)%)" could never match it even if it had been a string.
function M.test_counts_parsed_without_parentheses()
    mock_quest_log({
        [3] = {
            -- is_completed deliberately stale/false so the count must decide
            { objective_type = "monster", description = "Wolves slain: 10/10", is_completed = false },
        },
    })
    local ctx = make_ctx()
    T.assert_true(ctx:is_objective_complete(33, 1), "10/10 must read as complete from the count")
end

function M.test_missing_objective_index_is_not_complete()
    mock_quest_log({
        [3] = {
            { objective_type = "item", description = "Tough Wolf Meat: 0/8", is_completed = false },
        },
    })
    local ctx = make_ctx()
    local ok, result = pcall(ctx.is_objective_complete, ctx, 33, 5)
    T.assert_true(ok, "out-of-range objective index must not throw")
    T.assert_false(result, "out-of-range objective is not complete")
end

return M
