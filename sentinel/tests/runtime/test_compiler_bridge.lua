-- sentinel/tests/runtime/test_compiler_bridge.lua
-- Tests for runtime/compiler_bridge.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Runtime CompilerBridge Tests ===")

    -- Clear package cache
    package.loaded["runtime/compiler_bridge"] = nil
    package.loaded["runtime/migration_registry"] = nil
    package.loaded["runtime/blueprint_registry"] = nil
    -- Clear the shared LoweringStage profile cache so tests don't collide
    -- on the same profile name (the cache is keyed by profile id/name, and
    -- several tests below use the default "Test Profile" name).
    local LoweringStage = require("runtime/stage_lowering")
    LoweringStage.clear_cache()

    local Blackboard = require("core/blackboard")
    local EventBus = require("core/event_bus")
    local CompilerBridge = require("runtime/compiler_bridge")
    local ProfileManager = require("runtime/profile_manager")
    local BlueprintRegistry = require("runtime/blueprint_registry")

    -- Helper: create a valid profile
    local function make_profile(overrides)
        overrides = overrides or {}
        return {
            name = overrides.name or "Test Profile",
            author = overrides.author or "Test Author",
            schema_version = overrides.schema_version or "1.0.0",
            operations = overrides.operations or {},
            metadata = overrides.metadata or { compiler_version = "1.0.0" },
        }
    end

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local bb1 = Blackboard:new()
    local eb1 = EventBus:new()
    local pm1 = ProfileManager:new()
    local cb1 = CompilerBridge:new(bb1, eb1, pm1)
    T.assert_not_nil(cb1, "should construct")
    T.assert_false(cb1:is_compiling(), "should not be compiling initially")
    T.assert_nil(cb1:get_last_result(), "should have no last result initially")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Compile empty profile returns valid RuntimeProfile
    -- =====================================================================
    print("Test 2: Compile empty profile returns valid RuntimeProfile")
    local bb2 = Blackboard:new()
    local eb2 = EventBus:new()
    local pm2 = ProfileManager:new()
    local profile2 = make_profile({ name = "Empty Test Profile" })
    pm2:set_active_profile(profile2)
    local cb2 = CompilerBridge:new(bb2, eb2, pm2)

    local compile_result = nil
    local compile_error = nil
    cb2:compile(function(err, runtime_profile)
        compile_error = err
        compile_result = runtime_profile
    end)

    T.assert_nil(compile_error, "should compile without error")
    T.assert_not_nil(compile_result, "should return a runtime profile")
    T.assert_equal(compile_result.schema_version, "1.0",
        "schema_version should be 1.0")
    T.assert_equal(compile_result.compiler_version, "0.1.0",
        "compiler_version should be 0.1.0")
    T.assert_equal(compile_result.profile_id, "Empty Test Profile",
        "profile_id should match profile name")
    T.assert_not_nil(compile_result.metadata.compiled_at,
        "should have compiled_at timestamp")
    T.assert_equal(#compile_result.operations, 0,
        "should have empty operations")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Compile with operations transforms them correctly
    -- =====================================================================
    print("Test 3: Compile with operations transforms them correctly")
    local bb3 = Blackboard:new()
    local eb3 = EventBus:new()
    local pm3 = ProfileManager:new()
    local profile3 = make_profile({
        operations = {
            {
                id = "op-1",
                name = "Grind",
                action_type = "grind",
                priority = 50,
                entry_conditions = {
                    { type = "health", operator = ">", value = 20 },
                },
                goals = {
                    { type = "xp", value = 100 },
                },
                actions = {
                    { id = "act-1", action_type = "goto", params = { target = { x = 10, y = 20 } } },
                    { id = "act-2", action_type = "wait", params = { duration_ms = 1000 } },
                },
            },
        },
    })
    pm3:set_active_profile(profile3)
    local cb3 = CompilerBridge:new(bb3, eb3, pm3)

    local comp3_result = nil
    cb3:compile(function(err, rp)
        comp3_result = rp
    end)

    T.assert_not_nil(comp3_result, "should return runtime profile")
    T.assert_equal(#comp3_result.operations, 1, "should have 1 operation")
    T.assert_equal(comp3_result.operations[1].id, "op-1")
    T.assert_equal(comp3_result.operations[1].name, "Grind")
    T.assert_equal(#comp3_result.operations[1].entry_conditions, 1,
        "should preserve entry conditions")
    T.assert_equal(#comp3_result.operations[1].goals, 1,
        "should preserve goals")
    T.assert_equal(#comp3_result.operations[1].actions, 2,
        "should have 2 actions")
    T.assert_equal(comp3_result.operations[1].actions[1].id, "act-1")
    T.assert_equal(comp3_result.operations[1].actions[2].payload.type, "wait")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Compile with duplicate IDs returns validation error
    -- =====================================================================
    print("Test 4: Compile with duplicate IDs returns validation error")
    local bb4 = Blackboard:new()
    local eb4 = EventBus:new()
    local pm4 = ProfileManager:new()
    local profile4 = make_profile({
        operations = {
            { id = "dup-1", name = "Op1" },
            { id = "dup-1", name = "Op2" },
        },
    })
    pm4:set_active_profile(profile4)
    local cb4 = CompilerBridge:new(bb4, eb4, pm4)

    local comp4_err = nil
    cb4:compile(function(err, rp)
        comp4_err = err
    end)

    T.assert_not_nil(comp4_err, "should have error for duplicate IDs")
    -- Check that the error contains a V-1006 error
    if type(comp4_err) == "table" and comp4_err[1] then
        local found_dup = false
        for _, e in ipairs(comp4_err) do
            if e.code == "V-1006" then
                found_dup = true
                break
            end
        end
        T.assert_true(found_dup, "should have V-1006 error for duplicate IDs")
    end
    print("  PASS")

    -- =====================================================================
    -- Test 5: get_last_result returns cached result
    -- =====================================================================
    print("Test 5: get_last_result returns cached result")
    local bb5 = Blackboard:new()
    local eb5 = EventBus:new()
    local pm5 = ProfileManager:new()
    local profile5 = make_profile()
    pm5:set_active_profile(profile5)
    local cb5 = CompilerBridge:new(bb5, eb5, pm5)

    cb5:compile(function() end)

    local last = cb5:get_last_result()
    T.assert_not_nil(last, "should have last result after compile")
    T.assert_true(last.success, "should be success")
    T.assert_not_nil(last.runtime_profile, "should have runtime profile")
    T.assert_true(last.duration_ms >= 0, "should have duration")
    -- Run another compile and verify it updates
    local profile5b = make_profile({ name = "Second Profile" })
    pm5:set_active_profile(profile5b)
    cb5:compile(function() end)
    local last2 = cb5:get_last_result()
    T.assert_equal(last2.runtime_profile.profile_id, "Second Profile",
        "last result should update after second compile")
    print("  PASS")

    -- =====================================================================
    -- Test 6: is_compiling returns correct state
    -- =====================================================================
    print("Test 6: is_compiling returns correct state")
    local bb6 = Blackboard:new()
    local eb6 = EventBus:new()
    local pm6 = ProfileManager:new()
    pm6:set_active_profile(make_profile())
    local cb6 = CompilerBridge:new(bb6, eb6, pm6)

    T.assert_false(cb6:is_compiling(), "should not be compiling before start")
    cb6:compile(function()
        T.assert_false(cb6:is_compiling(), "should not be compiling after callback")
    end)
    print("  PASS")

    -- =====================================================================
    -- Test 7: Events emitted during compile
    -- =====================================================================
    print("Test 7: Events emitted during compile")
    local bb7 = Blackboard:new()
    local events_log = {}
    local eb7 = EventBus:new()
    eb7:subscribe("compile:started", function(payload)
        table.insert(events_log, "compile:started")
    end)
    eb7:subscribe("compile:stage_complete", function(payload)
        table.insert(events_log, "compile:stage_complete:" .. payload.stage)
    end)
    eb7:subscribe("compile:completed", function(payload)
        table.insert(events_log, "compile:completed")
    end)
    eb7:subscribe("compile:failed", function(payload)
        table.insert(events_log, "compile:failed")
    end)

    local pm7 = ProfileManager:new()
    pm7:set_active_profile(make_profile())
    local cb7 = CompilerBridge:new(bb7, eb7, pm7)
    cb7:compile(function() end)

    T.assert_true(#events_log >= 3, "should have at least 3 events")
    local found_started = false
    local found_completed = false
    for _, evt in ipairs(events_log) do
        if evt == "compile:started" then found_started = true end
        if evt == "compile:completed" then found_completed = true end
    end
    T.assert_true(found_started, "should have compile:started event")
    T.assert_true(found_completed, "should have compile:completed event")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Compile with no active profile returns error
    -- =====================================================================
    print("Test 8: Compile with no active profile returns error")
    local bb8 = Blackboard:new()
    local eb8 = EventBus:new()
    local pm8 = ProfileManager:new()
    -- No profile set
    local cb8 = CompilerBridge:new(bb8, eb8, pm8)

    local comp8_err = nil
    cb8:compile(function(err, rp)
        comp8_err = err
    end)

    T.assert_not_nil(comp8_err, "should have error for no active profile")
    print("  PASS")

    -- =====================================================================
    -- Test 9: compile_async works (same as compile)
    -- =====================================================================
    print("Test 9: compile_async works (same as compile)")
    local bb9 = Blackboard:new()
    local eb9 = EventBus:new()
    local pm9 = ProfileManager:new()
    pm9:set_active_profile(make_profile())
    local cb9 = CompilerBridge:new(bb9, eb9, pm9)

    local async_result = nil
    cb9:compile_async(function(err, rp)
        async_result = rp
    end)

    T.assert_not_nil(async_result, "compile_async should produce result")
    T.assert_equal(async_result.schema_version, "1.0")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Compile stores result in blackboard
    -- =====================================================================
    print("Test 10: Compile stores result in blackboard")
    local bb10 = Blackboard:new()
    local eb10 = EventBus:new()
    local pm10 = ProfileManager:new()
    pm10:set_active_profile(make_profile({ name = "Blackboard Test" }))
    local cb10 = CompilerBridge:new(bb10, eb10, pm10)

    cb10:compile(function() end)

    local stored = bb10:get("module.runtime.last_compile")
    T.assert_not_nil(stored, "should store result in blackboard")
    T.assert_true(stored.success, "stored result should indicate success")
    T.assert_not_nil(stored.runtime_profile, "stored result should have profile")
    print("  PASS")

    -- =====================================================================
    -- Blueprint Expansion Tests
    -- =====================================================================

    -- Test 11: BlueprintRegistry construction and blueprint registration
    print("Test 11: BlueprintRegistry construction and blueprint registration")
    local Br = BlueprintRegistry:new()
    T.assert_not_nil(Br, "should construct BlueprintRegistry")
    T.assert_true(Br:has("quest_hub"), "should have quest_hub blueprint")
    T.assert_true(Br:has("vendor_stop"), "should have vendor_stop blueprint")
    T.assert_true(Br:has("trainer_stop"), "should have trainer_stop blueprint")
    T.assert_true(Br:has("goto"), "should have goto blueprint")
    T.assert_false(Br:has("nonexistent"), "should not have nonexistent blueprint")
    print("  PASS")

    -- Test 12: is_blueprint detection
    print("Test 12: is_blueprint detection")
    local bp_action = { action_type = "blueprint", blueprint_id = "quest_hub" }
    local regular_action = { action_type = "goto", params = { target = { x = 10 } } }
    T.assert_true(Br:is_blueprint(bp_action), "should detect blueprint action")
    T.assert_false(Br:is_blueprint(regular_action), "should not detect regular action as blueprint")
    print("  PASS")

    -- Test 13: Basic goto blueprint expansion
    print("Test 13: Basic goto blueprint expansion")
    local goto_blueprint_action = {
        action_type = "blueprint",
        blueprint_id = "goto",
        id = "bp-goto-1",
        params = { target = { x = 50, y = 60, z = 70 }, arrival_radius = 3 }
    }
    local expanded_goto = Br:expand(goto_blueprint_action)
    T.assert_not_nil(expanded_goto, "should expand goto blueprint")
    T.assert_equal(#expanded_goto, 1, "should produce 1 action")
    T.assert_equal(expanded_goto[1].action_type, "goto", "should expand to goto action")
    T.assert_equal(expanded_goto[1].params.target.x, 50, "should preserve target x")
    T.assert_equal(expanded_goto[1].params.arrival_radius, 3, "should preserve arrival_radius")
    print("  PASS")

    -- Test 14: Vendor stop blueprint with conditional repair
    print("Test 14: Vendor stop blueprint with conditional repair")
    local vendor_blueprint_action = {
        action_type = "blueprint",
        blueprint_id = "vendor_stop",
        id = "bp-vendor-1",
        params = {
            vendor = { guid = "npc-vendor-123" },
            repair = true
        }
    }
    local expanded_vendor = Br:expand(vendor_blueprint_action)
    T.assert_not_nil(expanded_vendor, "should expand vendor_stop blueprint")
    T.assert_equal(#expanded_vendor, 2, "should produce 2 actions (vendor + repair)")
    T.assert_equal(expanded_vendor[1].action_type, "vendor", "first action should be vendor")
    T.assert_equal(expanded_vendor[2].action_type, "repair", "second action should be repair")
    print("  PASS")

    -- Test 15: Vendor stop without repair (conditional expansion)
    print("Test 15: Vendor stop without repair (conditional expansion)")
    local vendor_no_repair_action = {
        action_type = "blueprint",
        blueprint_id = "vendor_stop",
        id = "bp-vendor-2",
        params = {
            vendor = { guid = "npc-vendor-456" },
            repair = false
        }
    }
    local expanded_no_repair = Br:expand(vendor_no_repair_action)
    T.assert_not_nil(expanded_no_repair, "should expand vendor_stop blueprint")
    T.assert_equal(#expanded_no_repair, 1, "should produce only 1 action (no repair)")
    T.assert_equal(expanded_no_repair[1].action_type, "vendor", "action should be vendor")
    print("  PASS")

    -- Test 16: Vendor stop without vendor parameter (conditional expansion)
    print("Test 16: Vendor stop without vendor parameter (conditional expansion)")
    local vendor_empty_action = {
        action_type = "blueprint",
        blueprint_id = "vendor_stop",
        id = "bp-vendor-3",
        params = {}
    }
    local expanded_empty = Br:expand(vendor_empty_action)
    T.assert_not_nil(expanded_empty, "should expand vendor_stop blueprint")
    T.assert_equal(#expanded_empty, 0, "should produce 0 actions when vendor not provided")
    print("  PASS")

    -- Test 17: Trainer stop blueprint expansion
    print("Test 17: Trainer stop blueprint expansion")
    local trainer_blueprint_action = {
        action_type = "blueprint",
        blueprint_id = "trainer_stop",
        id = "bp-trainer-1",
        params = { trainer = { guid = "npc-trainer-789" } }
    }
    local expanded_trainer = Br:expand(trainer_blueprint_action)
    T.assert_not_nil(expanded_trainer, "should expand trainer_stop blueprint")
    T.assert_equal(#expanded_trainer, 1, "should produce 1 action")
    T.assert_equal(expanded_trainer[1].action_type, "train", "action should be train")
    T.assert_equal(expanded_trainer[1].params.npc_guid, "npc-trainer-789", "should have trainer guid")
    print("  PASS")

    -- Test 18: CompilerBridge Blueprint expansion
    print("Test 18: CompilerBridge Blueprint expansion")
    local bb18 = Blackboard:new()
    local eb18 = EventBus:new()
    local pm18 = ProfileManager:new()

    local blueprint_profile = {
        name = "Blueprint Test Profile",
        operations = {
            {
                id = "op-1",
                name = "Vendor Hub",
                actions = {
                    {
                        action_type = "blueprint",
                        blueprint_id = "vendor_stop",
                        id = "bp-act-1",
                        params = { vendor = { guid = "npc-vendor-test" }, repair = true }
                    }
                }
            }
        }
    }
    pm18:set_active_profile(blueprint_profile)
    local cb18 = CompilerBridge:new(bb18, eb18, pm18)

    local blueprint_result = nil
    cb18:compile(function(err, rp)
        blueprint_result = rp
    end)

    T.assert_not_nil(blueprint_result, "should compile successfully")
    T.assert_equal(#blueprint_result.operations, 1, "should have 1 operation")
    -- vendor_stop (repair=true) expands to Vendor + Repair, which the optimizer
    -- collapses into a single Vendor action (ADR-008 §9).
    T.assert_equal(#blueprint_result.operations[1].actions, 1, "should collapse vendor + repair into 1 action")
    T.assert_equal(blueprint_result.operations[1].actions[1].payload.type, "vendor", "collapsed action should be vendor")
    T.assert_not_nil(blueprint_result.operations[1].actions[1].generated_from, "action should have generated_from tag")
    print("  PASS")

    -- Test 19: Nested Blueprint composition
    print("Test 19: Nested Blueprint composition")
    local bb19 = Blackboard:new()
    local eb19 = EventBus:new()
    local pm19 = ProfileManager:new()

    local nested_blueprint = {
        id = "nested_test",
        expand = function(params)
            return {
                { action_type = "blueprint", blueprint_id = "trainer_stop", params = { trainer = params.trainer } }
            }
        end
    }
    local nested_profile = {
        name = "Nested Blueprint Profile",
        operations = {
            {
                id = "op-nested",
                name = "Nested",
                actions = {
                    {
                        action_type = "blueprint",
                        blueprint_id = "nested_test",
                        id = "bp-nested-1",
                        params = { trainer = { guid = "npc-trainer-nested" } }
                    }
                }
            }
        }
    }
    pm19:set_active_profile(nested_profile)
    local cb19 = CompilerBridge:new(bb19, eb19, pm19)
    -- Register the custom blueprint on the bridge's own registry (the bridge
    -- builds a fresh BlueprintRegistry instance, not the test's Br fixture).
    cb19._blueprint_registry:register(nested_blueprint)

    local nested_result = nil
    cb19:compile(function(err, rp)
        nested_result = rp
    end)

    T.assert_not_nil(nested_result, "should compile successfully")
    T.assert_equal(#nested_result.operations[1].actions, 1, "should have 1 action after nested expansion")
    T.assert_equal(nested_result.operations[1].actions[1].payload.type, "train", "nested expansion should produce train action")
    print("  PASS")

    -- Test 20: CompilerBridge mixed actions (blueprint + primitive)
    print("Test 20: CompilerBridge mixed actions (blueprint + primitive)")
    local bb20 = Blackboard:new()
    local eb20 = EventBus:new()
    local pm20 = ProfileManager:new()

    local mixed_profile = {
        name = "Mixed Actions Profile",
        operations = {
            {
                id = "op-mixed",
                name = "Mixed",
                actions = {
                    { action_type = "goto", id = "act-goto-1", params = { target = { x = 10, y = 20 } } },
                    {
                        action_type = "blueprint",
                        blueprint_id = "vendor_stop",
                        id = "act-vendor-1",
                        params = { vendor = { guid = "npc-123" }, repair = true }
                    },
                    { action_type = "wait", id = "act-wait-1", params = { duration_ms = 1000 } }
                }
            }
        }
    }
    pm20:set_active_profile(mixed_profile)
    local cb20 = CompilerBridge:new(bb20, eb20, pm20)

    local mixed_result = nil
    cb20:compile(function(err, rp)
        mixed_result = rp
    end)

    T.assert_not_nil(mixed_result, "should compile successfully")
    T.assert_equal(#mixed_result.operations[1].actions, 3, "should have 3 actions (goto + merged vendor/repair + wait)")
    T.assert_equal(mixed_result.operations[1].actions[1].payload.type, "goto", "first action should be goto")
    T.assert_equal(mixed_result.operations[1].actions[2].payload.type, "vendor", "second action should be vendor (merged with repair)")
    T.assert_equal(mixed_result.operations[1].actions[3].payload.type, "wait", "third action should be wait")
    T.assert_not_nil(mixed_result.operations[1].actions[2].generated_from, "vendor action should have generated_from tag")
    print("  PASS")

    print("\n=== All CompilerBridge Tests PASSED ===")
end

return M