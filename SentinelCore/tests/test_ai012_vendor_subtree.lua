local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local VendorSubTree = require("bt/VendorSubTree")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    local update_calls = 0
    local is_complete_val = false
    local mock_vendor = {
        update = function()
            update_calls = update_calls + 1
            return true
        end,
        is_complete = function()
            return is_complete_val
        end,
    }

    local tree = VendorSubTree.build(bb, mock_vendor)

    -- Test 1: FAILURE when bags have space and durability ok
    bb:set("player.in_combat", false)
    bb:set("inventory.free_slots", 20)
    bb:set("inventory.durability_pct", 0.90)
    assert(tree:tick() == S.FAILURE, "should fail when no vendor needed")

    -- Test 2: FAILURE when in combat
    bb:set("player.in_combat", true)
    bb:set("inventory.free_slots", 1)
    assert(tree:tick() == S.FAILURE, "should fail when in combat")

    -- Test 3: RUNNING when bags nearly full
    bb:set("player.in_combat", false)
    bb:set("inventory.free_slots", 2)
    tree:reset()
    assert(tree:tick() == S.RUNNING, "should run when bags near full")
    assert(update_calls > 0, "should have called vendor update")

    -- Test 4: RUNNING when durability low
    bb:set("inventory.free_slots", 20)
    bb:set("inventory.durability_pct", 0.15)
    update_calls = 0
    tree:reset()
    assert(tree:tick() == S.RUNNING, "should run when durability low")

    -- Test 5: SUCCESS when vendor trip completes
    bb:set("inventory.free_slots", 2)
    is_complete_val = true
    tree:reset()
    assert(tree:tick() == S.SUCCESS, "should succeed when vendor trip complete")

    -- Test 6: FAILURE on timeout (120s)
    is_complete_val = false
    tree:reset()
    now = now + 0.1
    tree:tick()  -- start the timeout
    now = now + 130
    assert(tree:tick() == S.FAILURE, "should fail after timeout")

    env.restore()
    return true
end

return M
