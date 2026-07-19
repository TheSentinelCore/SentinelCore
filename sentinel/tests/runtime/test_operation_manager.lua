-- sentinel/tests/runtime/test_operation_manager.lua
-- Tests for SENT-8.4 Runtime Operation Manager

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== OperationManager Tests ===")

    -- Mock nav adapter
    local mock_nav = {
        _state = "idle",
        move_to = function(self, target)
            self._state = "moving"
            self._target = target
            return true, nil
        end,
        poll = function(self)
            if self._state == "moving" then
                self._state = "idle"
            end
        end,
        get_state = function(self)
            return self._state
        end,
        stop = function(self)
            self._state = "idle"
        end,
    }

    -- Mock core API
    local function setup_core()
        _G.core = _G.core or {}
        _G.core.input = {
            interact_unit = function(guid) return true end,
            use_item = function(id) return true end,
        }
        _G.core.player = {
            is_moving = function() return false end,
            is_dead = function() return false end,
            is_ghost = function() return false end,
        }
        _G.core.game_time = function() return 0 end
    end

    setup_core()

    package.loaded["runtime/operation_manager"] = nil
    local OperationManager = require("runtime/operation_manager")

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local bb1 = Blackboard:new()
    local eb1 = EventBus:new()
    local om1 = OperationManager:new(bb1, eb1, mock_nav)
    T.assert_not_nil(om1, "operation manager should be created")
    T.assert_equal(om1:get_status(), "idle", "default status should be idle")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Execute operation with empty actions
    -- =====================================================================
    print("Test 2: Execute operation with no actions")
    local bb2 = Blackboard:new()
    local om2 = OperationManager:new(bb2, EventBus:new(), mock_nav)
    local op2 = { id = "op-empty-1", actions = {} }
    local r2 = om2:execute_operation(op2)
    T.assert_equal(r2.status, "succeeded", "empty operation should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Execute invalid operation
    -- =====================================================================
    print("Test 3: Execute invalid operation")
    local bb3 = Blackboard:new()
    local om3 = OperationManager:new(bb3, EventBus:new(), mock_nav)
    local r3 = om3:execute_operation(nil)
    T.assert_equal(r3.status, "failed", "nil operation should fail")
    T.assert_not_nil(r3.error, "error should be set")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Execute operation with sync actions
    -- =====================================================================
    print("Test 4: Execute operation with sync actions")
    local bb4 = Blackboard:new()
    local om4 = OperationManager:new(bb4, EventBus:new(), mock_nav)
    local op4 = {
        id = "op-sync-1",
        actions = {
            { id = "a1", payload = { type = "set_variable", name = "var1", value = 10 } },
            { id = "a2", payload = { type = "set_variable", name = "var2", value = 20 } },
        },
    }
    local r4 = om4:execute_operation(op4)
    T.assert_equal(r4.status, "succeeded", "sync operation should succeed")
    T.assert_equal(bb4:get("module.runtime.var.var1"), 10, "var1 should be set")
    T.assert_equal(bb4:get("module.runtime.var.var2"), 20, "var2 should be set")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Track operation status in blackboard
    -- =====================================================================
    print("Test 5: Operation status tracking")
    local bb5 = Blackboard:new()
    local eb5 = EventBus:new()
    local om5 = OperationManager:new(bb5, eb5, mock_nav)

    local status_values = {}
    eb5:subscribe("operation_status_changed", function(payload)
        table.insert(status_values, { op_id = payload.op_id, status = payload.new_status })
    end)

    local op5 = {
        id = "op-status-1",
        actions = {
            { id = "a1", payload = { type = "set_variable", name = "x", value = 1 } },
        },
    }
    om5:execute_operation(op5)

    T.assert_equal(#status_values, 2, "should emit status changes")
    T.assert_equal(status_values[1].status, "active", "first status should be active")
    T.assert_equal(status_values[2].status, "completed", "second status should be completed")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Emit operation_completed event
    -- =====================================================================
    print("Test 6: operation_completed event")
    local bb6 = Blackboard:new()
    local eb6 = EventBus:new()
    local om6 = OperationManager:new(bb6, eb6, mock_nav)

    local completed_events = {}
    eb6:subscribe("operation_completed", function(payload)
        table.insert(completed_events, payload)
    end)

    local op6 = {
        id = "op-complete-1",
        actions = {
            { id = "a1", payload = { type = "set_variable", name = "y", value = 2 } },
        },
    }
    om6:execute_operation(op6)

    T.assert_equal(#completed_events, 1, "should emit operation_completed")
    T.assert_equal(completed_events[1].op_id, "op-complete-1", "event should have correct op_id")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Abort on operation failure
    -- =====================================================================
    print("Test 7: Abort on operation failure")
    local bb7 = Blackboard:new()
    local eb7 = EventBus:new()
    local om7 = OperationManager:new(bb7, eb7, mock_nav)

    local failed_events = {}
    eb7:subscribe("operation_failed", function(payload)
        table.insert(failed_events, payload)
    end)

    _G.core.input.interact_unit = function() error("NPC not found") end

    local op7 = {
        id = "op-fail-1",
        actions = {
            { id = "a1", payload = { type = "pickup_quest", npc_guid = "missing-npc" } },
        },
    }
    local r7 = om7:execute_operation(op7)
    T.assert_equal(r7.status, "failed", "operation should fail")
    T.assert_equal(#failed_events, 1, "should emit operation_failed")
    T.assert_equal(r7.error, "NPC not found", "error should be propagated")

    _G.core.input.interact_unit = function() return true end
    print("  PASS")

    -- =====================================================================
    -- Test 8: Interleave support with allow_interleave
    -- =====================================================================
    print("Test 8: Interleave support")
    local bb8 = Blackboard:new()
    local om8 = OperationManager:new(bb8, EventBus:new(), mock_nav)

    local op8 = {
        id = "op-interleave-1",
        actions = {
            { id = "a1", payload = { type = "goto", target = { x = 100, y = 100, z = 0 } } },
        },
    }

    local result8 = om8:execute_operation(op8, { allow_interleave = true })
    T.assert_equal(result8.status, "running", "should return running with interleave")

    -- Poll to complete
    local poll_result = om8:poll()
    T.assert_equal(poll_result.status, "succeeded", "poll should complete operation")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Reset operation state
    -- =====================================================================
    print("Test 9: Reset operation state")
    local bb9 = Blackboard:new()
    local om9 = OperationManager:new(bb9, EventBus:new(), mock_nav)
    local op9 = { id = "op-reset-1", actions = {} }
    om9:execute_operation(op9)
    om9:reset_operation("op-reset-1")
    local status9 = om9:get_status("op-reset-1")
    T.assert_equal(status9, "ready", "status should be ready after reset")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Clear all operation state
    -- =====================================================================
    print("Test 10: Clear all operation state")
    local bb10 = Blackboard:new()
    local om10 = OperationManager:new(bb10, EventBus:new(), mock_nav)
    om10:execute_operation({ id = "op-clear-1", actions = {} })
    om10:execute_operation({ id = "op-clear-2", actions = {} })
    om10:clear()

    local snapshot = bb10:snapshot("module.operation.")
    T.assert_nil(next(snapshot), "no operation keys should remain after clear")
    print("  PASS")

    -- =====================================================================
    -- Test 11: Operation state key format in blackboard
    -- =====================================================================
    print("Test 11: Blackboard key format")
    local bb11 = Blackboard:new()
    local om11 = OperationManager:new(bb11, EventBus:new(), mock_nav)
    local op11 = { id = "op-key-test", actions = {} }
    om11:execute_operation(op11)

    local status11 = bb11:get("module.operation.op-key-test.status")
    T.assert_equal(status11, "completed", "operation status should use correct key format")
    print("  PASS")

    -- =====================================================================
    -- Test 12: RuntimeContext integration - get_operation_manager
    -- =====================================================================
    print("Test 12: RuntimeContext integration")
    package.loaded["runtime/runtime_context"] = nil
    local RuntimeContext = require("runtime/runtime_context")

    local ctx12 = RuntimeContext:new(bb1, EventBus:new())
    local ctx_om12 = ctx12:get_operation_manager()
    T.assert_not_nil(ctx_om12, "should get operation manager from context")

    -- Verify same instance is returned on subsequent calls
    local ctx_om12b = ctx12:get_operation_manager()
    T.assert_equal(ctx_om12, ctx_om12b, "should return same instance")
    print("  PASS")

    print("\n=== All OperationManager Tests PASSED ===")
end

return M