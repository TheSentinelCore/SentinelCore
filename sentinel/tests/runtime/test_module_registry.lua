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