local TestUtil = require("tests/test_util")
local Tracker = require("modules/quest/tracker")

local M = {}

function M.run()
    local previous_core = _G.core
    local values = {
        { is_header = false, quest_id = 42, title = "Test Quest", level = 10, is_complete = false },
    }
    _G.core = {
        quests = {
            get_num_quest_log_entries = function() return 1 end,
            get_quest_log_title = function(index) return values[index] end,
            get_num_quest_leader_boards = function() return 1 end,
            get_quest_log_leader_board = function() return "Wolves slain: 2/5" end,
        },
    }

    local data = {}
    local bb = {
        get = function(_, _, default) return default end,
        set = function(_, key, value) data[key] = value end,
    }
    local tracker = Tracker.new(bb)
    TestUtil.assert_true(tracker:refresh(1000))
    TestUtil.assert_equal(1, tracker:count())
    TestUtil.assert_equal("Wolves slain: 2/5", tracker:get(42).objectives[1].text)
    TestUtil.assert_equal(1, data["module.quest.active_count"])

    _G.core = previous_core
end

return M
