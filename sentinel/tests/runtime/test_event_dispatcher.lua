-- sentinel/tests/runtime/test_event_dispatcher.lua
-- Tests for runtime/event_dispatcher.lua

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")
local Mock = require("tests/harness/mocks/sylvannas_api")

local M = {}

function M.run()
    print("=== Event Dispatcher Tests ===")

    -- Set up mock Sylvannas core
    Mock.setup_globals()

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local bb = Blackboard:new()
    local eb = EventBus:new()
    local EventDispatcher = require("runtime/event_dispatcher")
    local ed = EventDispatcher:new(eb, bb)
    T.assert_not_nil(ed, "EventDispatcher instance should not be nil")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Start and stop dispatcher gracefully
    -- =====================================================================
    print("Test 2: Start and stop dispatcher")
    local bb2 = Blackboard:new()
    local eb2 = EventBus:new()
    local ed2 = EventDispatcher:new(eb2, bb2)
    -- Should not error when Sylvannas event bus doesn't have the events
    ed2:start()
    T.assert_true(true, "start should not error")
    ed2:stop()
    T.assert_true(true, "stop should not error")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Start is idempotent
    -- =====================================================================
    print("Test 3: Start is idempotent")
    local bb3 = Blackboard:new()
    local eb3 = EventBus:new()
    local ed3 = EventDispatcher:new(eb3, bb3)
    ed3:start()
    ed3:start()  -- Second start should be no-op
    ed3:stop()
    T.assert_true(true, "double start should not error")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Stop is idempotent
    -- =====================================================================
    print("Test 4: Stop is idempotent")
    local bb4 = Blackboard:new()
    local eb4 = EventBus:new()
    local ed4 = EventDispatcher:new(eb4, bb4)
    ed4:stop()  -- Stop without start
    ed4:stop()  -- Double stop
    T.assert_true(true, "double stop should not error")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Subscribe to runtime events and receive notifications
    -- =====================================================================
    print("Test 5: Subscribe to runtime events")
    local bb5 = Blackboard:new()
    local eb5 = EventBus:new()
    local ed5 = EventDispatcher:new(eb5, bb5)
    ed5:start()

    local received = {}
    local token = ed5:on_runtime_event("kill_event", function(payload)
        table.insert(received, payload)
    end)
    T.assert_not_nil(token, "subscription token should not be nil")
    T.assert_true(type(token) == "string", "token should be a string")

    -- Manually trigger the handler
    ed5:_handle_unit_combat(12345, 100, 200, 30)
    T.assert_equal(#received, 1, "should have received 1 kill_event")
    T.assert_equal(received[1].creature_entry, 12345, "creature entry should match")
    T.assert_equal(received[1].position.x, 100, "x should match")
    T.assert_equal(received[1].position.y, 200, "y should match")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Unsubscribe from runtime events
    -- =====================================================================
    print("Test 6: Unsubscribe from runtime events")
    local bb6 = Blackboard:new()
    local eb6 = EventBus:new()
    local ed6 = EventDispatcher:new(eb6, bb6)
    ed6:start()

    local count = 0
    local token6 = ed6:on_runtime_event("health_changed", function()
        count = count + 1
    end)

    -- Fire event
    ed6:_handle_unit_health("Player-1", 50, 100)
    T.assert_equal(count, 1, "handler should have been called once")

    -- Unsubscribe
    local removed = ed6:off_runtime_event(token6)
    T.assert_true(removed, "off_runtime_event should return true")

    -- Fire again - handler should not be called
    ed6:_handle_unit_health("Player-1", 25, 100)
    T.assert_equal(count, 1, "handler should not have been called after unsubscribe")

    -- Remove again should return false
    local removed2 = ed6:off_runtime_event(token6)
    T.assert_false(removed2, "second removal should return false")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Event dispatch with proper payloads
    -- =====================================================================
    print("Test 7: Event dispatch payloads")
    local bb7 = Blackboard:new()
    local eb7 = EventBus:new()
    local ed7 = EventDispatcher:new(eb7, bb7)
    ed7:start()

    local events = {}
    ed7:on_runtime_event("health_changed", function(p) table.insert(events, { name = "health_changed", p = p }) end)
    ed7:on_runtime_event("inventory_changed", function(p) table.insert(events, { name = "inventory_changed", p = p }) end)
    ed7:on_runtime_event("zone_entered", function(p) table.insert(events, { name = "zone_entered", p = p }) end)
    ed7:on_runtime_event("death_event", function(p) table.insert(events, { name = "death_event", p = p }) end)
    ed7:on_runtime_event("kill_event", function(p) table.insert(events, { name = "kill_event", p = p }) end)

    -- Trigger handlers manually
    ed7:_handle_unit_health("Player-1", 75, 100)
    ed7:_handle_bag_update(5)
    ed7:_handle_player_entering_world()
    ed7:_handle_player_death()
    ed7:_handle_unit_combat(67890, 10, 20, 30)

    T.assert_equal(#events, 5, "should have received 5 events")

    -- Check health_changed payload
    local hc = events[1]
    T.assert_equal(hc.name, "health_changed")
    T.assert_equal(hc.p.guid, "Player-1")
    T.assert_equal(hc.p.health, 75)
    T.assert_equal(hc.p.max_health, 100)

    -- Check inventory_changed payload
    local inv = events[2]
    T.assert_equal(inv.name, "inventory_changed")
    T.assert_equal(inv.p.bag_id, 5)

    -- Check zone_entered payload
    local zone = events[3]
    T.assert_equal(zone.name, "zone_entered")
    -- zone may have nil fields since mock doesn't have get_zone_name

    -- Check death_event payload
    local death = events[4]
    T.assert_equal(death.name, "death_event")
    -- position may be nil or have mock data

    -- Check kill_event payload
    local kill = events[5]
    T.assert_equal(kill.name, "kill_event")
    T.assert_equal(kill.p.creature_entry, 67890)
    T.assert_equal(kill.p.position.x, 10)
    T.assert_equal(kill.p.position.y, 20)

    print("  PASS")

    -- =====================================================================
    -- Test 8: Multiple subscribers to same event
    -- =====================================================================
    print("Test 8: Multiple subscribers to same event")
    local bb8 = Blackboard:new()
    local eb8 = EventBus:new()
    local ed8 = EventDispatcher:new(eb8, bb8)
    ed8:start()

    local call_a = 0
    local call_b = 0
    ed8:on_runtime_event("health_changed", function() call_a = call_a + 1 end)
    ed8:on_runtime_event("health_changed", function() call_b = call_b + 1 end)

    ed8:_handle_unit_health("Test", 100, 100)
    T.assert_equal(call_a, 1, "handler a should be called")
    T.assert_equal(call_b, 1, "handler b should be called")

    -- Fire again
    ed8:_handle_unit_health("Test", 50, 100)
    T.assert_equal(call_a, 2, "handler a should be called twice")
    T.assert_equal(call_b, 2, "handler b should be called twice")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Subscription token uniqueness
    -- =====================================================================
    print("Test 9: Subscription token uniqueness")
    local bb9 = Blackboard:new()
    local eb9 = EventBus:new()
    local ed9 = EventDispatcher:new(eb9, bb9)
    ed9:start()

    local t1 = ed9:on_runtime_event("quest_accepted", function() end)
    local t2 = ed9:on_runtime_event("quest_completed", function() end)
    local t3 = ed9:on_runtime_event("quest_accepted", function() end)

    T.assert_false(t1 == t2, "tokens should be different (t1 vs t2)")
    T.assert_false(t1 == t3, "tokens should be different (t1 vs t3)")
    T.assert_false(t2 == t3, "tokens should be different (t2 vs t3)")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Handle Sylvannas event dispatch via core.event_bus
    -- =====================================================================
    print("Test 10: Core event bus integration")
    local bb10 = Blackboard:new()
    local eb10 = EventBus:new()
    local ed10 = EventDispatcher:new(eb10, bb10)

    -- Set up core.event_bus with Sylvannas-style API
    local sylvannas_eb = {
        _subs = {},
        on = function(self, event, handler)
            if not self._subs[event] then
                self._subs[event] = {}
            end
            table.insert(self._subs[event], handler)
            return event .. "_token"
        end,
        off = function(self, token)
            return true
        end,
    }
    _G.core.event_bus = sylvannas_eb

    local captured = {}
    ed10:on_runtime_event("quest_accepted", function(p) table.insert(captured, p) end)

    ed10:start()

    -- Verify subscription tokens were stored
    T.assert_equal(#ed10._sylvannas_tokens, 6, "should have 6 Sylvannas subscription tokens")

    -- Simulate a Sylvannas event being triggered
    -- FIX: Our ed10 subscribed via pcall(core_eb.on, core_eb, "QUEST_LOG_UPDATE", handler)
    -- So we need to trigger the handler that was passed to sylvannas_eb.on
    local quest_handlers = sylvannas_eb._subs["QUEST_LOG_UPDATE"]
    T.assert_not_nil(quest_handlers, "QUEST_LOG_UPDATE should have a handler")
    T.assert_equal(#quest_handlers, 1, "should have 1 QUEST_LOG_UPDATE handler")

    -- Trigger the handler
    quest_handlers[1]()
    T.assert_equal(#captured, 1, "should have captured 1 quest_accepted event")

    ed10:stop()
    T.assert_equal(#ed10._sylvannas_tokens, 0, "tokens should be cleared after stop")
    print("  PASS")

    -- Clean up
    Mock.reset()

    print("\n=== All EventDispatcher Tests PASSED ===")
end

return M
