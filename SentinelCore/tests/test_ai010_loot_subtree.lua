local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local LootSubTree = require("bt/LootSubTree")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    local nav_calls = {}
    local nav_moving = false
    local mock_nav = {
        move_to = function(_, pos)
            nav_calls[#nav_calls + 1] = { action = "move_to", pos = pos }
            nav_moving = true
        end,
        is_moving = function() return nav_moving end,
        stop = function() nav_moving = false end,
        soft_repath = function(_, pos, cb)
            nav_calls[#nav_calls + 1] = { action = "soft_repath", pos = pos }
            if cb then cb(true) end
        end,
    }

    local tree = LootSubTree.build(bb, mock_nav)

    -- Test 1: FAILURE when no pending loot target
    bb:set("player.in_combat", false)
    bb:set("loot.pending_target", nil)
    assert(tree:tick() == S.FAILURE, "should fail with no loot target")

    -- Test 2: FAILURE when in combat
    local lootable = TU.mock_object({ position = { x = 10, y = 0, z = 0 } })
    bb:set("loot.pending_target", lootable)
    bb:set("player.in_combat", true)
    assert(tree:tick() == S.FAILURE, "should fail when in combat")

    -- Test 3: RUNNING when lootable out of range (navigate)
    bb:set("player.in_combat", false)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    tree:reset()
    local status = tree:tick()
    assert(status == S.RUNNING, "should be running when navigating to loot")
    assert(#nav_calls > 0, "should have issued nav command")

    -- Test 4: SUCCESS/FAILURE when in range (interact and clear)
    bb:set("player.position", { x = 9, y = 0, z = 0 })
    tree:reset()
    now = now + 0.1
    status = tree:tick()
    -- After interacting, pending_target is cleared. On next gate check it fails.
    -- The action returns SUCCESS after interact, so ReactiveSequence returns SUCCESS.
    -- But on the NEXT tick, gate fails because pending_target is nil.
    -- On this tick: gate passes (pending_target still set at gate eval) → action interacts and clears → SUCCESS
    assert(bb:get("loot.pending_target") == nil, "should clear pending_target after loot")

    -- Test 5: Timeout triggers FAILURE after 10s
    bb:set("loot.pending_target", TU.mock_object({ position = { x = 100, y = 0, z = 0 } }))
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    tree:reset()
    now = now + 0.1
    tree:tick()  -- start the timeout, RUNNING (far away)
    now = now + 12
    status = tree:tick()
    assert(status == S.FAILURE, "should fail after timeout")

    env.restore()
    return true
end

return M
