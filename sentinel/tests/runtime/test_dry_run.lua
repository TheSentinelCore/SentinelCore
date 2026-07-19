-- sentinel/tests/runtime/test_dry_run.lua
-- Tests for runtime/dry_run.lua

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local OperationScheduler = require("runtime/operation_scheduler")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Dry Run Tests ===")

    -- =====================================================================
    -- Test 1: Construction and basic API surface
    -- =====================================================================
    print("Test 1: Construction and API surface")
    local bb = Blackboard:new()
    bb:set("player.level", 10)
    bb:set("player.race", "Human")
    bb:set("player.class", "Warrior")
    local eb = EventBus:new()
    local sched = OperationScheduler:new(bb, eb)
    local profile = {
        name = "Dry Run Test",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-1",
        operations = {},
    }
    sched:set_profile(profile)

    package.loaded["runtime/dry_run"] = nil
    local DryRun = require("runtime/dry_run")
    local dr = DryRun:new(sched, nil, bb, eb)

    T.assert_not_nil(dr, "DryRun should construct")
    T.assert_not_nil(dr.start, "should have start method")
    T.assert_not_nil(dr.pause, "should have pause method")
    T.assert_not_nil(dr.step, "should have step method")
    T.assert_not_nil(dr.reset, "should have reset method")
    T.assert_not_nil(dr.get_trace, "should have get_trace method")
    T.assert_equal(#dr:get_trace(), 0, "trace should start empty")
    print("  PASS")

    -- =====================================================================
    -- Test 2: start() sets blackboard flag
    -- =====================================================================
    print("Test 2: start() sets dry_run flag in blackboard")
    local bb2 = Blackboard:new()
    bb2:set("player.level", 10)
    bb2:set("player.race", "Human")
    bb2:set("player.class", "Warrior")
    local eb2 = EventBus:new()
    local sched2 = OperationScheduler:new(bb2, eb2)
    local profile2 = {
        name = "Dry Run Test 2",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-2",
        operations = {},
    }
    sched2:set_profile(profile2)
    local dr2 = DryRun:new(sched2, nil, bb2, eb2)

    T.assert_nil(bb2:get("module.runtime.dry_run"), "flag should not be set before start")
    dr2:start()
    T.assert_equal(bb2:get("module.runtime.dry_run"), true, "flag should be set after start")
    print("  PASS")

    -- =====================================================================
    -- Test 3: step() advances through actions in an operation
    -- =====================================================================
    print("Test 3: step() advances through actions in a single operation")
    local bb3 = Blackboard:new()
    bb3:set("player.level", 10)
    bb3:set("player.race", "Human")
    bb3:set("player.class", "Warrior")
    local eb3 = EventBus:new()
    local sched3 = OperationScheduler:new(bb3, eb3)
    local profile3 = {
        name = "Dry Run Test 3",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-3",
        operations = {
            {
                id = "op-seq",
                name = "Sequence",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-1", action_type = "wait", duration_ms = 100 },
                    { id = "act-2", action_type = "wait", duration_ms = 200 },
                    { id = "act-3", action_type = "wait", duration_ms = 300 },
                }
            }
        }
    }
    sched3:set_profile(profile3)
    local dr3 = DryRun:new(sched3, nil, bb3, eb3)
    dr3:start()

    -- Step through each action
    local r1 = dr3:step()
    T.assert_not_nil(r1, "step should return result")
    T.assert_equal(r1.action_id, "act-1", "first action should be act-1")

    local r2 = dr3:step()
    T.assert_equal(r2.action_id, "act-2", "second action should be act-2")

    local r3 = dr3:step()
    T.assert_equal(r3.action_id, "act-3", "third action should be act-3")

    -- After all actions done, step returns nil
    local r4, err4 = dr3:step()
    T.assert_nil(r4, "step should return nil when no more actions")
    T.assert_not_nil(err4, "should provide error message")

    -- Trace should have 3 entries
    local trace = dr3:get_trace()
    T.assert_equal(#trace, 3, "trace should have 3 entries")
    print("  PASS")

    -- =====================================================================
    -- Test 4: reset() clears trace and state
    -- =====================================================================
    print("Test 4: reset() clears trace and state")
    local bb4 = Blackboard:new()
    bb4:set("player.level", 5)
    bb4:set("player.race", "Human")
    bb4:set("player.class", "Warrior")
    local eb4 = EventBus:new()
    local sched4 = OperationScheduler:new(bb4, eb4)
    local profile4 = {
        name = "Dry Run Test 4",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-4",
        operations = {
            {
                id = "op-reset",
                name = "Reset Test",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-r1", action_type = "wait" },
                }
            }
        }
    }
    sched4:set_profile(profile4)
    local dr4 = DryRun:new(sched4, nil, bb4, eb4)
    dr4:start()
    dr4:step()
    T.assert_equal(#dr4:get_trace(), 1, "trace should have 1 entry after step")

    dr4:reset()
    T.assert_equal(#dr4:get_trace(), 0, "trace should be empty after reset")
    T.assert_equal(dr4:is_started(), false, "should not be started after reset")
    T.assert_nil(bb4:get("module.runtime.dry_run"), "flag should be cleared after reset")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Trace entries have correct structure
    -- =====================================================================
    print("Test 5: Trace entries have correct structure")
    local bb5 = Blackboard:new()
    bb5:set("player.level", 10)
    bb5:set("player.race", "Human")
    bb5:set("player.class", "Warrior")
    local eb5 = EventBus:new()
    local sched5 = OperationScheduler:new(bb5, eb5)
    local profile5 = {
        name = "Dry Run Test 5",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-5",
        operations = {
            {
                id = "op-struct",
                name = "Structure Test",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-hello", action_type = "wait" },
                }
            }
        }
    }
    sched5:set_profile(profile5)
    local dr5 = DryRun:new(sched5, nil, bb5, eb5)
    dr5:start()
    local entry = dr5:step()

    T.assert_not_nil(entry, "entry should not be nil")
    T.assert_equal(entry.action_id, "act-hello", "should have action_id")
    T.assert_equal(entry.action_type, "wait", "should have action_type")
    T.assert_equal(entry.result, "pass", "wait should always pass")
    T.assert_not_nil(entry.message, "should have message")
    print("  PASS")

    -- =====================================================================
    -- Test 6: pause and resume
    -- =====================================================================
    print("Test 6: pause and resume")
    local bb6 = Blackboard:new()
    bb6:set("player.level", 10)
    bb6:set("player.race", "Human")
    bb6:set("player.class", "Warrior")
    local eb6 = EventBus:new()
    local sched6 = OperationScheduler:new(bb6, eb6)
    local profile6 = {
        name = "Dry Run Test 6",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-6",
        operations = {
            {
                id = "op-pause",
                name = "Pause Test",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-p1", action_type = "wait" },
                }
            }
        }
    }
    sched6:set_profile(profile6)
    local dr6 = DryRun:new(sched6, nil, bb6, eb6)
    dr6:start()
    T.assert_equal(dr6:is_paused(), false, "should not be paused after start")

    dr6:pause()
    T.assert_equal(dr6:is_paused(), true, "should be paused")

    local result, err = dr6:step()
    T.assert_nil(result, "step should return nil when paused")
    T.assert_not_nil(err, "should indicate paused")

    dr6:resume()
    T.assert_equal(dr6:is_paused(), false, "should not be paused after resume")

    local r6 = dr6:step()
    T.assert_not_nil(r6, "step should work after resume")
    print("  PASS")

    -- =====================================================================
    -- Test 7: set_variable action executes normally
    -- =====================================================================
    print("Test 7: set_variable action executes normally")
    local bb7 = Blackboard:new()
    bb7:set("player.level", 10)
    bb7:set("player.race", "Human")
    bb7:set("player.class", "Warrior")
    local eb7 = EventBus:new()
    local sched7 = OperationScheduler:new(bb7, eb7)
    local profile7 = {
        name = "Dry Run Test 7",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-7",
        operations = {
            {
                id = "op-var",
                name = "Variable Test",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-v1", action_type = "set_variable", name = "test_var", value = "hello_dry" },
                }
            }
        }
    }
    sched7:set_profile(profile7)
    local dr7 = DryRun:new(sched7, nil, bb7, eb7)
    dr7:start()
    dr7:step()

    T.assert_equal(bb7:get("module.runtime.var.test_var"), "hello_dry", "variable should be set")
    print("  PASS")

    -- =====================================================================
    -- Test 8: NPC existence check — known NPC passes
    -- =====================================================================
    print("Test 8: NPC existence check — known NPC passes")
    local bb8 = Blackboard:new()
    bb8:set("player.level", 10)
    bb8:set("player.race", "Human")
    bb8:set("player.class", "Warrior")
    local eb8 = EventBus:new()
    local sched8 = OperationScheduler:new(bb8, eb8)
    local profile8 = {
        name = "Dry Run Test 8",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-8",
        operations = {
            {
                id = "op-vendor",
                name = "Vendor Test",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-vendor", action_type = "vendor", npc_guid = "npc-123" },
                }
            }
        }
    }
    sched8:set_profile(profile8)
    local dr8 = DryRun:new(sched8, nil, bb8, eb8)
    dr8:set_known_npcs({
        { guid = "npc-123", exists = true },
        { guid = "npc-999", exists = false },
    })
    dr8:start()
    local r8 = dr8:step()
    T.assert_equal(r8.result, "pass", "known NPC should pass")
    print("  PASS")

    -- =====================================================================
    -- Test 9: NPC existence check — unknown NPC fails
    -- =====================================================================
    print("Test 9: NPC existence check — unknown NPC fails")
    local bb9 = Blackboard:new()
    bb9:set("player.level", 10)
    bb9:set("player.race", "Human")
    bb9:set("player.class", "Warrior")
    local eb9 = EventBus:new()
    local sched9 = OperationScheduler:new(bb9, eb9)
    local profile9 = {
        name = "Dry Run Test 9",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-9",
        operations = {
            {
                id = "op-train",
                name = "Train Test",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-train", action_type = "train", npc_guid = "npc-unknown" },
                }
            }
        }
    }
    sched9:set_profile(profile9)
    local dr9 = DryRun:new(sched9, nil, bb9, eb9)
    dr9:set_known_npcs({
        { guid = "npc-123", exists = true },
    })
    dr9:start()
    local r9 = dr9:step()
    T.assert_equal(r9.result, "fail", "unknown NPC should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Creature existence check — known creature passes
    -- =====================================================================
    print("Test 10: Creature existence check — known creature passes")
    local bb10 = Blackboard:new()
    bb10:set("player.level", 10)
    bb10:set("player.race", "Human")
    bb10:set("player.class", "Warrior")
    local eb10 = EventBus:new()
    local sched10 = OperationScheduler:new(bb10, eb10)
    local profile10 = {
        name = "Dry Run Test 10",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-10",
        operations = {
            {
                id = "op-kill",
                name = "Kill Test",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-kill", action_type = "kill_target", creature_entry = 1234 },
                }
            }
        }
    }
    sched10:set_profile(profile10)
    local dr10 = DryRun:new(sched10, nil, bb10, eb10)
    dr10:set_known_creatures({
        { entry = 1234, exists = true },
    })
    dr10:start()
    local r10 = dr10:step()
    T.assert_equal(r10.result, "pass", "known creature should pass")
    print("  PASS")

    -- =====================================================================
    -- Test 11: Creature existence check — unknown creature fails
    -- =====================================================================
    print("Test 11: Creature existence check — unknown creature fails")
    local bb11 = Blackboard:new()
    bb11:set("player.level", 10)
    bb11:set("player.race", "Human")
    bb11:set("player.class", "Warrior")
    local eb11 = EventBus:new()
    local sched11 = OperationScheduler:new(bb11, eb11)
    local profile11 = {
        name = "Dry Run Test 11",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-11",
        operations = {
            {
                id = "op-grind",
                name = "Grind Test",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-grind", action_type = "grind_area", mob_ids = { 9999 } },
                }
            }
        }
    }
    sched11:set_profile(profile11)
    local dr11 = DryRun:new(sched11, nil, bb11, eb11)
    dr11:set_known_creatures({
        { entry = 1234, exists = true },
    })
    dr11:start()
    local r11 = dr11:step()
    T.assert_equal(r11.result, "fail", "unknown creature should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 12: branch action evaluates normally
    -- =====================================================================
    print("Test 12: branch action evaluates condition")
    local bb12 = Blackboard:new()
    bb12:set("player.level", 25)
    bb12:set("player.race", "Human")
    bb12:set("player.class", "Warrior")
    local eb12 = EventBus:new()
    local sched12 = OperationScheduler:new(bb12, eb12)
    local profile12 = {
        name = "Dry Run Test 12",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-12",
        operations = {
            {
                id = "op-branch",
                name = "Branch Test",
                priority = 10,
                entry_conditions = {},
                actions = {
                    { id = "act-branch", action_type = "branch", condition = { type = "level_above", min_level = 20 } },
                }
            }
        }
    }
    sched12:set_profile(profile12)
    local dr12 = DryRun:new(sched12, nil, bb12, eb12)
    dr12:start()
    local r12 = dr12:step()
    T.assert_equal(r12.result, "pass", "branch should pass")
    T.assert_equal(bb12:get("module.runtime.branch_result"), true, "branch result should be true (level 25 >= 20)")
    print("  PASS")

    -- =====================================================================
    -- Test 13: Multiple operations in priority order
    -- =====================================================================
    print("Test 13: Multiple operations processed in priority order")
    local bb13 = Blackboard:new()
    bb13:set("player.level", 10)
    bb13:set("player.race", "Human")
    bb13:set("player.class", "Warrior")
    local eb13 = EventBus:new()
    local sched13 = OperationScheduler:new(bb13, eb13)
    local profile13 = {
        name = "Dry Run Test 13",
        author = "Test",
        schema_version = "1.0",
        id = "dry-run-13",
        operations = {
            {
                id = "op-low",
                name = "Low Priority",
                priority = 5,
                entry_conditions = {},
                actions = {
                    { id = "act-low", action_type = "set_variable", name = "seen", value = "low" },
                }
            },
            {
                id = "op-high",
                name = "High Priority",
                priority = 100,
                entry_conditions = {},
                actions = {
                    { id = "act-high", action_type = "set_variable", name = "seen", value = "high" },
                }
            },
        }
    }
    sched13:set_profile(profile13)
    local dr13 = DryRun:new(sched13, nil, bb13, eb13)
    dr13:start()

    -- First step should process high priority operation
    local r13a = dr13:step()
    T.assert_equal(r13a.action_id, "act-high", "high priority action first")
    T.assert_equal(bb13:get("module.runtime.var.seen"), "high", "high priority var set")

    -- Second step should process low priority
    local r13b = dr13:step()
    T.assert_equal(r13b.action_id, "act-low", "low priority action second")
    T.assert_equal(bb13:get("module.runtime.var.seen"), "low", "low priority var set")
    print("  PASS")

    print("\n=== All Dry Run Tests PASSED ===")
end

return M
