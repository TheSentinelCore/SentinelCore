local T = require("tests/TestUtil")
local BT = require("lib/BehaviorTree")

local function run()
    T.install_core_stub()

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local CombatKernelTree = require("behaviors/trees/CombatKernelTree")
    local ErrorCodes = require("events/ErrorCodes")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("context.canonical", { map_id = 530, zone_id = 3518, area_id = 3520 })

    local objective_called = 0
    local combat_called = 0
    local services = {
        blackboard = bb,
        recovery = { is_active = function() return false end },
        inventory = {
            is_vendor_enabled = function() return true end,
            needs_vendor_trip = function() return false end,
        },
        vendor = {
            is_active = function() return false end,
            get_state = function() return "idle" end,
            start = function() return false, ErrorCodes.VENDOR_NONE_VIABLE end,
            update = function() return true, nil end,
            reset = function() end,
        },
        loot = {
            get_state = function() return "idle" end,
            is_active = function() return false end,
            start = function() return false, ErrorCodes.LOOT_FAILED end,
            update = function() return true, nil end,
            reset = function() end,
        },
        objective = {
            has_work = function() return true end,
            tick = function()
                objective_called = objective_called + 1
                return "running", nil
            end,
        },
        combat = {
            is_active = function() return true end,
            update = function()
                combat_called = combat_called + 1
                return true, nil
            end,
            get_state = function() return "combat" end,
            should_hold_for_maintenance = function() return false end,
            run_maintenance = function() return false, nil end,
            start = function() return false, ErrorCodes.TARGET_NOT_FOUND end,
        },
        targeting = {
            acquire_target = function() return nil, ErrorCodes.TARGET_NOT_FOUND end,
        },
    }

    local tree = CombatKernelTree.create(services, {
        pause = function() end,
        restart = function() return false end,
        fail = function() end,
    })

    local status = tree:tick(bb, 0)
    T.assert_eq(status, BT.RUNNING, "combat kernel should keep running during active combat")
    T.assert_true(combat_called >= 1, "combat branch should execute")
    T.assert_eq(objective_called, 0, "objective branch must not preempt active combat")

    return {
        sc017_mode_kernel_branch_ordering = true,
    }
end

return { run = run }
