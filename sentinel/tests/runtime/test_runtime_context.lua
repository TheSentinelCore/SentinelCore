-- sentinel/tests/runtime/test_runtime_context.lua
-- Tests for runtime/runtime_context.lua - SENT-8.2

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local VariableStore = require("runtime/variable_store")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== RuntimeContext Tests ===")

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local bb = Blackboard:new()
    local eb = EventBus:new()
    local RuntimeContext = require("runtime/runtime_context")
    local ctx = RuntimeContext:new(bb, eb)
    T.assert_not_nil(ctx, "RuntimeContext instance should not be nil")
    T.assert_equal(type(ctx.get_variable_store), "function", "should have get_variable_store method")
    print("  PASS")

    -- =====================================================================
    -- Test 2: VariableStore integration
    -- =====================================================================
    print("Test 2: VariableStore integration")
    local vs = ctx:get_variable_store()
    T.assert_not_nil(vs, "VariableStore should not be nil")

    vs:set("global", "test_key", "test_value")
    local val = vs:get("global", "test_key")
    T.assert_equal(val, "test_value", "VariableStore set/get should work")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Profile management
    -- =====================================================================
    print("Test 3: Profile management")
    local profile = {
        profile_id = "test-profile-1",
        name = "Test Profile",
        operations = {}
    }
    ctx:set_profile(profile)

    T.assert_equal(ctx:get_profile_id(), "test-profile-1", "profile_id should be set")
    local retrieved = ctx:get_profile()
    T.assert_not_nil(retrieved, "get_profile should return profile")
    T.assert_equal(retrieved.name, "Test Profile", "profile name should match")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Runtime state machine
    -- =====================================================================
    print("Test 4: Runtime state machine")
    local ctx4 = RuntimeContext:new(Blackboard:new(), EventBus:new())

    T.assert_equal(ctx4:get_runtime_state(), "idle", "should start at idle")
    ctx4:transition_to_ready()
    T.assert_equal(ctx4:get_runtime_state(), "ready", "should transition to ready")
    ctx4:transition_to_executing()
    T.assert_equal(ctx4:get_runtime_state(), "executing", "should transition to executing")
    ctx4:transition_to_waiting()
    T.assert_equal(ctx4:get_runtime_state(), "waiting", "should transition to waiting")
    ctx4:transition_to_finished()
    T.assert_equal(ctx4:get_runtime_state(), "finished", "should transition to finished")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Runtime state publishes events
    -- =====================================================================
    print("Test 5: Runtime state event publishing")
    local bb5 = Blackboard:new()
    local eb5 = EventBus:new()
    local ctx5 = RuntimeContext:new(bb5, eb5)

    local state_changes = {}
    eb5:subscribe("runtime_state_changed", function(payload)
        table.insert(state_changes, payload)
    end)

    ctx5:transition_to_ready()
    ctx5:transition_to_executing()

    T.assert_equal(#state_changes, 2, "should have 2 state change events")
    T.assert_equal(state_changes[1].from, "idle", "first change from idle")
    T.assert_equal(state_changes[1].to, "ready", "first change to ready")
    T.assert_equal(state_changes[2].from, "ready", "second change from ready")
    T.assert_equal(state_changes[2].to, "executing", "second change to executing")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Player state access
    -- =====================================================================
    print("Test 6: Player state access")
    local bb6 = Blackboard:new()
    bb6:set("player.level", 10)
    bb6:set("player.class", "Mage")
    bb6:set("player.race", "Human")

    local ctx6 = RuntimeContext:new(bb6, EventBus:new())
    local player_state = ctx6:get_player_state()

    T.assert_equal(player_state.level, 10, "player level should match")
    T.assert_equal(player_state.class, "Mage", "player class should match")
    T.assert_equal(player_state.race, "Human", "player race should match")
    print("  PASS")

    -- =====================================================================
    -- Test 7: NPC/Object tracking
    -- =====================================================================
    print("Test 7: NPC/Object tracking")
    local bb7 = Blackboard:new()
    local eb7 = EventBus:new()
    local ctx7 = RuntimeContext:new(bb7, eb7)

    ctx7:set_known_npc({ entry_id = 123, name = "Test NPC" })
    local npcs = ctx7:get_known_npcs()
    T.assert_not_nil(npcs[123], "NPC should be stored")
    T.assert_equal(npcs[123].name, "Test NPC", "NPC name should match")

    ctx7:set_known_object({ entry_id = 456, name = "Test Object" })
    local objs = ctx7:get_known_objects()
    T.assert_not_nil(objs[456], "Object should be stored")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Inventory snapshot
    -- =====================================================================
    print("Test 8: Inventory snapshot")
    local bb8 = Blackboard:new()
    local ctx8 = RuntimeContext:new(bb8, EventBus:new())

    local items = {
        { entry_id = 1, count = 5 },
        { entry_id = 2, count = 1 }
    }
    ctx8:set_inventory(items)

    local retrieved_items = ctx8:get_inventory()
    T.assert_equal(#retrieved_items, 2, "inventory should have 2 items")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Clear resets state
    -- =====================================================================
    print("Test 9: Clear resets state")
    local bb9 = Blackboard:new()
    local ctx9 = RuntimeContext:new(bb9, EventBus:new())

    ctx9:set_profile({ profile_id = "test-clear", name = "Test" })
    ctx9:transition_to_executing()
    ctx9:set_inventory({ { entry_id = 1 } })

    ctx9:clear()

    T.assert_nil(ctx9:get_profile(), "profile should be nil after clear")
    T.assert_nil(ctx9:get_profile_id(), "profile_id should be nil after clear")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Context sync with profile
    -- =====================================================================
    print("Test 10: Context sync with profile")
    local bb10 = Blackboard:new()
    local eb10 = EventBus:new()
    local ctx10 = RuntimeContext:new(bb10, eb10)

    -- RuntimeContext should set profile on activation via profile_manager
    local profile10 = {
        profile_id = "profile-sync-test",
        name = "Sync Test",
        operations = {}
    }
    ctx10:set_profile(profile10)

    T.assert_equal(bb10:get("module.runtime.active_profile"), profile10, "blackboard should have profile")
    T.assert_equal(bb10:get("module.runtime.profile_id"), "profile-sync-test", "blackboard should have profile_id")
    print("  PASS")

    print("\n=== All RuntimeContext Tests PASSED ===")
end

return M