local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local EOTS = require("modules/battleground/states/eots")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local sm = EOTS:new(bus, bb, "HORDE")
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "MID_RACE")
    bb:set("bg.nav_result", "arrived")
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "PRIMARY_TOWER_ASSAULT")
    bb:set("bg.retreat_requested", true)
    sm:update(bb)
    T.assert_equal(sm:get_current_state(), "RETREAT")
end

return M
