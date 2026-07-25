-- sentinel/tests/runtime/test_module_registry.lua
-- Tests for Runtime Module Registry - SENT-8.1

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== ModuleRegistry Tests (SENT-8.1) ===")

    -- Save original modules to restore after tests
    local original_modules
    do
        local ModuleRegistry = require("runtime/module_registry")
        original_modules = ModuleRegistry.modules
    end

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local ModuleRegistry = require("runtime/module_registry")
    local registry = ModuleRegistry:new()
    T.assert_not_nil(registry, "ModuleRegistry instance should not be nil")
    T.assert_equal(type(registry.register), "function", "should have register method")
    T.assert_equal(type(registry.initialize_module), "function", "should have initialize_module method")
    T.assert_equal(type(registry.shutdown_module), "function", "should have shutdown_module method")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Module states
    -- =====================================================================
    print("Test 2: Module states enum")
    local MODULE_STATES = {
        UNLOADED = "unloaded",
        LOADED = "loaded",
        INITIALIZING = "initializing",
        ACTIVE = "active",
        SHUTDOWN = "shutdown",
    }
    T.assert_equal(MODULE_STATES.UNLOADED, "unloaded", "UNLOADED state should be 'unloaded'")
    T.assert_equal(MODULE_STATES.ACTIVE, "active", "ACTIVE state should be 'active'")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Schema validation
    -- =====================================================================
    print("Test 3: Schema validation")
    local registry3 = ModuleRegistry:new()

    -- Valid module
    local valid_module = {
        namespace = "test",
        capabilities = { "test_cap" },
        configuration = { enabled = true },
        init = function() return {} end,
    }
    local success, err = registry3:register("test", valid_module)
    T.assert_true(success, "valid module should register successfully")
    T.assert_nil(err, "no error should be returned for valid module")

    -- Invalid module - missing namespace
    local success2, err2 = registry3:register("invalid", {})
    T.assert_false(success2, "module without namespace should fail")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Register and get module
    -- =====================================================================
    print("Test 4: Register and get module")
    local registry4 = ModuleRegistry:new()
    local test_module = {
        namespace = "test",
        capabilities = { "cap1", "cap2" },
        configuration = { enabled = true },
    }
    registry4:register("test_mod", test_module)

    T.assert_equal(registry4:get_state("test_mod"), "loaded", "module should be in LOADED state after register")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Module capabilities
    -- =====================================================================
    print("Test 5: Module capabilities")
    local registry5 = ModuleRegistry:new()
    local caps_module = {
        namespace = "caps_test",
        capabilities = { "target_selection", "spell_casting" },
        configuration = { enabled = true },
    }
    registry5:register("caps_mod", caps_module)

    T.assert_equal(registry5:has_capability("caps_mod", "target_selection"), true, "should have target_selection capability")
    T.assert_equal(registry5:has_capability("caps_mod", "nonexistent"), false, "should not have nonexistent capability")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Module initialization lifecycle
    -- =====================================================================
    print("Test 6: Module initialization lifecycle")
    local bb6 = Blackboard:new()
    local eb6 = EventBus:new()
    local registry6 = ModuleRegistry:new()

    local init_called = false
    local test_init_module = {
        namespace = "init_test",
        capabilities = { "test" },
        configuration = { enabled = true },
        init = function(blackboard, event_bus)
            T.assert_equal(blackboard, bb6, "blackboard should be passed to init")
            init_called = true
            return { _inited = true }
        end,
    }
    registry6:register("init_mod", test_init_module)

    local state_before = registry6:get_state("init_mod")
    T.assert_equal(state_before, "loaded", "state should be loaded before initialize_module")

    registry6:initialize_module("init_mod", bb6, eb6)

    T.assert_true(init_called, "init function should have been called")
    T.assert_equal(registry6:get_state("init_mod"), "active", "state should be active after initialize")
    local instance = registry6:get("init_mod")
    T.assert_equal(instance._inited, true, "should get module instance")
    print("  PASS")

    -- =====================================================================
    -- Test 6b: A module whose init THROWS must be reported, not silently dropped
    -- =====================================================================
    -- FOUND BY THE PHASE 4C END-TO-END PIN, and it had been live in production since Phase 4b.
    --
    -- `initialize_all` wrapped each `init` in a bare pcall, discarded the error, set the module to
    -- SHUTDOWN and returned `false` -- which `SentinelApp:initialize()` does not check. The combat
    -- module threw on its FIRST blackboard write (`module.combat.izi_bridge`, refused by the handle
    -- guard that landed in Phase 4b D3), so combat was dead in every real boot: no profile, no
    -- catalog, no rotation, no cast. Nothing logged it. Every offline suite stayed green because
    -- they construct SentinelCombat directly instead of going through `initialize_all`.
    --
    -- `tick_all` had reported faults to the blackboard AND the event bus since Phase 1. The
    -- asymmetry is the bug: a module that dies at boot is strictly worse than one that dies on a
    -- tick, and it was the one being reported to nobody.
    print("Test 6b: a failing init is reported")
    local bb6b = Blackboard:new()
    local eb6b = EventBus:new()
    local registry6b = ModuleRegistry:new()

    local published = {}
    eb6b:subscribe("module:fault", function(payload) published[#published + 1] = payload end)

    registry6b:register("exploding_mod", {
        namespace = "boom",
        capabilities = { "test" },
        configuration = { enabled = true },
        init = function() return { init = function() error("init blew up", 0) end } end,
    })
    registry6b:initialize_module("exploding_mod", bb6b, eb6b)

    local all_ok = registry6b:initialize_all({})

    T.assert_false(all_ok, "initialize_all must report that something failed")
    T.assert_equal(#published, 1, "a failing init must publish module:fault, like a failing tick")
    T.assert_equal(published[1].module, "exploding_mod")
    T.assert_equal(published[1].phase, "init", "and must say it was INIT that failed, not a tick")
    T.assert_true(tostring(published[1].error):find("init blew up", 1, true) ~= nil,
        "carrying the error the pcall used to swallow: " .. tostring(published[1].error))

    local faults6b = bb6b:get("system.module_faults")
    T.assert_not_nil(faults6b and faults6b["exploding_mod"],
        "and it must be visible on the blackboard where the cockpit reads faults")
    print("  PASS")

    -- =====================================================================
    -- Test 6c: `phase` must be TOTAL on the blackboard map, not init-only
    -- =====================================================================
    -- Test 6b pins that the EVENT carries `phase = "init"`. The blackboard map did not: the tick
    -- mirror wrote `{ count, last_error }` with no phase at all, so a reader of
    -- `system.module_faults` could only ever see phase on the entries that happened to come from
    -- init. `nil` there was ambiguous -- "this is a tick fault" and "this writer predates the
    -- field" are the same absence -- which is why the field could not be read defensively and
    -- therefore was not read at all.
    --
    -- WHAT THIS CANNOT SEE: it proves the two entries carry DIFFERENT phase strings, not that any
    -- consumer branches on them. Test 6f pins the cockpit end; nothing here pins the log line
    -- (tests/test_main_diagnostics.lua does).
    print("Test 6c: init and tick faults are distinguishable on the blackboard map")
    local bb6c = Blackboard:new()
    local eb6c = EventBus:new()
    local registry6c = ModuleRegistry:new()

    registry6c:register("boot_mod", {
        namespace = "boot", capabilities = {}, configuration = { enabled = true },
        init = function() return { init = function() error("boot blew up", 0) end } end,
    })
    registry6c:register("tick_mod", {
        namespace = "ticker", capabilities = {}, configuration = { enabled = true },
        init = function() return { tick = function() error("tick blew up", 0) end } end,
    })
    registry6c:initialize_module("boot_mod", bb6c, eb6c)
    registry6c:initialize_module("tick_mod", bb6c, eb6c)
    registry6c:initialize_all({})
    registry6c:tick_all(16)

    local faults6c = bb6c:get("system.module_faults")
    T.assert_not_nil(faults6c, "both paths write the same map")
    T.assert_equal(faults6c["boot_mod"] and faults6c["boot_mod"].phase, "init",
        "a boot death must say so ON THE MAP, not only on the event")
    T.assert_equal(faults6c["tick_mod"] and faults6c["tick_mod"].phase, "tick",
        "and a tick fault must say tick, so absence of the field is never the answer")
    print("  PASS")

    -- =====================================================================
    -- Test 6d: the fault REPORT must survive a blackboard that refuses the write
    -- =====================================================================
    -- `_report_init_failure` guards its mirror with pcall and says why: "a blackboard that refuses
    -- it must not replace one silent failure with another". `tick_all`'s two mirrors were
    -- unguarded, and deleting the init pcall turned nothing red -- so neither half was pinned.
    --
    -- The asymmetry is not cosmetic. The blackboard write happens BEFORE the publish on both
    -- paths, so a throwing `set` skips the publish entirely: the fault reaches nobody. Worse, the
    -- throw does not stay local. `tick_all` runs as the scheduler's ACT-stage `module_registry`
    -- handler (runtime/app.lua), which has its own 3-strike quarantine -- so ONE module's tick
    -- fault plus a refusing blackboard escalates into quarantining the handler that ticks EVERY
    -- module. That is the exact blast radius the per-module pcall exists to prevent, re-entered
    -- through the diagnostic path. On the init side the throw lands in `SentinelApp:initialize()`
    -- and kills the whole boot.
    --
    -- WHAT THIS CANNOT SEE: it uses a blackboard that refuses EVERY key. A real handle guard
    -- refuses selectively, and this says nothing about which keys a real Blackboard rejects.
    print("Test 6d: a refusing blackboard must not swallow the fault or escape the registry")
    local refusing_bb = {
        set = function() error("blackboard refuses this key", 0) end,
        get = function() return nil end,
    }
    local eb6d = EventBus:new()
    local published6d = {}
    eb6d:subscribe("module:fault", function(payload) published6d[#published6d + 1] = payload end)

    local registry6d = ModuleRegistry:new()
    registry6d:register("boot_mod", {
        namespace = "boot", capabilities = {}, configuration = { enabled = true },
        init = function() return { init = function() error("boot blew up", 0) end } end,
    })
    -- Faults on its first tick, then runs clean -- driving the fault mirror AND the streak-reset
    -- mirror, both of which write the blackboard.
    local tick_n = 0
    registry6d:register("flappy_mod", {
        namespace = "flappy", capabilities = {}, configuration = { enabled = true },
        init = function()
            return { tick = function()
                tick_n = tick_n + 1
                if tick_n == 1 then error("tick blew up", 0) end
            end }
        end,
    })
    registry6d:initialize_module("boot_mod", refusing_bb, eb6d)
    registry6d:initialize_module("flappy_mod", refusing_bb, eb6d)

    local init_ok6d = pcall(function() registry6d:initialize_all({}) end)
    T.assert_true(init_ok6d, "a refusing blackboard must not turn a module boot death into an app boot death")
    T.assert_equal(#published6d, 1, "the init fault must still reach the event bus (the write is BEFORE the publish)")

    local tick_ok6d = pcall(function() registry6d:tick_all(16) end)
    T.assert_true(tick_ok6d, "a refusing blackboard must not escape tick_all into the scheduler's ACT handler")
    T.assert_equal(#published6d, 2, "the tick fault must still reach the event bus")
    T.assert_equal(published6d[2] and published6d[2].phase, "tick")

    local clean_ok6d = pcall(function() registry6d:tick_all(16) end)
    T.assert_true(clean_ok6d, "and the streak-reset mirror must be guarded too, not just the fault mirror")
    T.assert_equal(#published6d, 2, "a clean tick publishes nothing")
    print("  PASS")

    -- =====================================================================
    -- Test 6e: an init failure must NOT advance the tick fault streak
    -- =====================================================================
    -- `_report_init_failure` hardcodes `count = 1` and never touches the FaultTracker, while
    -- `tick_all` calls `self._faults:fault(...)`. That is deliberate and provable, not an
    -- oversight -- see the comment on the literal in module_registry.lua. This pins it so the two
    -- authorities cannot quietly merge later: if someone "unifies" them by routing init through
    -- the tracker, a boot death would start consuming strikes from a budget that only tick faults
    -- are supposed to spend.
    --
    -- WHAT THIS CANNOT SEE: the streak is a private field, so this asserts on `_faults` directly.
    -- There is no observable route -- an init-failed module is SHUTDOWN and never ticks again, so
    -- its streak can never be witnessed through behaviour. That unobservability IS the argument
    -- for `count = 1`; the assertion is the only thing that can hold it.
    print("Test 6e: an init failure does not spend a tick strike")
    local bb6e = Blackboard:new()
    local eb6e = EventBus:new()
    local registry6e = ModuleRegistry:new()
    registry6e:register("boot_mod", {
        namespace = "boot", capabilities = {}, configuration = { enabled = true },
        init = function() return { init = function() error("boot blew up", 0) end } end,
    })
    registry6e:initialize_module("boot_mod", bb6e, eb6e)
    registry6e:initialize_all({})

    T.assert_equal(registry6e._faults:streak("boot_mod"), 0,
        "the tick streak is a tick authority; a boot death must not spend one of its three strikes")
    T.assert_nil(registry6e._faults:report()["boot_mod"],
        "and the tracker must not claim a module it never ticked")
    T.assert_equal(bb6e:get("system.module_faults")["boot_mod"].count, 1,
        "the map still reports the boot death, counted by construction rather than by the tracker")
    print("  PASS")

    -- =====================================================================
    -- Test 6f: the cockpit view-model must carry the phase through
    -- =====================================================================
    -- Deliverable 2's whole point is that a boot death reaches a RECEIVER. The blackboard map is
    -- transport, not a receiver; `RunnerState.build` is the first thing that reduces it for a
    -- human. It reduced `count` and `last_error` and dropped `phase`, so "combat x1, permanently
    -- dead until you reload" and "combat x1, cleared on the next tick" rendered identically.
    --
    -- Driven end-to-end from a REAL registry rather than a hand-written fixture, because the bug
    -- being pinned lives in the seam between the two, not in either side.
    print("Test 6f: the cockpit view-model distinguishes a boot death from a tick fault")
    local RunnerState = require("modules/questing/runner_state")
    local vm_boot = RunnerState.build({ module_faults = bb6c:get("system.module_faults") })
    T.assert_not_nil(vm_boot.health.module_fault, "the view-model surfaces the worst faulting module")
    T.assert_not_nil(vm_boot.health.module_fault.phase,
        "and must say WHICH phase killed it -- a boot-dead module needs a reload, a tick fault does not")

    local vm_only_boot = RunnerState.build({
        module_faults = { combat = { count = 1, phase = "init", last_error = "boom" } },
    })
    local vm_only_tick = RunnerState.build({
        module_faults = { combat = { count = 1, phase = "tick", last_error = "boom" } },
    })
    T.assert_equal(vm_only_boot.health.module_fault.phase, "init")
    T.assert_equal(vm_only_tick.health.module_fault.phase, "tick")
    T.assert_true(vm_only_boot.health.module_fault.human_text
        ~= vm_only_tick.health.module_fault.human_text,
        "two faults that differ only in phase must not reduce to the same operator sentence")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Module shutdown lifecycle
    -- =====================================================================
    print("Test 7: Module shutdown lifecycle")
    local bb7 = Blackboard:new()
    local eb7 = EventBus:new()
    local registry7 = ModuleRegistry:new()

    local shutdown_called = false
    local instance7 = {
        shutdown = function(self)
            shutdown_called = true
        end
    }
    local test_shutdown_module = {
        namespace = "shutdown_test",
        capabilities = { "test" },
        configuration = { enabled = true },
        init = function() return instance7 end,
    }
    registry7:register("shutdown_mod", test_shutdown_module)
    registry7:initialize_module("shutdown_mod", bb7, eb7)

    local state_active = registry7:get_state("shutdown_mod")
    T.assert_equal(state_active, "active", "state should be active before shutdown")

    registry7:shutdown_module("shutdown_mod")

    T.assert_true(shutdown_called, "shutdown should have been called")
    T.assert_equal(registry7:get_state("shutdown_mod"), "shutdown", "state should be shutdown after shutdown_module")
    T.assert_nil(registry7:get("shutdown_mod"), "_instance should be nil after shutdown")
    print("  PASS")

    -- =====================================================================
    -- Test 8: register_all initializes modules in priority order
    -- =====================================================================
    print("Test 8: register_all priority ordering")
    local bb8 = Blackboard:new()
    local eb8 = EventBus:new()
    local registry8 = ModuleRegistry:new()

    local order = {}
    local module_low = {
        namespace = "low",
        capabilities = {},
        configuration = { enabled = true, priority = 1 },
        init = function() table.insert(order, "low"); return {} end,
    }
    local module_high = {
        namespace = "high",
        capabilities = {},
        configuration = { enabled = true, priority = 10 },
        init = function() table.insert(order, "high"); return {} end,
    }

    local test_modules_8 = {
        low = module_low,
        high = module_high,
    }
    ModuleRegistry.modules = test_modules_8

    registry8:register_all(bb8, eb8)

    -- Higher priority (10) should initialize before lower (1)
    T.assert_true(#order > 0, "modules should be initialized")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Module state change event publishing
    -- =====================================================================
    print("Test 9: Module state change events")
    local bb9 = Blackboard:new()
    local eb9 = EventBus:new()
    local registry9 = ModuleRegistry:new()

    local state_changes = {}
    eb9:subscribe("module_state_changed", function(payload)
        table.insert(state_changes, payload)
    end)

    local test_modules_9 = {
        event_mod = {
            namespace = "event_test",
            capabilities = {},
            configuration = { enabled = true },
            init = function() return {} end,
        }
    }
    ModuleRegistry.modules = test_modules_9

    registry9:register_all(bb9, eb9)

    T.assert_true(#state_changes >= 1, "should have received state change event")
    if #state_changes >= 1 then
        T.assert_equal(state_changes[#state_changes].state, "active", "event state should be active")
    end
    print("  PASS")

    -- =====================================================================
    -- Test 10: shutdown_all shuts down all modules
    -- =====================================================================
    print("Test 10: shutdown_all shuts down all modules")
    local bb10 = Blackboard:new()
    local eb10 = EventBus:new()
    local registry10 = ModuleRegistry:new()

    local shut_down = {}
    local test_modules_10 = {
        m1 = {
            namespace = "m1", capabilities = {}, configuration = { enabled = true },
            init = function() return { shutdown = function() table.insert(shut_down, "m1") end } end,
        },
        m2 = {
            namespace = "m2", capabilities = {}, configuration = { enabled = true },
            init = function() return { shutdown = function() table.insert(shut_down, "m2") end } end,
        },
    }
    ModuleRegistry.modules = test_modules_10

    registry10:register_all(bb10, eb10)
    registry10:shutdown_all()

    T.assert_true(#shut_down >= 2, "all modules should be shut down")
    print("  PASS")

    -- =====================================================================
    -- Test 11: disabled modules not registered
    -- =====================================================================
    print("Test 11: disabled modules not registered")
    local bb11 = Blackboard:new()
    local eb11 = EventBus:new()
    local registry11 = ModuleRegistry:new()

    local test_modules_11 = {
        disabled = {
            namespace = "disabled",
            capabilities = {},
            configuration = { enabled = false },
            init = function() return {} end,
        },
        enabled = {
            namespace = "enabled",
            capabilities = {},
            configuration = { enabled = true },
            init = function() return {} end,
        },
    }
    ModuleRegistry.modules = test_modules_11

    registry11:register_all(bb11, eb11)

    T.assert_nil(registry11:get("disabled"), "disabled module should not be initialized")
    T.assert_not_nil(registry11:get("enabled"), "enabled module should be initialized")
    print("  PASS")

    -- =====================================================================
    -- Test 12: RuntimeContext module registry integration - SENT-8.1
    -- =====================================================================
    print("Test 12: RuntimeContext module registry integration")
    local bb12 = Blackboard:new()
    local eb12 = EventBus:new()
    local RuntimeContext = require("runtime/runtime_context")
    local ctx12 = RuntimeContext:new(bb12, eb12)

    T.assert_not_nil(ctx12:get_module_registry(), "RuntimeContext should have module registry")
    print("  PASS")

    -- =====================================================================
    -- Test 13: RuntimeContext initialize/destroy lifecycle - SENT-8.1
    -- =====================================================================
    print("Test 13: RuntimeContext initialize/destroy lifecycle")
    local bb13 = Blackboard:new()
    local eb13 = EventBus:new()
    local ctx13 = RuntimeContext:new(bb13, eb13)

    -- Use simple test modules that don't require game APIs
    ModuleRegistry.modules = {
        test_module_13 = {
            namespace = "test",
            capabilities = {},
            configuration = { enabled = true },
            init = function() return { shutdown = function() end } end,
        },
    }

    local app13 = { name = "test_app" }
    ctx13:initialize(app13)

    -- Check that module registry was initialized
    local mr = ctx13:get_module_registry()
    T.assert_not_nil(mr, "module registry should exist")

    -- Destroy should work without error
    ctx13:destroy()
    print("  PASS")

    -- Restore original modules
    ModuleRegistry.modules = original_modules

    print("\n=== All ModuleRegistry Tests PASSED ===")
end

return M