-- sentinel/tests/runtime/test_profile_state.lua
-- Tests for runtime/profile_state.lua

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Profile State Tests ===")

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local bb = Blackboard:new()
    local eb = EventBus:new()
    local ProfileState = require("runtime/profile_state")
    local ps = ProfileState:new(bb, eb)
    T.assert_not_nil(ps, "ProfileState instance should not be nil")
    T.assert_nil(ps:get_profile_state(), "initial profile state should be nil")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Set initial profile state
    -- =====================================================================
    print("Test 2: Set initial profile state")
    local bb2 = Blackboard:new()
    local eb2 = EventBus:new()
    local ps2 = ProfileState:new(bb2, eb2)

    local ok = ps2:set_profile_state("idle")
    T.assert_true(ok, "setting initial state 'idle' should succeed")
    T.assert_equal(ps2:get_profile_state(), "idle", "profile state should be 'idle'")
    T.assert_equal(bb2:get("module.runtime.profile_state"), "idle", "blackboard should reflect 'idle'")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Valid transition: idle → ready
    -- =====================================================================
    print("Test 3: Valid transition idle → ready")
    local bb3 = Blackboard:new()
    local eb3 = EventBus:new()
    local ps3 = ProfileState:new(bb3, eb3)
    ps3:set_profile_state("idle")
    local ok = ps3:set_profile_state("ready")
    T.assert_true(ok, "idle → ready should succeed")
    T.assert_equal(ps3:get_profile_state(), "ready", "state should be 'ready'")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Full profile state cycle
    -- =====================================================================
    print("Test 4: Full profile state cycle")
    local bb4 = Blackboard:new()
    local eb4 = EventBus:new()
    local ps4 = ProfileState:new(bb4, eb4)

    T.assert_true(ps4:set_profile_state("idle"), "→ idle")
    T.assert_true(ps4:set_profile_state("ready"), "→ ready")
    T.assert_true(ps4:set_profile_state("executing"), "→ executing")
    T.assert_true(ps4:set_profile_state("waiting"), "→ waiting")
    T.assert_true(ps4:set_profile_state("executing"), "→ executing (back)")
    T.assert_true(ps4:set_profile_state("idle"), "→ idle (from executing)")
    T.assert_true(ps4:set_profile_state("ready"), "→ ready")
    T.assert_true(ps4:set_profile_state("executing"), "→ executing")
    T.assert_true(ps4:set_profile_state("idle"), "→ idle")
    T.assert_true(ps4:set_profile_state("ready"), "→ ready")
    T.assert_true(ps4:set_profile_state("executing"), "→ executing")
    T.assert_true(ps4:set_profile_state("waiting"), "→ waiting")
    T.assert_true(ps4:set_profile_state("idle"), "→ idle (from waiting)")
    T.assert_equal(ps4:get_profile_state(), "idle", "final state should be 'idle'")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Invalid profile state transition
    -- =====================================================================
    print("Test 5: Invalid profile state transition")
    local bb5 = Blackboard:new()
    local eb5 = EventBus:new()
    local ps5 = ProfileState:new(bb5, eb5)
    ps5:set_profile_state("idle")

    -- Can't jump from idle to executing (must go through ready first)
    local ok = ps5:set_profile_state("executing")
    T.assert_false(ok, "idle → executing should be invalid")
    T.assert_equal(ps5:get_profile_state(), "idle", "state should remain 'idle'")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Invalid profile state name
    -- =====================================================================
    print("Test 6: Invalid profile state name")
    local bb6 = Blackboard:new()
    local eb6 = EventBus:new()
    local ps6 = ProfileState:new(bb6, eb6)
    local ok = ps6:set_profile_state("invalid_state")
    T.assert_false(ok, "invalid state name should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Set and get operation state
    -- =====================================================================
    print("Test 7: Operation state basic")
    local bb7 = Blackboard:new()
    local eb7 = EventBus:new()
    local ps7 = ProfileState:new(bb7, eb7)

    -- Must start as locked
    local ok = ps7:set_operation_state("op_1", "locked")
    T.assert_true(ok, "setting initial state 'locked' should succeed")
    T.assert_equal(ps7:get_operation_state("op_1"), "locked", "op state should be 'locked'")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Valid operation state transitions
    -- =====================================================================
    print("Test 8: Valid operation state transitions")
    local bb8 = Blackboard:new()
    local eb8 = EventBus:new()
    local ps8 = ProfileState:new(bb8, eb8)

    ps8:set_operation_state("op_2", "locked")
    T.assert_true(ps8:set_operation_state("op_2", "ready"), "locked → ready")
    T.assert_true(ps8:set_operation_state("op_2", "active"), "ready → active")
    T.assert_true(ps8:set_operation_state("op_2", "completed"), "active → completed")

    -- Test failed path
    ps8:set_operation_state("op_3", "locked")
    ps8:set_operation_state("op_3", "ready")
    ps8:set_operation_state("op_3", "active")
    T.assert_true(ps8:set_operation_state("op_3", "failed"), "active → failed")

    -- Test aborted path
    ps8:set_operation_state("op_4", "locked")
    ps8:set_operation_state("op_4", "ready")
    ps8:set_operation_state("op_4", "active")
    T.assert_true(ps8:set_operation_state("op_4", "aborted"), "active → aborted")

    -- Test skipped path
    ps8:set_operation_state("op_5", "locked")
    ps8:set_operation_state("op_5", "ready")
    ps8:set_operation_state("op_5", "active")
    T.assert_true(ps8:set_operation_state("op_5", "skipped"), "active → skipped")

    print("  PASS")

    -- =====================================================================
    -- Test 9: Invalid operation state transitions
    -- =====================================================================
    print("Test 9: Invalid operation state transitions")
    local bb9 = Blackboard:new()
    local eb9 = EventBus:new()
    local ps9 = ProfileState:new(bb9, eb9)

    -- Can't set to ready without first being locked
    local ok = ps9:set_operation_state("op_6", "ready")
    T.assert_false(ok, "nil → ready should be invalid (must start as locked)")

    -- Can't skip from locked to active
    ps9:set_operation_state("op_7", "locked")
    ok = ps9:set_operation_state("op_7", "active")
    T.assert_false(ok, "locked → active should be invalid")

    -- Can't go from completed back to ready
    ps9:set_operation_state("op_8", "locked")
    ps9:set_operation_state("op_8", "ready")
    ps9:set_operation_state("op_8", "active")
    ps9:set_operation_state("op_8", "completed")
    ok = ps9:set_operation_state("op_8", "ready")
    T.assert_false(ok, "completed → ready should be invalid")

    print("  PASS")

    -- =====================================================================
    -- Test 10: Invalid operation state name
    -- =====================================================================
    print("Test 10: Invalid operation state name")
    local bb10 = Blackboard:new()
    local eb10 = EventBus:new()
    local ps10 = ProfileState:new(bb10, eb10)
    local ok = ps10:set_operation_state("op_9", "bogus")
    T.assert_false(ok, "bogus state name should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 11: Operation state with nil/empty op_id
    -- =====================================================================
    print("Test 11: Operation state edge cases")
    local bb11 = Blackboard:new()
    local eb11 = EventBus:new()
    local ps11 = ProfileState:new(bb11, eb11)

    local ok = ps11:set_operation_state(nil, "locked")
    T.assert_false(ok, "nil op_id should fail")

    ok = ps11:set_operation_state("", "locked")
    T.assert_false(ok, "empty op_id should fail")

    local state = ps11:get_operation_state(nil)
    T.assert_nil(state, "get with nil op_id should return nil")

    state = ps11:get_operation_state("")
    T.assert_nil(state, "get with empty op_id should return nil")

    print("  PASS")

    -- =====================================================================
    -- Test 12: Recovery actions
    -- =====================================================================
    print("Test 12: Recovery actions")
    local bb12 = Blackboard:new()
    local eb12 = EventBus:new()
    local ps12 = ProfileState:new(bb12, eb12)

    -- Set retry
    local ok = ps12:set_recovery("op_a", "retry")
    T.assert_true(ok, "set_recovery retry should succeed")
    T.assert_equal(ps12:get_recovery("op_a"), "retry", "recovery should be 'retry'")

    -- Set skip
    ok = ps12:set_recovery("op_a", "skip")
    T.assert_true(ok, "set_recovery skip should succeed")
    T.assert_equal(ps12:get_recovery("op_a"), "skip", "recovery should be 'skip'")

    -- Set abort
    ok = ps12:set_recovery("op_a", "abort")
    T.assert_true(ok, "set_recovery abort should succeed")
    T.assert_equal(ps12:get_recovery("op_a"), "abort", "recovery should be 'abort'")

    -- Invalid action
    ok = ps12:set_recovery("op_a", "invalid")
    T.assert_false(ok, "invalid recovery action should fail")
    T.assert_equal(ps12:get_recovery("op_a"), "abort", "recovery should remain 'abort'")

    -- nil/empty op_id
    ok = ps12:set_recovery(nil, "retry")
    T.assert_false(ok, "nil op_id should fail")
    ok = ps12:set_recovery("", "retry")
    T.assert_false(ok, "empty op_id should fail")

    local rec = ps12:get_recovery(nil)
    T.assert_nil(rec, "get_recovery with nil op_id should return nil")
    rec = ps12:get_recovery("")
    T.assert_nil(rec, "get_recovery with empty op_id should return nil")

    print("  PASS")

    -- =====================================================================
    -- Test 13: Reset clears all state
    -- =====================================================================
    print("Test 13: Reset")
    local bb13 = Blackboard:new()
    local eb13 = EventBus:new()
    local ps13 = ProfileState:new(bb13, eb13)

    ps13:set_profile_state("idle")
    ps13:set_operation_state("op_x", "locked")
    ps13:set_operation_state("op_y", "locked")
    ps13:set_recovery("op_x", "retry")

    T.assert_not_nil(ps13:get_profile_state(), "profile state should exist before reset")
    T.assert_not_nil(ps13:get_operation_state("op_x"), "op_x state should exist before reset")

    ps13:reset()

    T.assert_nil(ps13:get_profile_state(), "profile state should be nil after reset")
    T.assert_nil(ps13:get_operation_state("op_x"), "op_x state should be nil after reset")
    T.assert_nil(ps13:get_operation_state("op_y"), "op_y state should be nil after reset")
    T.assert_nil(ps13:get_recovery("op_x"), "op_x recovery should be nil after reset")

    print("  PASS")

    -- =====================================================================
    -- Test 14: Profile state changed events
    -- =====================================================================
    print("Test 14: Profile state events")
    local bb14 = Blackboard:new()
    local eb14 = EventBus:new()
    local ps14 = ProfileState:new(bb14, eb14)

    local profile_events = {}
    eb14:subscribe("profile_state_changed", function(payload)
        table.insert(profile_events, payload)
    end)

    ps14:set_profile_state("idle")
    ps14:set_profile_state("ready")
    ps14:set_profile_state("executing")

    T.assert_equal(#profile_events, 3, "should have 3 profile state events")
    T.assert_nil(profile_events[1].from, "first event from should be nil")
    T.assert_equal(profile_events[1].to, "idle", "first event to should be 'idle'")
    T.assert_equal(profile_events[2].from, "idle", "second event from should be 'idle'")
    T.assert_equal(profile_events[2].to, "ready", "second event to should be 'ready'")
    T.assert_equal(profile_events[3].from, "ready", "third event from should be 'ready'")
    T.assert_equal(profile_events[3].to, "executing", "third event to should be 'executing'")
    print("  PASS")

    -- =====================================================================
    -- Test 15: Operation state changed events
    -- =====================================================================
    print("Test 15: Operation state events")
    local bb15 = Blackboard:new()
    local eb15 = EventBus:new()
    local ps15 = ProfileState:new(bb15, eb15)

    local op_events = {}
    eb15:subscribe("operation_state_changed", function(payload)
        table.insert(op_events, payload)
    end)

    ps15:set_operation_state("op_z", "locked")
    ps15:set_operation_state("op_z", "ready")
    ps15:set_operation_state("op_z", "active")
    ps15:set_operation_state("op_z", "completed")

    T.assert_equal(#op_events, 4, "should have 4 operation state events")
    T.assert_equal(op_events[1].operation_id, "op_z")
    T.assert_nil(op_events[1].from, "first op event from should be nil")
    T.assert_equal(op_events[1].to, "locked", "first op event to should be 'locked'")
    T.assert_equal(op_events[2].from, "locked")
    T.assert_equal(op_events[2].to, "ready")
    T.assert_equal(op_events[3].from, "ready")
    T.assert_equal(op_events[3].to, "active")
    T.assert_equal(op_events[4].from, "active")
    T.assert_equal(op_events[4].to, "completed")
    print("  PASS")

    -- =====================================================================
    -- Test 16: Setting same state is idempotent (no event published)
    -- =====================================================================
    print("Test 16: Idempotent state setting")
    local bb16 = Blackboard:new()
    local eb16 = EventBus:new()
    local ps16 = ProfileState:new(bb16, eb16)

    local count = 0
    eb16:subscribe("profile_state_changed", function() count = count + 1 end)
    eb16:subscribe("operation_state_changed", function() count = count + 1 end)

    ps16:set_profile_state("idle")
    T.assert_equal(count, 1, "1 event so far")

    -- Set same state again — no event should be published but returns true
    local ok = ps16:set_profile_state("idle")
    T.assert_true(ok, "setting same state should return true")
    T.assert_equal(count, 1, "no additional event for same state")

    ps16:set_operation_state("op_z", "locked")
    T.assert_equal(count, 2, "2 events so far")

    ok = ps16:set_operation_state("op_z", "locked")
    T.assert_true(ok, "setting same op state should return true")
    T.assert_equal(count, 2, "no additional event for same op state")

    print("  PASS")

    print("\n=== All ProfileState Tests PASSED ===")
end

return M
