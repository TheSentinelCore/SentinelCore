-- sentinel/tests/runtime/test_runtime_action_executor.lua
-- Tests for SENT-8.5 Runtime Action Executor

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== RuntimeActionExecutor Tests ===")

    -- Mock nav adapter for tests
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

    package.loaded["runtime/runtime_action_executor"] = nil
    local Executor = require("runtime/runtime_action_executor")

    -- =====================================================================
    -- Test 1: Construction with RuntimeAction schema
    -- =====================================================================
    print("Test 1: Construction with RuntimeAction schema")
    local bb1 = Blackboard:new()
    local eb1 = EventBus:new()
    local ex1 = Executor:new(bb1, eb1, mock_nav)
    T.assert_not_nil(ex1, "executor should be created")
    local state1 = ex1:get_state()
    T.assert_not_nil(state1, "get_state should return table")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Execute nil action returns failed
    -- =====================================================================
    print("Test 2: Execute nil action")
    local bb2 = Blackboard:new()
    local ex2 = Executor:new(bb2, EventBus:new(), mock_nav)
    local r2 = ex2:execute(nil)
    T.assert_equal(r2.status, "failed", "nil action should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Execute action with missing payload returns failed
    -- =====================================================================
    print("Test 3: Execute action missing payload")
    local bb3 = Blackboard:new()
    local ex3 = Executor:new(bb3, EventBus:new(), mock_nav)
    local r3 = ex3:execute({ id = "test-action-1" })
    T.assert_equal(r3.status, "failed", "action without payload should fail")
    T.assert_equal(r3.error, "invalid action: missing payload", "should indicate missing payload")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Execute valid pickup_quest payload
    -- =====================================================================
    print("Test 4: Execute pickup_quest payload")
    local bb4 = Blackboard:new()
    local ex4 = Executor:new(bb4, EventBus:new(), mock_nav)
    local action4 = {
        id = "action-pickup-1",
        payload = { type = "pickup_quest", npc_guid = "npc-123", quest_id = 33 },
        retry_policy = { max_attempts = 3 },
        timeout = 10000,
        generated_from = "source-action-uuid",
    }
    local r4 = ex4:execute(action4)
    T.assert_equal(r4.status, "succeeded", "pickup_quest should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Execute pickup_quest without npc_guid returns failed
    -- =====================================================================
    print("Test 5: Execute pickup_quest without npc_guid")
    local bb5 = Blackboard:new()
    local ex5 = Executor:new(bb5, EventBus:new(), mock_nav)
    local r5 = ex5:execute({
        id = "action-pickup-2",
        payload = { type = "pickup_quest", quest_id = 33 },
    })
    T.assert_equal(r5.status, "failed", "pickup_quest without guid should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Retry on failure with max_attempts
    -- =====================================================================
    print("Test 6: Retry on failure with max_attempts")
    local bb6 = Blackboard:new()
    local ex6 = Executor:new(bb6, EventBus:new(), mock_nav)
    _G.core.input.interact_unit = function() error("NPC not found") end
    local r6 = ex6:execute({
        id = "action-retry-1",
        payload = { type = "pickup_quest", npc_guid = "npc-1" },
        retry_policy = { max_attempts = 2 },
    })
    T.assert_equal(r6.status, "running", "should be running (retrying)")
    T.assert_equal(r6.error, "retrying", "should indicate retrying")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Exceed retry attempts
    -- =====================================================================
    print("Test 7: Exceed retry attempts")
    local bb7 = Blackboard:new()
    local ex7 = Executor:new(bb7, EventBus:new(), mock_nav)
    _G.core.input.interact_unit = function() error("NPC not found") end
    ex7._attempt_count = 2 -- Already at max
    local r7 = ex7:execute({
        id = "action-retry-2",
        payload = { type = "pickup_quest", npc_guid = "npc-1" },
        retry_policy = { max_attempts = 3 },
    })
    T.assert_equal(r7.status, "running", "should be running (retrying)")
    T.assert_equal(r7.error, "retrying", "should indicate retrying")
    _G.core.input.interact_unit = function() return true end
    print("  PASS")

    -- =====================================================================
    -- Test 8: Timeout exceeded for async action
    -- =====================================================================
    print("Test 8: Timeout exceeded")
    local bb8 = Blackboard:new()
    local ex8 = Executor:new(bb8, EventBus:new(), mock_nav)
    local time_counter = 0
    _G.core.game_time = function() return time_counter end

    local r8a = ex8:execute({
        id = "action-wait-1",
        payload = { type = "wait", duration_ms = 10000 },
        timeout = 50, -- 50ms timeout
    })
    T.assert_equal(r8a.status, "running", "should start running")

    time_counter = 200 -- Advance past timeout
    local r8b = ex8:poll()
    T.assert_equal(r8b.status, "failed", "should fail due to timeout")
    T.assert_equal(r8b.error, "timeout exceeded", "should indicate timeout")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Default timeout is 10s
    -- =====================================================================
    print("Test 9: Default timeout is 10s")
    local bb9 = Blackboard:new()
    local ex9 = Executor:new(bb9, EventBus:new(), mock_nav)
    local action9 = {
        id = "action-default-timeout",
        payload = { type = "set_variable", name = "test", value = 1 },
        timeout = nil, -- No timeout specified
    }
    local r9 = ex9:execute(action9)
    T.assert_equal(r9.status, "succeeded", "sync action should succeed regardless of timeout")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Cache action results in RuntimeContext
    -- =====================================================================
    print("Test 10: Cache action results")
    local bb10 = Blackboard:new()
    local ex10 = Executor:new(bb10, EventBus:new(), mock_nav)

    local action10 = {
        id = "action-cached-1",
        payload = { type = "set_variable", name = "cached_var", value = 42 },
    }
    local r10a = ex10:execute(action10)
    T.assert_equal(r10a.status, "succeeded", "action should succeed")

    -- Execute same action again - should return cached result
    local r10b = ex10:execute(action10)
    T.assert_equal(r10b.status, "succeeded", "cached action should succeed")
    T.assert_equal(r10b.cached, true, "should indicate cached result")
    print("  PASS")

    -- =====================================================================
    -- Test 11: Execute goto with nav_adapter
    -- =====================================================================
    print("Test 11: Execute goto payload")
    local bb11 = Blackboard:new()
    local nav11 = {
        _state = "idle",
        move_to = function(self, target)
            self._state = "moving"
            self._target = target
            return true, nil
        end,
        poll = function(self) end,
        get_state = function(self) return self._state end,
    }
    local ex11 = Executor:new(bb11, EventBus:new(), nav11)
    local r11a = ex11:execute({
        id = "action-goto-1",
        payload = { type = "goto", target = { x = 10, y = 20, z = 30 } },
    })
    T.assert_equal(r11a.status, "running", "goto should start as running")

    nav11._state = "idle" -- Simulate arrival
    local r11b = ex11:poll()
    T.assert_equal(r11b.status, "succeeded", "goto should complete when nav is idle")
    print("  PASS")

    -- =====================================================================
    -- Test 12: generated_from is preserved in action
    -- =====================================================================
    print("Test 12: generated_from preserved")
    local bb12 = Blackboard:new()
    local ex12 = Executor:new(bb12, EventBus:new(), mock_nav)
    local action12 = {
        id = "action-gen-1",
        payload = { type = "set_variable", name = "gen_test", value = 1 },
        generated_from = "blueprint-uuid",
    }
    local r12 = ex12:execute(action12)
    T.assert_equal(r12.status, "succeeded", "action with generated_from should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 13: set_variable payload
    -- =====================================================================
    print("Test 13: Execute set_variable payload")
    local bb13 = Blackboard:new()
    local ex13 = Executor:new(bb13, EventBus:new(), mock_nav)
    local r13 = ex13:execute({
        id = "action-var-1",
        payload = { type = "set_variable", name = "runtime_var", value = "hello" },
    })
    T.assert_equal(r13.status, "succeeded", "set_variable should succeed")
    T.assert_equal(bb13:get("module.runtime.var.runtime_var"), "hello", "variable should be set")
    print("  PASS")

    -- =====================================================================
    -- Test 14: kill_target payload
    -- =====================================================================
    print("Test 14: Execute kill_target payload")
    local bb14 = Blackboard:new()
    local ex14 = Executor:new(bb14, EventBus:new(), mock_nav)
    local r14a = ex14:execute({
        id = "action-kill-1",
        payload = { type = "kill_target", creature_entry = 197 },
    })
    T.assert_equal(r14a.status, "running", "kill_target should start as running")

    local kill_state = bb14:get("module.runtime.kill_target")
    T.assert_not_nil(kill_state, "kill_target state should be set")
    T.assert_equal(kill_state.entry, 197, "entry should be 197")
    print("  PASS")

    -- =====================================================================
    -- Test 15: branch payload with condition
    -- =====================================================================
    print("Test 15: Execute branch payload")
    local bb15 = Blackboard:new()
    bb15:set("player.level", 10)
    local ex15 = Executor:new(bb15, EventBus:new(), mock_nav)
    local r15 = ex15:execute({
        id = "action-branch-1",
        payload = { type = "branch", condition = { type = "level_above", min_level = 5 } },
    })
    T.assert_equal(r15.status, "succeeded", "branch should succeed")
    T.assert_equal(bb15:get("module.runtime.branch_result"), true, "branch result should be true")
    print("  PASS")

    -- =====================================================================
    -- Test 16: hearth payload
    -- =====================================================================
    print("Test 16: Execute hearth payload")
    local bb16 = Blackboard:new()
    local ex16 = Executor:new(bb16, EventBus:new(), mock_nav)
    local r16 = ex16:execute({
        id = "action-hearth-1",
        payload = { type = "hearth", item_id = 6948 },
    })
    T.assert_equal(r16.status, "succeeded", "hearth should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 17: Flight path poll until arrived
    -- =====================================================================
    print("Test 17: Flight path poll")
    local bb17 = Blackboard:new()
    local ex17 = Executor:new(bb17, EventBus:new(), mock_nav)

    local moving = true
    _G.core.player.is_moving = function() return moving end
    local r17a = ex17:execute({
        id = "action-flight-1",
        payload = { type = "flight_path", npc_guid = "flight-1" },
    })
    T.assert_equal(r17a.status, "running", "flight_path should start as running")

    moving = false
    local r17b = ex17:poll()
    T.assert_equal(r17b.status, "succeeded", "flight_path should complete when not moving")
    print("  PASS")

    print("\n=== All RuntimeActionExecutor Tests PASSED ===")
end

return M