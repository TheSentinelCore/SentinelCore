local TestUtil = require("tests/test_util")
local Questie = require("modules/quest/questie_adapter")

local M = {}

function M.run()
    -- Test when Questie is not available
    local previous_core = _G.core
    _G.core = {}

    TestUtil.assert_false(Questie.is_ready(), "should return false when Questie not loaded")
    TestUtil.assert_nil(Questie.query_quest(42, "title"), "should return nil when Questie not loaded")
    TestUtil.assert_nil(Questie.is_quest_doable(42), "should return nil when Questie not loaded")

    -- Test when Questie is available but is_ready returns false
    _G.core = {
        addons = {
            questie = {
                is_ready = function() return false end,
                query_quest_single = function() return nil end,
            }
        }
    }

    TestUtil.assert_false(Questie.is_ready(), "should return false when Questie not ready")

    -- Test when Questie is fully available
    _G.core = {
        addons = {
            questie = {
                is_ready = function() return true end,
                get_quest_npc_ids = function() return { 123, 456 } end,
                get_quest_ids = function() return { 42, 43 } end,
                query_quest_single = function(quest_id, key)
                    if quest_id == 42 then
                        if key == "title" then return "Test Quest" end
                        if key == "level" then return 10 end
                    end
                    return nil
                end,
                is_quest_doable = function(quest_id)
                    return quest_id == 42
                end,
                is_quest_complete = function(quest_id)
                    return quest_id == 99
                end,
            }
        }
    }

    TestUtil.assert_true(Questie.is_ready(), "should return true when Questie ready")
    TestUtil.assert_equal(Questie.query_quest(42, "title"), "Test Quest", "query_quest should return title")
    TestUtil.assert_true(Questie.is_quest_doable(42), "quest 42 should be doable")
    TestUtil.assert_false(Questie.is_quest_doable(99), "quest 99 should not be doable")
    TestUtil.assert_false(Questie.is_quest_complete(42), "quest 42 should not be complete")
    TestUtil.assert_true(Questie.is_quest_complete(99), "quest 99 should be complete")

    local npc_ids = Questie.get_active_npc_ids()
    TestUtil.assert_equal(type(npc_ids), "table", "get_active_npc_ids should return table")
    TestUtil.assert_equal(#npc_ids, 2, "should have 2 NPC IDs")

    _G.core = previous_core
end

return M