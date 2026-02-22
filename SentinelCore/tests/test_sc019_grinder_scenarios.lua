local T = require("tests/TestUtil")
local BT = require("lib/BehaviorTree")
local ErrorCodes = require("events/ErrorCodes")

local function run()
    local env = T.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local RunCombat = require("behaviors/actions/RunCombat")
    local CombatService = require("services/CombatService")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)

    local player = T.mock_object({
        level = 20,
        class_id = 2,
        position = { x = 0, y = 0, z = 0 },
        health = 100,
        max_health = 100,
        mana = 100,
        max_mana = 100,
    })
    bb:set("player.object", player)
    bb:set("player.position", player:get_position())
    bb:set("player.in_combat", false)

    -- Scenario 1: rest hold should run maintenance and then transition into pull once recovered.
    local maintenance_calls = 0
    local start_calls = 0
    local hold_rest = true
    local scenario_target = T.mock_object({
        name = "ScenarioTarget",
        health = 100,
        max_health = 100,
        position = { x = 8, y = 0, z = 0 },
    })
    local run_combat = RunCombat({
        acquire_target = function()
            return scenario_target, nil
        end,
    }, {
        is_active = function()
            return false
        end,
        should_hold_for_maintenance = function()
            return hold_rest
        end,
        run_maintenance = function(_, force)
            maintenance_calls = maintenance_calls + 1
            hold_rest = false
            return true, nil
        end,
        start = function(_, target)
            start_calls = start_calls + 1
            if not target then
                return false, ErrorCodes.TARGET_NOT_FOUND
            end
            return true, nil
        end,
    })
    local status_rest_1 = run_combat:tick(bb, 0)
    T.assert_eq(status_rest_1, BT.RUNNING, "rest scenario should keep combat action running while maintenance is required")
    T.assert_eq(maintenance_calls, 1, "rest scenario should invoke maintenance before pulling")
    local status_rest_2 = run_combat:tick(bb, 0)
    T.assert_eq(status_rest_2, BT.RUNNING, "rest scenario should transition from maintenance into pull attempt")
    T.assert_eq(start_calls, 1, "rest scenario should attempt pull immediately after maintenance clears")

    -- Scenario 2: while pulling one target, a defensive attacker should preempt and become combat target.
    local primary_target = T.mock_object({
        name = "PrimaryScenarioTarget",
        health = 100,
        max_health = 100,
        position = { x = 32, y = 0, z = 0 },
    })
    local attacker_add = T.mock_object({
        name = "AttackerScenarioAdd",
        health = 100,
        max_health = 100,
        position = { x = 6, y = 0, z = 0 },
        in_combat = true,
        target = player,
    })
    local combat_svc = CombatService:new(bus, bb, {
        move_to = function() end,
        stop = function() end,
    }, {
        get_target = function()
            return primary_target
        end,
        acquire_defensive_target = function(_, preferred)
            if preferred == primary_target then
                return attacker_add, nil
            end
            return nil, ErrorCodes.TARGET_NOT_FOUND
        end,
    }, {
        get_pull_profile = function()
            return { pull_spell_id = 20271, max_pull_range = 30 }
        end,
        get_movement_profile = function()
            return { combat_chase_range = 5.5 }
        end,
        tick_once = function()
            return true, nil
        end,
    }, {
        combat_timeout = 15,
        pull_timeout = 5,
    })
    local s2_ok, s2_err = combat_svc:start(primary_target)
    T.assert_true(s2_ok == true and s2_err == nil, "defensive preemption scenario should start combat")
    local s2_update = combat_svc:update()
    T.assert_true(s2_update == true and combat_svc:get_state() == "combat",
        "defensive preemption scenario should transition into combat when add aggro appears")
    T.assert_true(bb:get("combat.target") == attacker_add,
        "defensive preemption scenario should retarget to attacking add")

    -- Scenario 3: moving target chase should refresh with hysteresis (no per-tick path spam).
    local chase_target = T.mock_object({
        name = "MovingScenarioTarget",
        health = 100,
        max_health = 100,
        position = { x = 40, y = 0, z = 0 },
    })
    local chase_nav_calls = { move_to = 0 }
    local chase_combat = CombatService:new(bus, bb, {
        move_to = function()
            chase_nav_calls.move_to = chase_nav_calls.move_to + 1
        end,
        stop = function() end,
    }, {
        get_target = function()
            return chase_target
        end,
    }, {
        get_pull_profile = function()
            return { pull_spell_id = 20271, max_pull_range = 30 }
        end,
        tick_once = function()
            return true, nil
        end,
    }, {
        combat_timeout = 15,
        pull_timeout = 5,
        pull_chase_repath_distance = 3.0,
        pull_chase_move_to_cooldown = 0.5,
    })
    local s3_ok = chase_combat:start(chase_target)
    T.assert_true(s3_ok == true, "moving chase scenario should start")
    local s3_u1 = chase_combat:update()
    T.assert_true(s3_u1 == true, "moving chase first update should run")
    T.assert_eq(chase_nav_calls.move_to, 1, "moving chase should issue initial move_to")
    local s3_u2 = chase_combat:update()
    T.assert_true(s3_u2 == true, "moving chase second update should run")
    T.assert_eq(chase_nav_calls.move_to, 1, "moving chase should avoid duplicate move_to inside cooldown")
    chase_target._position = { x = 46, y = 0, z = 0 }
    if core and core._set_time and core.time then
        core._set_time(core.time() + 0.6)
    end
    local s3_u3 = chase_combat:update()
    T.assert_true(s3_u3 == true, "moving chase third update should run after target shift")
    T.assert_eq(chase_nav_calls.move_to, 2, "moving chase should refresh move_to after cooldown when target shifts")

    return {
        sc019_rest_to_pull_transition = true,
        sc019_defensive_add_preemption = true,
        sc019_moving_target_chase_hysteresis = true,
    }
end

return { run = run }
