local TestUtil = require("tests/test_util")
local Interactions = require("modules/quest/interactions")

local M = {}

function M.run()
    local previous_core = _G.core
    _G.core = {
        quests = {
            is_gossip_frame_shown = function() return true end,
            select_gossip_available_quest = function(id) end,
            select_gossip_active_quest = function(id) end,
            accept_quest = function() end,
            complete_quest = function() end,
            get_quest_reward = function(index) end,
            close_gossip = function() end,
        },
    }

    TestUtil.assert_true(Interactions.is_open())
    TestUtil.assert_true(Interactions.accept_available(7))
    TestUtil.assert_true(Interactions.complete_active(7, 2))
    TestUtil.assert_true(Interactions.close())

    _G.core = previous_core
end

return M
