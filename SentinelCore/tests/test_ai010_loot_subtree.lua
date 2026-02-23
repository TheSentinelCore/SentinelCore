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
    local mock_nav = {
        move_to = function(_, pos)
            nav_calls[#nav_calls + 1] = { action = "move_to", pos = pos }
        end,
    }

    local tree = LootSubTree.build(bb, mock_nav)

    -- Test 1: FAILURE when no lootables
    bb:set("player.in_combat", false)
    bb:set("loot.lootable_objects", nil)
    assert(tree:tick() == S.FAILURE, "should fail with no lootables")

    -- Test 2: FAILURE when in combat
    local lootable = TU.mock_object({ position = { x = 10, y = 0, z = 0 } })
    bb:set("loot.lootable_objects", { lootable })
    bb:set("player.in_combat", true)
    assert(tree:tick() == S.FAILURE, "should fail when in combat")

    -- Test 3: RUNNING when lootable out of range (navigate)
    bb:set("player.in_combat", false)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    tree:reset()
    local status = tree:tick()
    assert(status == S.RUNNING, "should be running when navigating to loot")
    assert(#nav_calls > 0, "should have issued nav command")

    -- Test 4: RUNNING when in range (looting)
    bb:set("player.position", { x = 9, y = 0, z = 0 })
    tree:reset()
    now = now + 0.1
    status = tree:tick()
    assert(status == S.RUNNING, "should be running while looting")

    -- Test 5: Timeout triggers FAILURE after 8s
    tree:reset()
    now = now + 10
    status = tree:tick()
    -- After reset and 10s advance, lootables still there means timeout on next tick
    -- The timeout starts fresh after reset, so first tick after reset starts the timer
    -- Need to tick multiple times past the 8s mark
    local first_tick_time = now
    now = first_tick_time + 9
    status = tree:tick()
    assert(status == S.FAILURE, "should fail after timeout")

    env.restore()
    return true
end

return M
