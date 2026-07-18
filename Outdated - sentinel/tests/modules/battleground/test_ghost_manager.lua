local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local GhostManager = require("modules/battleground/ghost_manager")
local T = require("tests/test_util")

local M = {}

function M.run()
    local release_calls = 0
    local nav_stop_calls = 0
    core = {
        input = {
            release_spirit = function()
                release_calls = release_calls + 1
                return true
            end,
        },
    }

    local bb = Blackboard:new()
    bb:set("system.now_ms", 1000)
    bb:set("module.bg.ghost_mode", "release_wait")
    bb:set("player.is_dead", true)
    bb:set("player.is_ghost", false)
    bb:set("bg.sensor.in_bg", true)

    local nav = {
        stop = function()
            nav_stop_calls = nav_stop_calls + 1
        end,
    }

    local manager = GhostManager:new(EventBus:new(), bb, nav)
    manager:initialize()
    manager:update()
    T.assert_equal(release_calls, 1)
    T.assert_true(bb:get("bg.ghost.active", false))

    bb:set("system.now_ms", 2000)
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", true)
    manager:update()
    T.assert_equal(nav_stop_calls, 1)
    T.assert_equal(bb:get("bg.ghost.action"), "wait_spirit_healer")
    T.assert_true(manager:is_blocking_strategy())
end

return M
