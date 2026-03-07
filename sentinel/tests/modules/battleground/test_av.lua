local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local AV = require("modules/battleground/states/av")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local sm = AV:new(bus, bb, "ALLIANCE")
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "OPENING_PUSH")
    bb:set("bg.nav_result", "arrived")
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "OUTER_OBJECTIVE")
    bb:set("bg.retreat_requested", true)
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "RETREAT")
end

return M
