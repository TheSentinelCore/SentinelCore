local T = require("tests/TestUtil")
local BT = require("lib/BehaviorTree")

local function run()
    T.install_core_stub()

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local StateMachine = require("core/StateMachine")
    local RunCombat = require("behaviors/actions/RunCombat")
    local ErrorCodes = require("events/ErrorCodes")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local sm = StateMachine:new(bus)
    sm:register_mode("quest", { "scout", "acquire", "pull", "combat", "loot", "vendor", "recover" }, "scout")
    sm:set_active_mode("quest")
    local transitioned = sm:transition("running", {
        mode_id = "quest",
        substate = "running.quest.scout",
    })
    T.assert_true(transitioned == true, "state machine should enter quest mode")

    bb:set("core.state_machine", sm)
    bb:set("core.mode", "quest")
    bb:set("core.mode_definition", {
        id = "quest",
        phases = { "scout", "acquire", "pull", "combat", "loot", "vendor", "recover" },
        default_phase = "scout",
    })

    local target = T.mock_object({ name = "QuestTarget", in_combat = false })

    local combat = {
        _active = false,
        _state = "idle",
        is_active = function(self)
            return self._active
        end,
        update = function(self)
            return true, nil
        end,
        get_state = function(self)
            return self._state
        end,
        should_hold_for_maintenance = function()
            return false
        end,
        start = function(self, value)
            self._active = true
            self._state = "pull"
            return value ~= nil, nil
        end,
    }

    local targeting = {
        acquire_target = function()
            return target, nil
        end,
    }

    local action = RunCombat(targeting, combat)
    local tick1 = action:tick(bb, 0)
    T.assert_eq(tick1, BT.RUNNING, "first combat tick should be running")
    T.assert_eq(sm:get_substate(), "running.quest.pull", "pull substate should be mode-aware")

    combat._active = true
    combat._state = "combat"
    local tick2 = action:tick(bb, 0)
    T.assert_eq(tick2, BT.RUNNING, "active combat tick should be running")
    T.assert_eq(sm:get_substate(), "running.quest.combat", "combat substate should be mode-aware")

    local maintenance_ticks = 0
    combat._active = false
    combat._state = "idle"
    combat.start = function()
        return false, ErrorCodes.MAINTENANCE_REQUIRED
    end
    combat.run_maintenance = function()
        maintenance_ticks = maintenance_ticks + 1
        return true, nil
    end
    local tick3 = action:tick(bb, 0)
    T.assert_eq(tick3, BT.RUNNING, "maintenance-required pull should remain running")
    T.assert_eq(maintenance_ticks, 1, "run combat should trigger maintenance when start returns MAINTENANCE_REQUIRED")

    return {
        sc015_mode_substate_routing = true,
    }
end

return { run = run }
