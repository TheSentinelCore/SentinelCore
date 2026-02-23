local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local DeathRecoverySubTree = require("bt/DeathRecoverySubTree")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    local nav_calls = {}
    local mock_nav = {
        move_to = function(_, pos)
            nav_calls[#nav_calls + 1] = { action = "move_to", pos = pos }
        end,
        stop = function(_)
            nav_calls[#nav_calls + 1] = { action = "stop" }
        end,
    }

    local tree = DeathRecoverySubTree.build(bb, mock_nav)

    -- Test 1: FAILURE when alive
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", false)
    assert(tree:tick() == S.FAILURE, "should fail when alive")

    -- Test 2: RUNNING when dead (waiting to release)
    bb:set("player.is_dead", true)
    bb:set("player.is_ghost", false)
    assert(tree:tick() == S.RUNNING, "should be running when dead")

    -- Test 3: RUNNING when ghost (corpse run)
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", true)
    bb:set("player.corpse_position", { x = 100, y = 200, z = 0 })
    bb:set("player.position", { x = 50, y = 200, z = 0 })
    now = now + 5
    assert(tree:tick() == S.RUNNING, "should be running during corpse run")

    -- Test 4: SUCCESS when resurrected
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", false)
    tree:reset()
    assert(tree:tick() == S.FAILURE, "should fail once alive again")

    env.restore()
    return true
end

return M
