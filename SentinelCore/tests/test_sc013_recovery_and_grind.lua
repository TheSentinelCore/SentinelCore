local T = require("tests/TestUtil")
local BT = require("lib/BehaviorTree")

local function run()
    local env = T.install_core_stub()

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local RecoveryService = require("services/RecoveryService")
    local ErrorCodes = require("events/ErrorCodes")
    local CombatKernelTree = require("behaviors/trees/CombatKernelTree")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local recovery = RecoveryService:new(bus, bb, {
        auto_restart_max_attempts = 3,
        auto_restart_backoff_secs = { 2, 5, 10 },
    })

    recovery:report_critical("CTX_UNRESOLVED")

    local cmd1 = recovery:update(1000)
    T.assert_eq(cmd1.action, "pause", "first escalation should pause")

    -- Attempt 1
    local cmd2 = recovery:update(1002)
    T.assert_eq(cmd2.action, "restart", "second command should restart")
    recovery:complete_restart_attempt(false)

    -- Attempt 2
    local cmd3 = recovery:update(1007)
    T.assert_eq(cmd3.action, "restart", "third command should restart again")
    recovery:complete_restart_attempt(false)

    -- Attempt 3
    local cmd4 = recovery:update(1017)
    T.assert_eq(cmd4.action, "restart", "fourth command should restart third time")
    recovery:complete_restart_attempt(false)

    -- Exhausted
    local cmd5 = recovery:update(1018)
    T.assert_eq(cmd5.action, "fail", "must hard fail after 3 attempts")
    T.assert_eq(cmd5.error_code, ErrorCodes.RECOVERY_ATTEMPTS_EXHAUSTED, "wrong exhausted error code")

    local bb2 = Blackboard:new(bus)
    bb2:set("context.canonical", { map_id = 530, zone_id = 3519, area_id = 3520 })
    bb2:set("loot.pending_target", T.mock_object({ name = "Corpse", dead = true }))

    local loot_started = false
    local loot_service = {
        _state = "idle",
        get_state = function(self)
            return self._state
        end,
        is_active = function(self)
            return self._state == "looting"
        end,
        start = function(self, target)
            if not target then
                return false, ErrorCodes.LOOT_FAILED
            end
            loot_started = true
            self._state = "looting"
            return true, nil
        end,
        update = function()
            return true, nil
        end,
        reset = function(self)
            self._state = "idle"
        end,
    }

    local services = {
        blackboard = bb2,
        recovery = { is_active = function() return false end },
        inventory = {
            is_vendor_enabled = function() return true end,
            needs_vendor_trip = function() return false end,
        },
        vendor = {
            is_active = function() return false end,
        },
        loot = loot_service,
        combat = {
            is_active = function() return false end,
            run_maintenance = function() return false, nil end,
            should_hold_for_maintenance = function() return false end,
            get_state = function() return "idle" end,
            start = function() return false, ErrorCodes.TARGET_NOT_FOUND end,
            update = function() return true, nil end,
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
    local status = tree:tick(bb2, 0)
    T.assert_eq(status, BT.RUNNING, "grind tree should run loot branch when pending loot exists")
    T.assert_true(loot_started == true, "grind tree did not start loot from pending target")

    return {
        sc013_recovery_escalation = true,
        sc013_grind_loot_pending_branch = true,
    }
end

return { run = run }
