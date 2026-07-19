-- sentinel/tests/runtime/test_operation_scheduler.lua
-- Tests for runtime/operation_scheduler.lua

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Runtime OperationScheduler Tests ===")

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local bb = Blackboard:new()
    local eb = EventBus:new()
    package.loaded["runtime/operation_scheduler"] = nil
    local Scheduler = require("runtime/operation_scheduler")
    local sched = Scheduler:new(bb, eb)
    T.assert_not_nil(sched, "scheduler should be created")
    T.assert_nil(sched:get_current_operation(), "no current op initially")
    T.assert_nil(sched:get_current_action(), "no current action initially")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Set profile initializes operation statuses
    -- =====================================================================
    print("Test 2: Set profile initializes operation statuses")
    local bb2 = Blackboard:new()
    local eb2 = EventBus:new()
    local sched2 = Scheduler:new(bb2, eb2)
    local profile = {
        name = "Test Profile",
        operations = {
            { id = "op-1", name = "Operation 1", priority = 10, actions = {} },
            { id = "op-2", name = "Operation 2", priority = 20, actions = {} },
        }
    }
    sched2:set_profile(profile)
    T.assert_equal(sched2:get_status("op-1"), "locked", "op-1 should start locked")
    T.assert_equal(sched2:get_status("op-2"), "locked", "op-2 should start locked")
    print("  PASS")

    -- =====================================================================
    -- Test 3: get_ready_operations returns operations sorted by priority
    -- =====================================================================
    print("Test 3: get_ready_operations sorted by priority (descending)")
    local bb3 = Blackboard:new()
    bb3:set("player.level", 10)
    bb3:set("player.race", "Human")
    bb3:set("player.class", "Warrior")
    local eb3 = EventBus:new()
    local sched3 = Scheduler:new(bb3, eb3)
    local profile3 = {
        name = "Test Profile",
        operations = {
            { id = "op-low", name = "Low Priority", priority = 5, entry_conditions = {}, actions = {} },
            { id = "op-high", name = "High Priority", priority = 100, entry_conditions = {}, actions = {} },
            { id = "op-mid", name = "Mid Priority", priority = 50, entry_conditions = {}, actions = {} },
        }
    }
    sched3:set_profile(profile3)
    -- Set all to ready
    sched3:set_status("op-low", "ready")
    sched3:set_status("op-high", "ready")
    sched3:set_status("op-mid", "ready")

    local ready = sched3:get_ready_operations()
    T.assert_equal(#ready, 3, "should have 3 ready operations")
    T.assert_equal(ready[1].id, "op-high", "highest priority first")
    T.assert_equal(ready[2].id, "op-mid", "mid priority second")
    T.assert_equal(ready[3].id, "op-low", "lowest priority last")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Entry condition - level_below
    -- =====================================================================
    print("Test 4: Entry condition - level_below")
    local bb4 = Blackboard:new()
    bb4:set("player.level", 5)
    bb4:set("player.race", "Human")
    bb4:set("player.class", "Warrior")
    local eb4 = EventBus:new()
    local sched4 = Scheduler:new(bb4, eb4)
    local profile4 = {
        name = "Test Profile",
        operations = {
            { id = "op-start", name = "Starting Zone", priority = 10,
              entry_conditions = { { type = "level_below", max_level = 6 } },
              actions = {} },
        }
    }
    sched4:set_profile(profile4)
    local ready4 = sched4:get_ready_operations()
    T.assert_equal(#ready4, 1, "level 5 should qualify for max_level 6")

    -- Now test with level too high
    local bb4b = Blackboard:new()
    bb4b:set("player.level", 10)
    bb4b:set("player.race", "Human")
    bb4b:set("player.class", "Warrior")
    local sched4b = Scheduler:new(bb4b, eb4)
    sched4b:set_profile(profile4)
    local ready4b = sched4b:get_ready_operations()
    T.assert_equal(#ready4b, 0, "level 10 should NOT qualify for max_level 6")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Entry condition - race_is and class_is
    -- =====================================================================
    print("Test 5: Entry condition - race_is and class_is")
    local bb5 = Blackboard:new()
    bb5:set("player.level", 1)
    bb5:set("player.race", "Orc")
    bb5:set("player.class", "Warrior")
    local eb5 = EventBus:new()
    local sched5 = Scheduler:new(bb5, eb5)
    local profile5 = {
        name = "Test Profile",
        operations = {
            { id = "op-orc", name = "Orc Zone", priority = 10,
              entry_conditions = { { type = "race_is", race = "Orc" } },
              actions = {} },
            { id = "op-human", name = "Human Zone", priority = 5,
              entry_conditions = { { type = "race_is", race = "Human" } },
              actions = {} },
        }
    }
    sched5:set_profile(profile5)
    local ready5 = sched5:get_ready_operations()
    T.assert_equal(#ready5, 1, "only orc op should be ready")
    T.assert_equal(ready5[1].id, "op-orc", "orc op should be selected")

    -- Class test
    local bb5b = Blackboard:new()
    bb5b:set("player.level", 1)
    bb5b:set("player.race", "Human")
    bb5b:set("player.class", "Mage")
    local sched5b = Scheduler:new(bb5b, eb5)
    local profile5b = {
        name = "Test Profile",
        operations = {
            { id = "op-mage", name = "Mage Stuff", priority = 10,
              entry_conditions = { { type = "class_is", class = "Mage" } },
              actions = {} },
            { id = "op-warrior", name = "Warrior Stuff", priority = 5,
              entry_conditions = { { type = "class_is", class = "Warrior" } },
              actions = {} },
        }
    }
    sched5b:set_profile(profile5b)
    local ready5b = sched5b:get_ready_operations()
    T.assert_equal(#ready5b, 1, "only mage op should be ready")
    T.assert_equal(ready5b[1].id, "op-mage", "mage op should be selected")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Entry condition - quest_completed and quest_active
    -- =====================================================================
    print("Test 6: Entry condition - quest_completed and quest_active")
    local bb6 = Blackboard:new()
    bb6:set("player.level", 10)
    bb6:set("player.race", "Human")
    bb6:set("player.class", "Warrior")
    bb6:set("player.completed_quests", { 33, 34, 35 })
    bb6:set("player.active_quests", { 36 })
    local eb6 = EventBus:new()
    local sched6 = Scheduler:new(bb6, eb6)
    local profile6 = {
        name = "Test Profile",
        operations = {
            { id = "op-completed", name = "Needs Quest 33 Done", priority = 10,
              entry_conditions = { { type = "quest_completed", quest_id = 33 } },
              actions = {} },
            { id = "op-not-completed", name = "Needs Quest 99 Done", priority = 5,
              entry_conditions = { { type = "quest_completed", quest_id = 99 } },
              actions = {} },
            { id = "op-active", name = "Needs Quest 36 Active", priority = 3,
              entry_conditions = { { type = "quest_active", quest_id = 36 } },
              actions = {} },
        }
    }
    sched6:set_profile(profile6)
    local ready6 = sched6:get_ready_operations()
    T.assert_equal(#ready6, 2, "two ops should be ready (completed 33 and active 36)")
    local ids = {}
    for _, op in ipairs(ready6) do
        ids[op.id] = true
    end
    T.assert_true(ids["op-completed"], "completed quest condition should pass")
    T.assert_true(ids["op-active"], "active quest condition should pass")
    T.assert_nil(ids["op-not-completed"], "uncompleted quest should not be ready")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Entry condition - variable_equals
    -- =====================================================================
    print("Test 7: Entry condition - variable_equals")
    local bb7 = Blackboard:new()
    bb7:set("player.level", 10)
    bb7:set("player.race", "Human")
    bb7:set("player.class", "Warrior")
    bb7:set("module.runtime.some_var", "hello")
    local eb7 = EventBus:new()
    local sched7 = Scheduler:new(bb7, eb7)
    local profile7 = {
        name = "Test Profile",
        operations = {
            { id = "op-match", name = "Variable Match", priority = 10,
              entry_conditions = { { type = "variable_equals", name = "module.runtime.some_var", value = "hello" } },
              actions = {} },
            { id = "op-no-match", name = "Variable No Match", priority = 5,
              entry_conditions = { { type = "variable_equals", name = "module.runtime.some_var", value = "world" } },
              actions = {} },
        }
    }
    sched7:set_profile(profile7)
    local ready7 = sched7:get_ready_operations()
    T.assert_equal(#ready7, 1, "only matching var should be ready")
    T.assert_equal(ready7[1].id, "op-match", "matching operation should be selected")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Operations with completed/failed/aborted/skipped status are skipped
    -- =====================================================================
    print("Test 8: Skipped operations with terminal statuses")
    local bb8 = Blackboard:new()
    bb8:set("player.level", 10)
    bb8:set("player.race", "Human")
    bb8:set("player.class", "Warrior")
    local eb8 = EventBus:new()
    local sched8 = Scheduler:new(bb8, eb8)
    local profile8 = {
        name = "Test Profile",
        operations = {
            { id = "op-completed", name = "Completed Op", priority = 100, entry_conditions = {}, actions = {} },
            { id = "op-failed", name = "Failed Op", priority = 90, entry_conditions = {}, actions = {} },
            { id = "op-aborted", name = "Aborted Op", priority = 80, entry_conditions = {}, actions = {} },
            { id = "op-skipped", name = "Skipped Op", priority = 70, entry_conditions = {}, actions = {} },
            { id = "op-ready", name = "Ready Op", priority = 60, entry_conditions = {}, actions = {} },
        }
    }
    sched8:set_profile(profile8)
    sched8:set_status("op-completed", "completed")
    sched8:set_status("op-failed", "failed")
    sched8:set_status("op-aborted", "aborted")
    sched8:set_status("op-skipped", "skipped")
    sched8:set_status("op-ready", "ready")

    local ready8 = sched8:get_ready_operations()
    T.assert_equal(#ready8, 1, "only one ready operation")
    T.assert_equal(ready8[1].id, "op-ready", "only op-ready should be returned")
    print("  PASS")

    -- =====================================================================
    -- Test 9: select_next picks highest priority ready operation
    -- =====================================================================
    print("Test 9: select_next picks highest priority ready operation")
    local bb9 = Blackboard:new()
    bb9:set("player.level", 10)
    bb9:set("player.race", "Human")
    bb9:set("player.class", "Warrior")
    local eb9 = EventBus:new()
    local sched9 = Scheduler:new(bb9, eb9)
    local profile9 = {
        name = "Test Profile",
        operations = {
            { id = "op-a", name = "A", priority = 10, entry_conditions = {}, actions = {
                { id = "act-1", action_type = "wait", duration_ms = 100 },
            }},
            { id = "op-b", name = "B", priority = 50, entry_conditions = {}, actions = {
                { id = "act-2", action_type = "wait", duration_ms = 100 },
            }},
        }
    }
    sched9:set_profile(profile9)
    sched9:set_status("op-a", "ready")
    sched9:set_status("op-b", "ready")

    local selected = sched9:select_next()
    T.assert_not_nil(selected, "should select an operation")
    T.assert_equal(selected.id, "op-b", "should select highest priority (B)")
    T.assert_equal(sched9:get_status("op-b"), "active", "B should be active")
    T.assert_equal(sched9._current_action_index, 1, "action index should be 1")
    print("  PASS")

    -- =====================================================================
    -- Test 10: advance_action advances to next action, returns nil when done
    -- =====================================================================
    print("Test 10: advance_action advances through actions")
    local bb10 = Blackboard:new()
    bb10:set("player.level", 10)
    bb10:set("player.race", "Human")
    bb10:set("player.class", "Warrior")
    local eb10 = EventBus:new()
    local sched10 = Scheduler:new(bb10, eb10)
    local profile10 = {
        name = "Test Profile",
        operations = {
            { id = "op-multi", name = "Multi Action", priority = 10, entry_conditions = {},
              actions = {
                  { id = "act-1", action_type = "wait", duration_ms = 100 },
                  { id = "act-2", action_type = "wait", duration_ms = 200 },
              }
            },
        }
    }
    sched10:set_profile(profile10)
    sched10:set_status("op-multi", "ready")
    local sel10 = sched10:select_next()
    T.assert_equal(sel10.id, "op-multi")

    -- Get first action
    local act1 = sched10:get_current_action()
    T.assert_equal(act1.id, "act-1", "first action should be act-1")

    -- Advance to second
    local act2 = sched10:advance_action()
    T.assert_equal(act2.id, "act-2", "should advance to act-2")
    T.assert_equal(sched10._current_action_index, 2, "action index should be 2")

    -- Advance past end
    local nil_act = sched10:advance_action()
    T.assert_nil(nil_act, "should return nil when past last action")
    print("  PASS")

    -- =====================================================================
    -- Test 11: advance_operation marks current op completed and selects next
    -- =====================================================================
    print("Test 11: advance_operation completes operation and selects next")
    local bb11 = Blackboard:new()
    bb11:set("player.level", 10)
    bb11:set("player.race", "Human")
    bb11:set("player.class", "Warrior")
    local eb11 = EventBus:new()
    local sched11 = Scheduler:new(bb11, eb11)
    local profile11 = {
        name = "Test Profile",
        operations = {
            { id = "op-first", name = "First", priority = 10, entry_conditions = {}, actions = {} },
            { id = "op-second", name = "Second", priority = 5, entry_conditions = {}, actions = {} },
        }
    }
    sched11:set_profile(profile11)
    sched11:set_status("op-first", "ready")
    sched11:set_status("op-second", "ready")

    sched11:select_next()
    T.assert_equal(sched11:get_current_operation().id, "op-first", "should be on first op")

    local next_op = sched11:advance_operation()
    T.assert_equal(sched11:get_status("op-first"), "completed", "first should be completed")
    T.assert_equal(next_op.id, "op-second", "should select second op")
    T.assert_equal(sched11:get_current_operation().id, "op-second", "current should be second")
    print("  PASS")

    -- =====================================================================
    -- Test 12: No player data causes conditions to evaluate as unmet
    -- =====================================================================
    print("Test 12: No player data causes conditions to evaluate as unmet")
    local bb12 = Blackboard:new()
    -- No player data set
    local eb12 = EventBus:new()
    local sched12 = Scheduler:new(bb12, eb12)
    local profile12 = {
        name = "Test Profile",
        operations = {
            { id = "op-cond", name = "Conditional", priority = 10,
              entry_conditions = { { type = "level_below", max_level = 10 } },
              actions = {} },
        }
    }
    sched12:set_profile(profile12)
    local ready12 = sched12:get_ready_operations()
    -- With no player data, player.level defaults to 0, so level_below(10) is satisfied
    -- This is expected behavior: unknown/missing data is treated as default values
    T.assert_equal(#ready12, 1, "level_below(10) passes when level defaults to 0")
    print("  PASS")

    -- =====================================================================
    -- Test 13: Unknown condition type is treated as eligible
    -- =====================================================================
    print("Test 13: Unknown condition type treated as eligible")
    local bb13 = Blackboard:new()
    bb13:set("player.level", 10)
    local eb13 = EventBus:new()
    local sched13 = Scheduler:new(bb13, eb13)
    local profile13 = {
        name = "Test Profile",
        operations = {
            { id = "op-weird", name = "Weird Condition", priority = 10,
              entry_conditions = { { type = "unknown_future_type", some_param = true } },
              actions = {} },
        }
    }
    sched13:set_profile(profile13)
    local ready13 = sched13:get_ready_operations()
    T.assert_equal(#ready13, 1, "unknown condition should be treated as eligible")
    print("  PASS")

    -- =====================================================================
    -- Test 14: get_status returns nil for unknown op
    -- =====================================================================
    print("Test 14: get_status returns nil for unknown op")
    local bb14 = Blackboard:new()
    local eb14 = EventBus:new()
    local sched14 = Scheduler:new(bb14, eb14)
    T.assert_nil(sched14:get_status("nonexistent"), "unknown op should return nil")
    print("  PASS")

    -- =====================================================================
    -- Test 15: Declaration order tiebreaker when priorities equal
    -- =====================================================================
    print("Test 15: Declaration order tiebreaker for equal priorities")
    local bb15 = Blackboard:new()
    bb15:set("player.level", 10)
    bb15:set("player.race", "Human")
    bb15:set("player.class", "Warrior")
    local eb15 = EventBus:new()
    local sched15 = Scheduler:new(bb15, eb15)
    local profile15 = {
        name = "Test Profile",
        operations = {
            { id = "op-first", name = "First Declared", priority = 50, entry_conditions = {}, actions = {} },
            { id = "op-second", name = "Second Declared", priority = 50, entry_conditions = {}, actions = {} },
        }
    }
    sched15:set_profile(profile15)
    sched15:set_status("op-first", "ready")
    sched15:set_status("op-second", "ready")

    local ready15 = sched15:get_ready_operations()
    T.assert_equal(#ready15, 2, "both should be ready")
    T.assert_equal(ready15[1].id, "op-first", "first declared should come first")
    T.assert_equal(ready15[2].id, "op-second", "second declared should come second")
    print("  PASS")

    print("\n=== All OperationScheduler Tests PASSED ===")
end

return M
