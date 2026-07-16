local TestUtil = require("tests/test_util")
local Engine = require("modules/quest/engine")

local M = {}

function M.run()
    local bb = {
        get = function(_, _, default) return default end,
        set = function() end,
    }
    
    local engine = Engine.new(bb)
    TestUtil.assert_not_nil(engine, "engine should be constructable")
    TestUtil.assert_equal(engine:get_active_quests(), {}, "no quests when empty blackboard")
    
    -- Test can_turn_in with empty tracker
    TestUtil.assert_false(engine:can_turn_in(999), "cannot turn in non-existent quest")
end

return M