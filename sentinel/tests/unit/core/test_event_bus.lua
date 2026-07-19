-- sentinel/tests/unit/core/test_event_bus.lua
-- EventBus unit tests

local Helpers = require("tests.harness.test_helpers")

local function run_tests()
    print("=== Core EventBus Tests ===")

    Helpers.setup()

    local EventBus = require("core/event_bus")

    -- Test 1: Subscribe and publish
    print("Test 1: Subscribe and publish")
    local bus = EventBus:new()
    local received = nil
    local token = bus:subscribe("test.event", function(payload)
        received = payload
    end)
    bus:publish("test.event", { value = 42 })
    Helpers.assert_not_nil(received, "Should receive published event")
    Helpers.assert_equal(received.value, 42, "Should receive payload")
    print("  PASS")

    -- Test 2: Multiple subscribers
    print("Test 2: Multiple subscribers")
    local received1, received2 = nil, nil
    bus:subscribe("multi.event", function(p) received1 = p end)
    bus:subscribe("multi.event", function(p) received2 = p end)
    bus:publish("multi.event", { data = "test" })
    Helpers.assert_equal(received1.data, "test", "Subscriber 1 should receive")
    Helpers.assert_equal(received2.data, "test", "Subscriber 2 should receive")
    print("  PASS")

    -- Test 3: Unsubscribe
    print("Test 3: Unsubscribe")
    local count = 0
    local token2 = bus:subscribe("unsub.event", function() count = count + 1 end)
    bus:publish("unsub.event", {})
    Helpers.assert_equal(count, 1, "Should have fired once")
    bus:unsubscribe(token2)
    bus:publish("unsub.event", {})
    Helpers.assert_equal(count, 1, "Should not fire after unsubscribe")
    print("  PASS")

    -- Test 4: Publish to empty topic
    print("Test 4: Publish to empty topic")
    bus:publish("empty.topic", { x = 1 }) -- Should not error
    print("  PASS")

    -- Test 5: Multiple events independent
    print("Test 5: Multiple events independent")
    local a, b = 0, 0
    bus:subscribe("event.a", function() a = a + 1 end)
    bus:subscribe("event.b", function() b = b + 1 end)
    bus:publish("event.a", {})
    bus:publish("event.a", {})
    bus:publish("event.b", {})
    Helpers.assert_equal(a, 2, "Event A should fire twice")
    Helpers.assert_equal(b, 1, "Event B should fire once")
    print("  PASS")

    -- Test 6: Priority ordering
    print("Test 6: Priority ordering")
    local order = {}
    bus:subscribe("priority.test", function() table.insert(order, 1) end, 10) -- low priority
    bus:subscribe("priority.test", function() table.insert(order, 2) end, 1)  -- high priority
    bus:subscribe("priority.test", function() table.insert(order, 3) end, 5)  -- medium priority
    bus:publish("priority.test", {})
    Helpers.assert_equal(order[1], 2, "High priority first")
    Helpers.assert_equal(order[2], 3, "Medium priority second")
    Helpers.assert_equal(order[3], 1, "Low priority last")
    print("  PASS")

    Helpers.teardown()
    print("=== All Core EventBus Tests PASSED ===\n")
end

run_tests()