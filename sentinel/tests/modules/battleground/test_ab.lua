local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local AB = require("modules/battleground/states/ab")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local sm = AB:new(bus, bb, "ALLIANCE")
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "OPENING_SPLIT")
    bb:set("bg.nav_result", "arrived")
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "PRIMARY_NODE_ASSAULT")
    bb:set("bg.retreat_requested", true)
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "RETREAT")
end

return M
