local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local VendorService = require("services/VendorService")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    -- VendorService uses a state-machine vendor service:
    -- get_state(), is_active(), start(ctx), update(), reset()
    local vendor_state = "idle"
    local start_calls = 0
    local update_calls = 0
    local mock_vendor = setmetatable({
        _blackboard = bb,
        get_state = function() return vendor_state end,
        is_active = function()
            return vendor_state == "active" or vendor_state == "running"
        end,
        start = function(_, ctx)
            start_calls = start_calls + 1
            vendor_state = "active"
            return true
        end,
        update = function()
            update_calls = update_calls + 1
        end,
        reset = function()
            vendor_state = "idle"
        end,
    }, { __index = VendorService })

    local tree = mock_vendor:build()

    -- Test 1: FAILURE when bags have space and durability ok
    bb:set("player.in_combat", false)
    bb:set("inventory.free_slots", 20)
    bb:set("player.durability_pct", 0.90)
    bb:set("context.ui_map_id", 0)
    assert(tree:tick() == S.FAILURE, "should fail when no vendor needed")

    -- Test 2: FAILURE when in combat
    bb:set("player.in_combat", true)
    bb:set("inventory.free_slots", 1)
    assert(tree:tick() == S.FAILURE, "should fail when in combat")

    -- Test 3: RUNNING when bags nearly full (triggers start then active)
    bb:set("player.in_combat", false)
    bb:set("inventory.free_slots", 2)
    bb:set("player.durability_pct", 0.90)
    vendor_state = "idle"
    start_calls = 0
    tree:reset()
    now = now + 0.1
    assert(tree:tick() == S.RUNNING, "should run when bags near full")
    assert(start_calls > 0, "should have called vendor start")

    -- Test 4: RUNNING when durability low
    bb:set("inventory.free_slots", 20)
    bb:set("player.durability_pct", 0.15)
    vendor_state = "idle"
    start_calls = 0
    tree:reset()
    now = now + 0.1
    assert(tree:tick() == S.RUNNING, "should run when durability low")

    -- Test 5: RUNNING while vendor is active (updating)
    vendor_state = "active"
    update_calls = 0
    tree:reset()
    now = now + 0.1
    bb:set("inventory.free_slots", 2)
    bb:set("player.durability_pct", 0.90)
    assert(tree:tick() == S.RUNNING, "should run while vendor active")

    -- Test 6: SUCCESS when vendor trip completes
    vendor_state = "completed"
    tree:reset()
    now = now + 0.1
    assert(tree:tick() == S.SUCCESS, "should succeed when vendor trip complete")

    -- Test 7: FAILURE on timeout (120s)
    vendor_state = "active"
    tree:reset()
    now = now + 0.1
    tree:tick()  -- start the timeout
    now = now + 130
    assert(tree:tick() == S.FAILURE, "should fail after timeout")

    env.restore()
    return true
end

return M
