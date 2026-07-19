-- sentinel/tests/runtime/test_runtime_engine.lua
-- Tests for runtime/runtime_engine.lua

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Runtime Engine Tests ===")

    -- Mock objects used across tests
    local mock_nav = {
        _state = "idle",
        move_to = function(self, target)
            self._state = "moving"
            return true
        end,
        poll = function(self)
            if self._state == "moving" then
                self._state = "idle"
            end
        end,
        get_state = function(self) return self._state end,
        stop = function(self) self._state = "idle" end,
        is_active = function(self) return self._state == "moving" end,
    }

    -- Mock core for tests
    _G.core = _G.core or {}
    _G.core.input = {
        interact_unit = function(guid) return true end,
        use_item = function(id) return true end,
    }
    _G.core.player = {
        is_moving = function() return false end,
        is_dead = function() return false end,
        is_ghost = function() return false end,
        kill = function() return true end,
    }
    _G.core.object_manager = {
        get_all_objects = function() return {} end,
    }
    _G.core.game_time = function() return 0 end

    -- Helper to create a mock profile manager
    local function make_profile_manager(profile, profile_id)
        profile = profile or { name = "Test", author = "Test", schema_version = "1.0", operations = {} }
        profile_id = profile_id or "test-profile"
        local pm = {
            _profile = profile,
            _profile_id = profile_id,
            get_active_profile = function(self) return self._profile end,
            get_active_profile_id = function(self) return self._profile_id end,
            set_active_profile = function(self, p) self._profile = p end,
            activate = function(self, bb, id) self._profile_id = id; bb:set("module.runtime.active_profile", id); return true end,
            deactivate = function(self, bb) self._profile_id = nil; self._profile = nil; return true end,
        }
        return pm
    end

    package.loaded["runtime/runtime_engine"] = nil
    local Engine = require("runtime/runtime_engine")
    package.loaded["runtime/operation_scheduler"] = nil
    package.loaded["runtime/action_executor"] = nil

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local bb1 = Blackboard:new()
    local eb1 = EventBus:new()
    local pm1 = make_profile_manager()
    local eng1 = Engine:new(bb1, eb1, pm1, mock_nav)
    local state1 = eng1:get_state()
    T.assert_equal(state1.status, "idle", "initial status should be idle")
    T.assert_nil(state1.current_operation, "no current operation initially")
    T.assert_nil(state1.current_action, "no current action initially")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Start engine sets status to running
    -- =====================================================================
    print("Test 2: Start engine")
    local bb2 = Blackboard:new()
    local eb2 = EventBus:new()
    local pm2 = make_profile_manager()
    local eng2 = Engine:new(bb2, eb2, pm2, mock_nav)
    eng2:start()
    local state2 = eng2:get_state()
    T.assert_equal(state2.status, "running", "engine should be running after start")
    T.assert_equal(bb2:get("module.runtime.engine_status"), "running", "blackboard should reflect running")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Pause and resume engine
    -- =====================================================================
    print("Test 3: Pause and resume engine")
    local bb3 = Blackboard:new()
    local eb3 = EventBus:new()
    local pm3 = make_profile_manager()
    local eng3 = Engine:new(bb3, eb3, pm3, mock_nav)
    eng3:start()
    T.assert_equal(eng3:get_state().status, "running", "should be running")

    eng3:pause()
    T.assert_equal(eng3:get_state().status, "paused", "should be paused after pause")
    T.assert_equal(bb3:get("module.runtime.engine_status"), "paused", "blackboard should reflect paused")

    eng3:resume()
    T.assert_equal(eng3:get_state().status, "running", "should be running after resume")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Stop engine
    -- =====================================================================
    print("Test 4: Stop engine")
    local bb4 = Blackboard:new()
    local eb4 = EventBus:new()
    local pm4 = make_profile_manager()
    local eng4 = Engine:new(bb4, eb4, pm4, mock_nav)
    eng4:start()
    eng4:stop()
    local state4 = eng4:get_state()
    T.assert_equal(state4.status, "stopped", "engine should be stopped")
    T.assert_equal(bb4:get("module.runtime.engine_status"), "stopped", "blackboard should reflect stopped")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Engine tick with profile that has a single operation
    -- =====================================================================
    print("Test 5: Engine tick with single operation")
    local bb5 = Blackboard:new()
    bb5:set("player.level", 5)
    bb5:set("player.race", "Human")
    bb5:set("player.class", "Warrior")
    local eb5 = EventBus:new()
    local profile5 = {
        name = "Test Profile",
        author = "Test",
        schema_version = "1.0",
        id = "profile-5",
        operations = {
            {
                id = "op-setvar",
                name = "Set Variable",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-1", action_type = "set_variable", payload = { type = "set_variable", name = "my_var", value = "hello" } },
                }
            },
        }
    }
    local pm5 = make_profile_manager(profile5, "profile-5")
    local eng5 = Engine:new(bb5, eb5, pm5, mock_nav)
    eng5:start()

    -- First tick should execute the set_variable action
    local result5 = eng5:tick(16)
    T.assert_equal(result5.status, "running", "engine should still be running")
    T.assert_equal(bb5:get("module.runtime.var.my_var"), "hello", "variable should be set")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Engine completes when no more operations
    -- =====================================================================
    print("Test 6: Engine completes when no more operations")
    local bb6 = Blackboard:new()
    bb6:set("player.level", 5)
    bb6:set("player.race", "Human")
    bb6:set("player.class", "Warrior")
    local eb6 = EventBus:new()
    local profile6 = {
        name = "Test Profile",
        author = "Test",
        schema_version = "1.0",
        id = "profile-6",
        operations = {
            {
                id = "op-single",
                name = "Single Action Op",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-1", action_type = "set_variable", payload = { type = "set_variable", name = "done", value = true } },
                }
            },
        }
    }
    local pm6 = make_profile_manager(profile6, "profile-6")

    -- Clear module cache to get fresh instances
    package.loaded["runtime/runtime_engine"] = nil
    package.loaded["runtime/operation_scheduler"] = nil
    package.loaded["runtime/action_executor"] = nil
    local Engine6 = require("runtime/runtime_engine")

    local eng6 = Engine6:new(bb6, eb6, pm6, mock_nav)
    eng6:start()

    -- First tick - should execute action and advance
    local r6a = eng6:tick(16)
    T.assert_equal(r6a.status, "running", "should still be running after action executes")

    -- Second tick - should advance operation and find no more ready
    local r6b = eng6:tick(16)
    T.assert_equal(r6b.status, "completed", "engine should be completed")
    T.assert_equal(bb6:get("module.runtime.engine_status"), "completed", "blackboard should reflect completed")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Engine tick does nothing when paused
    -- =====================================================================
    print("Test 7: Engine tick does nothing when paused")
    local bb7 = Blackboard:new()
    bb7:set("player.level", 5)
    bb7:set("player.race", "Human")
    bb7:set("player.class", "Warrior")
    local eb7 = EventBus:new()
    local profile7 = {
        name = "Test Profile",
        author = "Test",
        schema_version = "1.0",
        id = "profile-7",
        operations = {
            {
                id = "op-pause-test",
                name = "Pause Test",
                priority = 10,
                entry_conditions = {},
actions = {
                     { id = "act-7", action_type = "set_variable", payload = { type = "set_variable", name = "should_not_be_set", value = true } },
                 }
            },
        }
    }
    local pm7 = make_profile_manager(profile7, "profile-7")

    package.loaded["runtime/runtime_engine"] = nil
    package.loaded["runtime/operation_scheduler"] = nil
    package.loaded["runtime/action_executor"] = nil
    local Engine7 = require("runtime/runtime_engine")

    local eng7 = Engine7:new(bb7, eb7, pm7, mock_nav)
    eng7:start()
    eng7:pause()

    -- Tick while paused
    local r7 = eng7:tick(16)
    T.assert_equal(r7.status, "paused", "should still be paused")
    T.assert_nil(bb7:get("module.runtime.var.should_not_be_set"), "no action should execute while paused")
    print("  PASS")

    -- =====================================================================
    -- Test 8: set_profile changes the active profile
    -- =====================================================================
    print("Test 8: set_profile changes active profile")
    local bb8 = Blackboard:new()
    local eb8 = EventBus:new()
    local pm8 = make_profile_manager()
    local eng8 = Engine:new(bb8, eb8, pm8, mock_nav)

    local new_profile = {
        name = "New Profile",
        author = "Agent",
        schema_version = "1.0",
        id = "new-profile",
        operations = {
            { id = "op-new", name = "New Op", priority = 10, entry_conditions = {}, actions = {} },
        }
    }
    eng8:set_profile(new_profile)
    T.assert_equal(bb8:get("module.runtime.profile_id"), "new-profile", "profile id should be set in blackboard")
    T.assert_equal(eng8:get_state().profile_id, "new-profile", "engine should track new profile id")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Engine processes multiple operations in priority order
    -- =====================================================================
    print("Test 9: Engine processes multiple operations in priority order")
    local bb9 = Blackboard:new()
    bb9:set("player.level", 5)
    bb9:set("player.race", "Human")
    bb9:set("player.class", "Warrior")
    local eb9 = EventBus:new()
    local profile9 = {
        name = "Test Profile",
        author = "Test",
        schema_version = "1.0",
        id = "profile-9",
        operations = {
            {
                id = "op-low",
                name = "Low Priority",
                priority = 10,
                entry_conditions = {},
actions = {
                     { id = "act-low", action_type = "set_variable", payload = { type = "set_variable", name = "order", value = "low" } },
                 }
             },
             {
                 id = "op-high",
                 name = "High Priority",
                 priority = 100,
                 entry_conditions = {},
                 actions = {
                     { id = "act-high", action_type = "set_variable", payload = { type = "set_variable", name = "order", value = "high" } },
                 }
             },
        }
    }
    local pm9 = make_profile_manager(profile9, "profile-9")

    package.loaded["runtime/runtime_engine"] = nil
    package.loaded["runtime/operation_scheduler"] = nil
    package.loaded["runtime/action_executor"] = nil
    local Engine9 = require("runtime/runtime_engine")

    local eng9 = Engine9:new(bb9, eb9, pm9, mock_nav)
    eng9:start()

    -- Tick 1: executes high priority op's action (set_variable to "high"), then advances to next op
    local r9a = eng9:tick(16)
    T.assert_equal(r9a.status, "running", "engine should be running after first tick")
    -- After first tick, high priority action has been executed
    T.assert_equal(bb9:get("module.runtime.var.order"), "high", "high priority should have run")

    -- Tick 2: executes low priority op's action (set_variable to "low"), then completes last op
    local r9b = eng9:tick(16)
    T.assert_equal(r9b.status, "running", "engine should still be running after second tick")
    -- The low priority action overrides with "low"
    T.assert_equal(bb9:get("module.runtime.var.order"), "low", "low priority should have run")

    -- Tick 3: no more ready operations, engine completes
    local r9c = eng9:tick(16)
    T.assert_equal(r9c.status, "completed", "engine should be completed after third tick")
    print("  PASS")

    print("\n=== All RuntimeEngine Tests PASSED ===")
end

return M
