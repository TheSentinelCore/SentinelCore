-- sentinel/tests/runtime/test_tick_isolation.lua
-- Characterization tests for B1 (per-module tick isolation) and F2 (priority ordering)
-- in sentinel/runtime/module_registry.lua.
--
-- B1 (PROVEN): tick_all had no per-module pcall, so a throw in one module's tick()
-- aborted the whole tick_all loop for that frame — other modules (e.g. combat) never
-- ticked. Fixed by wrapping each instance:tick(delta) call in its own pcall; on failure
-- the registry publishes "module:fault" ({module = <name>, error = tostring(err)}) and
-- continues to the next module.
--
-- F2: register_all sorted priority DESCENDING (`>`), so questing (priority 50)
-- initialized/ticked before combat (priority 10) — inverted from the intended
-- lower-number-first ordering. Fixed by sorting ascending (`<`).

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Tick Isolation Tests (B1 / F2) ===")

    local ModuleRegistry = require("runtime/module_registry")
    local original_modules = ModuleRegistry.modules

    -- =====================================================================
    -- Test 1: register_all initializes lower-priority modules first
    -- (combat priority 10 before questing priority 50)
    -- =====================================================================
    print("Test 1: register_all inits combat(10) before questing(50)")
    local bb1 = Blackboard:new()
    local eb1 = EventBus:new()
    local registry1 = ModuleRegistry:new()

    local init_order = {}
    ModuleRegistry.modules = {
        questing = {
            namespace = "questing",
            capabilities = {},
            configuration = { enabled = true, priority = 50 },
            init = function() table.insert(init_order, "questing"); return { tick = function() end } end,
        },
        combat = {
            namespace = "combat",
            capabilities = {},
            configuration = { enabled = true, priority = 10 },
            init = function() table.insert(init_order, "combat"); return { tick = function() end } end,
        },
    }

    registry1:register_all(bb1, eb1)

    T.assert_equal(init_order[1], "combat", "combat (priority 10) should init first")
    T.assert_equal(init_order[2], "questing", "questing (priority 50) should init second")
    print("  PASS")

    -- =====================================================================
    -- Test 2: tick_all ticks combat before questing
    -- =====================================================================
    print("Test 2: tick_all ticks combat before questing")
    local bb2 = Blackboard:new()
    local eb2 = EventBus:new()
    local registry2 = ModuleRegistry:new()

    local tick_order = {}
    ModuleRegistry.modules = {
        questing = {
            namespace = "questing",
            capabilities = {},
            configuration = { enabled = true, priority = 50 },
            init = function()
                return { tick = function() table.insert(tick_order, "questing") end }
            end,
        },
        combat = {
            namespace = "combat",
            capabilities = {},
            configuration = { enabled = true, priority = 10 },
            init = function()
                return { tick = function() table.insert(tick_order, "combat") end }
            end,
        },
    }

    registry2:register_all(bb2, eb2)
    registry2:tick_all(16)

    T.assert_equal(tick_order[1], "combat", "combat should tick first")
    T.assert_equal(tick_order[2], "questing", "questing should tick second")
    print("  PASS")

    -- =====================================================================
    -- Test 3: a throwing questing tick does not block combat's tick, and
    -- exactly one module:fault event fires with the expected payload shape
    -- =====================================================================
    print("Test 3: throwing tick does not abort the loop; module:fault published")
    local bb3 = Blackboard:new()
    local eb3 = EventBus:new()
    local registry3 = ModuleRegistry:new()

    local combat_ticked = false
    local faults = {}
    eb3:subscribe("module:fault", function(payload)
        table.insert(faults, payload)
    end)

    ModuleRegistry.modules = {
        questing = {
            namespace = "questing",
            capabilities = {},
            configuration = { enabled = true, priority = 50 },
            init = function()
                return { tick = function() error("boom: questing tick failure") end }
            end,
        },
        combat = {
            namespace = "combat",
            capabilities = {},
            configuration = { enabled = true, priority = 10 },
            init = function()
                return { tick = function() combat_ticked = true end }
            end,
        },
    }

    registry3:register_all(bb3, eb3)
    registry3:tick_all(16)

    T.assert_true(combat_ticked, "combat should still tick despite questing throwing")
    T.assert_equal(#faults, 1, "exactly one module:fault event should be published")
    if #faults == 1 then
        T.assert_equal(faults[1].module, "questing", "fault payload.module should name the throwing module")
        T.assert_not_nil(faults[1].error, "fault payload.error should be present")
        T.assert_true(
            tostring(faults[1].error):match("boom: questing tick failure") ~= nil,
            "fault payload.error should contain the original error message"
        )
    end
    print("  PASS")

    -- =====================================================================
    -- Test 4: fault-continue behavior holds across repeated frames
    -- =====================================================================
    print("Test 4: fault isolation holds across repeated frames")
    local bb4 = Blackboard:new()
    local eb4 = EventBus:new()
    local registry4 = ModuleRegistry:new()

    local combat_tick_count = 0
    local fault_count = 0
    eb4:subscribe("module:fault", function(payload)
        fault_count = fault_count + 1
    end)

    ModuleRegistry.modules = {
        questing = {
            namespace = "questing",
            capabilities = {},
            configuration = { enabled = true, priority = 50 },
            init = function()
                return { tick = function() error("boom: repeated failure") end }
            end,
        },
        combat = {
            namespace = "combat",
            capabilities = {},
            configuration = { enabled = true, priority = 10 },
            init = function()
                return { tick = function() combat_tick_count = combat_tick_count + 1 end }
            end,
        },
    }

    registry4:register_all(bb4, eb4)
    registry4:tick_all(16)
    registry4:tick_all(16)
    registry4:tick_all(16)

    T.assert_equal(combat_tick_count, 3, "combat should tick every frame despite questing faulting every frame")
    T.assert_equal(fault_count, 3, "one module:fault should be published per faulting frame")
    print("  PASS")

    -- =====================================================================
    -- Test 5: 3 consecutive tick faults degrade the module (tick skipped,
    -- others keep running) and the fault map is published to the blackboard
    -- =====================================================================
    print("Test 5: 3 consecutive faults degrade the module; fault map on blackboard")
    local bb5 = Blackboard:new()
    local eb5 = EventBus:new()
    local registry5 = ModuleRegistry:new()

    local combat_ticks5 = 0
    local faults5 = {}
    eb5:subscribe("module:fault", function(payload) table.insert(faults5, payload) end)

    ModuleRegistry.modules = {
        questing = {
            namespace = "questing",
            capabilities = {},
            configuration = { enabled = true, priority = 50 },
            init = function()
                return { tick = function() error("boom: persistent failure") end }
            end,
        },
        combat = {
            namespace = "combat",
            capabilities = {},
            configuration = { enabled = true, priority = 10 },
            init = function()
                return { tick = function() combat_ticks5 = combat_ticks5 + 1 end }
            end,
        },
    }

    registry5:register_all(bb5, eb5)
    for _ = 1, 5 do registry5:tick_all(16) end

    T.assert_equal(#faults5, 3, "faults stop after degradation: no per-frame re-fault spam")
    T.assert_equal(faults5[3].count, 3, "the fault payload carries the consecutive count")
    T.assert_equal(registry5:get_state("questing"), "degraded",
        "3 consecutive faults transition the module to degraded")
    T.assert_equal(combat_ticks5, 5, "other modules keep ticking after a degradation")

    local fault_map = bb5:get("system.module_faults", nil)
    T.assert_true(fault_map ~= nil and fault_map.questing ~= nil,
        "system.module_faults must be written so the cockpit can show the fault")
    T.assert_equal(fault_map.questing.count, 3, "the blackboard entry carries the count")
    T.assert_true(tostring(fault_map.questing.last_error):match("persistent failure") ~= nil,
        "the blackboard entry carries the last error")

    -- =====================================================================
    -- Test 6: a successful tick resets the consecutive-fault count and
    -- clears the blackboard entry — only CONSECUTIVE faults degrade
    -- =====================================================================
    print("Test 6: a successful tick resets the consecutive-fault count")
    local bb6 = Blackboard:new()
    local eb6 = EventBus:new()
    local registry6 = ModuleRegistry:new()

    local should_fail = true
    ModuleRegistry.modules = {
        questing = {
            namespace = "questing",
            capabilities = {},
            configuration = { enabled = true, priority = 50 },
            init = function()
                return { tick = function() if should_fail then error("boom: flaky") end end }
            end,
        },
    }

    registry6:register_all(bb6, eb6)
    registry6:tick_all(16)
    registry6:tick_all(16)          -- 2 consecutive faults
    should_fail = false
    registry6:tick_all(16)          -- success: count resets
    should_fail = true
    registry6:tick_all(16)
    registry6:tick_all(16)          -- only 2 consecutive again: still active

    T.assert_equal(registry6:get_state("questing"), "active",
        "non-consecutive faults must not degrade the module")
    local map6 = bb6:get("system.module_faults", nil)
    T.assert_equal(map6 and map6.questing and map6.questing.count, 2,
        "the blackboard count reflects the current consecutive streak")
    print("  PASS")

    -- Restore original modules
    ModuleRegistry.modules = original_modules

    print("\n=== All Tick Isolation Tests PASSED ===")
end

return M
