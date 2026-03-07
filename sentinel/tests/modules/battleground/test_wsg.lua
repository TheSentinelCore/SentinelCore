local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local WSG = require("modules/battleground/states/wsg")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local sm = WSG:new(bus, bb, "HORDE")
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "MID_CONTROL")
    bb:set("bg.nav_result", "arrived")
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "ENEMY_FLAG_ROOM")
    bb:set("bg.retreat_requested", true)
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "RETREAT")
end

return M
