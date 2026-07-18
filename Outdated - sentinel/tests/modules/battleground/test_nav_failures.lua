local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local NavController = require("modules/battleground/nav_controller")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local states = {
        { "failed", { state = "failed", destination = { x = 5, y = 5, z = 0 } } },
    }
    local nav_adapter = {
        move_to = function() return true end,
        plan_route = function() return true end,
        stop = function() return true end,
        poll = function()
            local current = table.remove(states, 1)
            return current[1], current[2]
        end,
    }

    local nav = NavController:new(bus, bb, nav_adapter)
    bb:set("system.now_ms", 1000)
    nav:issue_move_to({ x = 5, y = 5, z = 0 }, { source = "bg", objective_id = "FAIL_TEST" })
    nav:update(bb)
    T.assert_equal(bb:get("bg.nav_result"), "failed")
    T.assert_equal(bb:get("nav.last_failure_count"), 1)
    T.assert_equal(bb:get("nav.failure_count"), 1)
    T.assert_equal(bb:get("nav.command"), nil)

    local idle_bb = Blackboard:new()
    local idle_states = {
        { "idle", { state = "idle" } },
    }
    local idle_adapter = {
        move_to = function() return true end,
        plan_route = function() return true end,
        stop = function() return true end,
        poll = function()
            local current = table.remove(idle_states, 1)
            return current[1], current[2]
        end,
    }

    local idle_nav = NavController:new(bus, idle_bb, idle_adapter)
    idle_bb:set("system.now_ms", 1000)
    idle_nav:issue_move_to({ x = 9, y = 9, z = 0 }, { source = "bg", objective_id = "IDLE_TEST" })
    idle_bb:set("system.now_ms", 1800)
    idle_nav:update(idle_bb)
    T.assert_equal(idle_bb:get("nav.command"), nil)
    T.assert_equal(idle_bb:get("nav.last_idle_abort_reason"), "movement_idle_before_start")
end

return M
