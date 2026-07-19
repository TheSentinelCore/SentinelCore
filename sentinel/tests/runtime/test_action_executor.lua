-- sentinel/tests/runtime/test_action_executor.lua
-- Tests for runtime/action_executor.lua

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Runtime ActionExecutor Tests ===")

    -- Mock nav adapter for tests
    local mock_nav = {
        _state = "idle",
        move_to = function(self, target)
            self._state = "moving"
            self._target = target
            return true, nil
        end,
        poll = function(self)
            -- Advance state on each poll for testing
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
        is_active = function(self)
            return self._state == "moving"
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
            kill = function() return true end,
        }
        _G.core.object_manager = {
            get_all_objects = function() return {} end,
        }
        _G.core.game_time = function() return 0 end
    end

    setup_core()

    package.loaded["runtime/action_executor"] = nil
    local Executor = require("runtime/action_executor")

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local bb1 = Blackboard:new()
    local eb1 = EventBus:new()
    local ex1 = Executor:new(bb1, eb1, mock_nav)
    T.assert_not_nil(ex1, "executor should be created")
    local state1 = ex1:get_state()
    T.assert_equal(state1.status, nil, "no initial status")
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
    -- Test 3: Execute unknown action type
    -- =====================================================================
    print("Test 3: Execute unknown action type")
    local bb3 = Blackboard:new()
    local ex3 = Executor:new(bb3, EventBus:new(), mock_nav)
    local r3 = ex3:execute({ action_type = "nonexistent_action" })
    T.assert_equal(r3.status, "failed", "unknown action type should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Execute "wait" action (sync completion via poll cycle)
    -- =====================================================================
    print("Test 4: Execute wait action")
    local bb4 = Blackboard:new()
    local ex4 = Executor:new(bb4, EventBus:new(), mock_nav)
    local r4 = ex4:execute({ action_type = "wait", duration_ms = 50 })
    T.assert_equal(r4.status, "running", "wait should start as running")

    -- Simulate time passing
    _G.core.game_time = function() return 100 end
    local r4b = ex4:poll()
    T.assert_equal(r4b.status, "succeeded", "wait should complete after time passes")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Execute "set_variable" action
    -- =====================================================================
    print("Test 5: Execute set_variable action")
    local bb5 = Blackboard:new()
    local ex5 = Executor:new(bb5, EventBus:new(), mock_nav)
    local r5 = ex5:execute({ action_type = "set_variable", name = "test_var", value = 42 })
    T.assert_equal(r5.status, "succeeded", "set_variable should succeed")
    T.assert_equal(bb5:get("module.runtime.var.test_var"), 42, "variable should be set")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Execute "set_variable" without name
    -- =====================================================================
    print("Test 6: Execute set_variable without name")
    local bb6 = Blackboard:new()
    local ex6 = Executor:new(bb6, EventBus:new(), mock_nav)
    local r6 = ex6:execute({ action_type = "set_variable", value = 42 })
    T.assert_equal(r6.status, "failed", "set_variable without name should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Execute "pickup_quest" action
    -- =====================================================================
    print("Test 7: Execute pickup_quest action")
    local bb7 = Blackboard:new()
    local ex7 = Executor:new(bb7, EventBus:new(), mock_nav)
    local r7 = ex7:execute({ action_type = "pickup_quest", npc_guid = "npc-123", quest_id = 33 })
    T.assert_equal(r7.status, "succeeded", "pickup_quest should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Execute "pickup_quest" without guid
    -- =====================================================================
    print("Test 8: Execute pickup_quest without guid")
    local bb8 = Blackboard:new()
    local ex8 = Executor:new(bb8, EventBus:new(), mock_nav)
    local r8 = ex8:execute({ action_type = "pickup_quest", quest_id = 33 })
    T.assert_equal(r8.status, "failed", "pickup_quest without guid should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Execute "turn_in_quest" action
    -- =====================================================================
    print("Test 9: Execute turn_in_quest action")
    local bb9 = Blackboard:new()
    local ex9 = Executor:new(bb9, EventBus:new(), mock_nav)
    local r9 = ex9:execute({ action_type = "turn_in_quest", npc_guid = "npc-456", quest_id = 33 })
    T.assert_equal(r9.status, "succeeded", "turn_in_quest should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Execute "goto" action (async)
    -- =====================================================================
    print("Test 10: Execute goto action (async)")
    local bb10 = Blackboard:new()
    local nav10 = {
        _state = "idle",
        move_to = function(self, target)
            self._state = "moving"
            self._target = target
            return true, nil
        end,
        poll = function(self) end,
        get_state = function(self) return self._state end,
        stop = function(self) self._state = "idle" end,
        is_active = function(self) return self._state == "moving" end,
    }
    local ex10 = Executor:new(bb10, EventBus:new(), nav10)
    local r10 = ex10:execute({ action_type = "goto", target = { x = 10, y = 20, z = 30 } })
    T.assert_equal(r10.status, "running", "goto should start as running")

    -- Poll until done
    nav10._state = "idle" -- Simulate arrival
    local r10b = ex10:poll()
    T.assert_equal(r10b.status, "succeeded", "goto should complete when nav is idle")
    print("  PASS")

    -- =====================================================================
    -- Test 11: Execute "hearth" action
    -- =====================================================================
    print("Test 11: Execute hearth action")
    local bb11 = Blackboard:new()
    local ex11 = Executor:new(bb11, EventBus:new(), mock_nav)
    local r11 = ex11:execute({ action_type = "hearth" })
    T.assert_equal(r11.status, "succeeded", "hearth should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 12: Execute "branch" action
    -- =====================================================================
    print("Test 12: Execute branch action")
    local bb12 = Blackboard:new()
    bb12:set("player.level", 10)
    local ex12 = Executor:new(bb12, EventBus:new(), mock_nav)
    local r12 = ex12:execute({ action_type = "branch", condition = { type = "level_above", min_level = 5 } })
    T.assert_equal(r12.status, "succeeded", "branch should succeed")
    T.assert_equal(bb12:get("module.runtime.branch_result"), true, "branch result should be true")
    print("  PASS")

    -- =====================================================================
    -- Test 13: Execute "vendor" action
    -- =====================================================================
    print("Test 13: Execute vendor action")
    local bb13 = Blackboard:new()
    local ex13 = Executor:new(bb13, EventBus:new(), mock_nav)
    local r13 = ex13:execute({ action_type = "vendor", npc_guid = "npc-vendor-1" })
    T.assert_equal(r13.status, "succeeded", "vendor should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 14: Execute "vendor" without guid
    -- =====================================================================
    print("Test 14: Execute vendor without guid")
    local bb14 = Blackboard:new()
    local ex14 = Executor:new(bb14, EventBus:new(), mock_nav)
    local r14 = ex14:execute({ action_type = "vendor" })
    T.assert_equal(r14.status, "failed", "vendor without guid should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 15: Execute "repair" action
    -- =====================================================================
    print("Test 15: Execute repair action")
    local bb15 = Blackboard:new()
    local ex15 = Executor:new(bb15, EventBus:new(), mock_nav)
    local r15 = ex15:execute({ action_type = "repair", npc_guid = "npc-repair-1" })
    T.assert_equal(r15.status, "succeeded", "repair should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 16: Execute "talk_to_npc" action
    -- =====================================================================
    print("Test 16: Execute talk_to_npc action")
    local bb16 = Blackboard:new()
    local ex16 = Executor:new(bb16, EventBus:new(), mock_nav)
    local r16 = ex16:execute({ action_type = "talk_to_npc", npc_guid = "npc-gossip-1", gossip_option = 1 })
    T.assert_equal(r16.status, "succeeded", "talk_to_npc should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 17: Execute "dungeon_marker" action
    -- =====================================================================
    print("Test 17: Execute dungeon_marker action")
    local bb17 = Blackboard:new()
    local ex17 = Executor:new(bb17, EventBus:new(), mock_nav)
    local r17 = ex17:execute({ action_type = "dungeon_marker", marker = "enter_dungeon" })
    T.assert_equal(r17.status, "succeeded", "dungeon_marker should succeed")
    T.assert_true(bb17:get("module.runtime.dungeon_marker.enter_dungeon"), "marker should be set")
    print("  PASS")

    -- =====================================================================
    -- Test 18: Execute "use_item" action
    -- =====================================================================
    print("Test 18: Execute use_item action")
    local bb18 = Blackboard:new()
    local ex18 = Executor:new(bb18, EventBus:new(), mock_nav)
    local r18 = ex18:execute({ action_type = "use_item", item_id = 6948 })
    T.assert_equal(r18.status, "succeeded", "use_item should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 19: Execute "mailbox" action
    -- =====================================================================
    print("Test 19: Execute mailbox action")
    local bb19 = Blackboard:new()
    local ex19 = Executor:new(bb19, EventBus:new(), mock_nav)
    local r19 = ex19:execute({ action_type = "mailbox", object_guid = "obj-mailbox-1" })
    T.assert_equal(r19.status, "succeeded", "mailbox should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 20: Execute "bank" action
    -- =====================================================================
    print("Test 20: Execute bank action")
    local bb20 = Blackboard:new()
    local ex20 = Executor:new(bb20, EventBus:new(), mock_nav)
    local r20 = ex20:execute({ action_type = "bank", npc_guid = "npc-banker-1" })
    T.assert_equal(r20.status, "succeeded", "bank should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 21: Execute "train" action
    -- =====================================================================
    print("Test 21: Execute train action")
    local bb21 = Blackboard:new()
    local ex21 = Executor:new(bb21, EventBus:new(), mock_nav)
    local r21 = ex21:execute({ action_type = "train", npc_guid = "npc-trainer-1" })
    T.assert_equal(r21.status, "succeeded", "train should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 22: Execute "loot_object" action
    -- =====================================================================
    print("Test 22: Execute loot_object action")
    local bb22 = Blackboard:new()
    local ex22 = Executor:new(bb22, EventBus:new(), mock_nav)
    local r22 = ex22:execute({ action_type = "loot_object", object_guid = "obj-loot-1" })
    T.assert_equal(r22.status, "succeeded", "loot_object should succeed")
    print("  PASS")

    -- =====================================================================
    -- Test 23: Execute "death_skip" action
    -- =====================================================================
    print("Test 23: Execute death_skip action")
    local bb23 = Blackboard:new()
    local ex23 = Executor:new(bb23, EventBus:new(), mock_nav)
    local r23 = ex23:execute({ action_type = "death_skip" })
    T.assert_equal(r23.status, "running", "death_skip should start as running")
    T.assert_true(bb23:get("module.runtime.death_resurrecting"), "death_resurrecting should be set")

    -- Poll until dead
    _G.core.player.is_dead = function() return true end
    local r23b = ex23:poll()
    T.assert_equal(r23b.status, "succeeded", "death_skip should complete when dead")
    _G.core.player.is_dead = function() return false end
    print("  PASS")

    -- =====================================================================
    -- Test 24: Execute "record_path" action
    -- =====================================================================
    print("Test 24: Execute record_path action")
    local bb24 = Blackboard:new()
    local ex24 = Executor:new(bb24, EventBus:new(), mock_nav)
    local r24a = ex24:execute({ action_type = "record_path", mode = "start" })
    T.assert_equal(r24a.status, "succeeded", "record_path start should succeed")
    local rec = bb24:get("module.runtime.recording_path")
    T.assert_not_nil(rec, "recording state should be set")
    T.assert_true(rec.active, "recording should be active")

    local r24b = ex24:execute({ action_type = "record_path", mode = "stop" })
    T.assert_equal(r24b.status, "succeeded", "record_path stop should succeed")
    local rec2 = bb24:get("module.runtime.recording_path")
    T.assert_false(rec2.active, "recording should be inactive")
    print("  PASS")

    -- =====================================================================
    -- Test 25: Retry policy - action retries on failure
    -- =====================================================================
    print("Test 25: Retry policy basic")
    local bb25 = Blackboard:new()
    local ex25 = Executor:new(bb25, EventBus:new(), mock_nav)
    -- Create an action with an interact_unit that throws an error, causing retry
    local saved_interact = _G.core.input.interact_unit
    _G.core.input.interact_unit = function() error("NPC not found") end

    local r25 = ex25:execute({ action_type = "pickup_quest", npc_guid = "npc-1", retry_policy = { max_retries = 2, delay_ms = 10 } })
    T.assert_equal(r25.status, "running", "should be running (retrying)")
    T.assert_equal(r25.error, "retrying", "should indicate retrying")

    _G.core.input.interact_unit = saved_interact
    print("  PASS")

    -- =====================================================================
    -- Test 26: Timeout exceeded
    -- =====================================================================
    print("Test 26: Timeout exceeded")
    local bb26 = Blackboard:new()
    local ex26 = Executor:new(bb26, EventBus:new(), mock_nav)
    local start_time = 0
    _G.core.game_time = function() return start_time end
    local r26 = ex26:execute({ action_type = "wait", duration_ms = 10000, timeout_ms = 50 })
    T.assert_equal(r26.status, "running", "should start running")

    -- Advance time past timeout
    _G.core.game_time = function() return 200 end
    local r26b = ex26:poll()
    T.assert_equal(r26b.status, "failed", "should fail due to timeout")
    T.assert_equal(r26b.error, "timeout exceeded", "should indicate timeout")
    print("  PASS")

    print("\n=== All ActionExecutor Tests PASSED ===")
end

return M
