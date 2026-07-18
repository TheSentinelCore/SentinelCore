local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local NavController = require("modules/battleground/nav_controller")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local states = {
        { "moving", { state = "moving", destination = { x = 1, y = 2, z = 3 }, path_count = 3 } },
        { "arrived", { state = "arrived", destination = { x = 1, y = 2, z = 3 } } },
    }
    local nav_adapter = {
        move_to = function() return true end,
        follow_path = function() return true end,
        plan_route = function() return true end,
        stop = function() return true end,
        poll = function()
            local current = table.remove(states, 1)
            return current[1], current[2]
        end,
    }

    local nav = NavController:new(bus, bb, nav_adapter)
    bb:set("system.now_ms", 1000)
    nav:issue_follow_path({
        { x = 0, y = 0, z = 0 },
        { x = 1, y = 2, z = 3 },
    }, { source = "bg", objective_id = "TEST" })
    nav:update(bb)
    T.assert_equal(bb:get("nav.state"), "moving")
    T.assert_equal(bb:get("nav.command"), "follow_path")
    bb:set("system.now_ms", 1300)
    nav:update(bb)
    T.assert_equal(bb:get("bg.nav_result"), "arrived")
end

return M
