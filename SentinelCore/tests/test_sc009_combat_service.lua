local T = require("tests/TestUtil")
local ErrorCodes = require("events/ErrorCodes")

local function run()
    local player = T.mock_object({ position = { x = 0, y = 0, z = 0 } })
    local target = T.mock_object({
        name = "Target",
        position = { x = 5, y = 0, z = 0 },
        health = 100,
        max_health = 100,
    })

    local env = T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return { target } end,
        },
    })
    local look_at_calls = 0
    if env and env.core and env.core.input then
        env.core.input.look_at = function()
            look_at_calls = look_at_calls + 1
            return true
        end
    end

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local CombatService = require("services/CombatService")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.object", player)
    bb:set("player.position", player:get_position())

    local nav_calls = { move_to = 0, stop = 0 }
    local nav = {
        move_to = function(_, _, cb)
            nav_calls.move_to = nav_calls.move_to + 1
            if cb then
                cb(true, nil, nil)
            end
        end,
        stop = function()
            nav_calls.stop = nav_calls.stop + 1
        end,
    }
    local targeting = { get_target = function() return target end }
    local rotation = {
        get_pull_profile = function() return { pull_spell_id = 20271, max_pull_range = 30 } end,
        tick_once = function() return true, nil end,
    }

    local combat = CombatService:new(bus, bb, nav, targeting, rotation, {
        combat_timeout = 15,
        pull_timeout = 5,
    })

    local ok, err = combat:start(target)
    T.assert_true(ok == true, "combat start failed")
    T.assert_eq(nav_calls.stop, 1, "combat start should stop nav once before entering pull")

    local u1 = combat:update()
    T.assert_true(u1 == true, "combat update should run")
    T.assert_eq(combat:get_state(), "pull", "combat service should remain in pull state until pull actually engages combat")
    T.assert_eq(nav_calls.stop, 2, "in-range pull should stop nav before attempting pull action")

    target._in_combat = true
    local u1b = combat:update()
    T.assert_true(u1b == true, "combat update should transition after pull engages")
    T.assert_eq(combat:get_state(), "combat", "combat service should switch to combat state once target enters combat")

    target._dead = true
    local u2 = combat:update()
    T.assert_true(u2 == true and combat:get_state() == "idle", "combat should exit on kill")
    T.assert_true(bb:get("loot.pending_target") == target, "combat kill should hand off loot target")

    local stale_target = {
        is_valid = function()
            error("Invalid game object!")
        end,
        is_dead = function()
            error("Invalid game object!")
        end,
    }
    combat._state = "combat"
    combat._active_target = stale_target
    combat._started_at = (core and core.time and core.time()) or 0
    local safe_ok, update_ok, update_err = pcall(function()
        return combat:update()
    end)
    T.assert_true(safe_ok == true, "combat update must not throw on stale object")
    T.assert_true(update_ok == false and update_err == ErrorCodes.TARGET_LOST,
        "stale object should fail closed with TARGET_LOST")

    local far_target = T.mock_object({
        name = "FarTarget",
        position = { x = 40, y = 0, z = 0 },
        health = 100,
        max_health = 100,
    })
    local nav_far_calls = { move_to = 0, stop = 0 }
    local nav_far = {
        move_to = function(_, _, cb)
            nav_far_calls.move_to = nav_far_calls.move_to + 1
            if cb then
                cb(true, nil, nil)
            end
        end,
        stop = function()
            nav_far_calls.stop = nav_far_calls.stop + 1
        end,
    }
    local targeting_far = { get_target = function() return far_target end }
    local combat_far = CombatService:new(bus, bb, nav_far, targeting_far, rotation, {
        combat_timeout = 15,
        pull_timeout = 5,
    })
    local far_ok, far_err = combat_far:start(far_target)
    T.assert_true(far_ok == true, "combat start should succeed for far target")
    local far_update = combat_far:update()
    T.assert_true(far_update == true, "combat update should issue chase for far target")
    T.assert_eq(combat_far:get_state(), "pull", "far target should remain in pull state while closing distance")
    T.assert_eq(nav_far_calls.stop, 1, "far pull should not cancel nav repeatedly while target is out of range")
    T.assert_eq(nav_far_calls.move_to, 1, "far pull should issue move_to when target is out of pull range")

    local moving_target = T.mock_object({
        name = "MovingTarget",
        position = { x = 40, y = 0, z = 0 },
        health = 100,
        max_health = 100,
    })
    local repath_calls = { move_to = 0, find_path = 0 }
    local nav_client_bb = {
        values = {
            ["player.position"] = player:get_position(),
        },
        get = function(self, key)
            return self.values[key]
        end,
        set = function(self, key, value)
            self.values[key] = value
        end,
    }
    local nav_client_state = {
        moving = false,
        movement = {
            navigate = function() end,
        },
        nav_client = {
            find_path = function(_, _, _, cb)
                repath_calls.find_path = repath_calls.find_path + 1
                cb(true, {
                    waypoints = {
                        { x = 1, y = 0, z = 0 },
                        { x = 2, y = 0, z = 0 },
                    },
                })
            end,
        },
        is_moving = function(self)
            return self.moving == true
        end,
        get_full_state = function(self)
            if self.moving then
                return "moving"
            end
            return "idle"
        end,
        get_blackboard = function()
            return nav_client_bb
        end,
        get_path_opts = function()
            return {}
        end,
    }
    local nav_follow_style = {
        move_to = function(_, _, cb)
            repath_calls.move_to = repath_calls.move_to + 1
            if cb then
                cb(true, nil, nil)
            end
        end,
        stop = function() end,
        get_client = function()
            return nav_client_state
        end,
    }
    local combat_moving = CombatService:new(bus, bb, nav_follow_style, targeting_far, rotation, {
        combat_timeout = 15,
        pull_timeout = 5,
        pull_chase_repath_distance = 3.0,
        pull_chase_repath_cooldown = 0.0,
        pull_chase_move_to_cooldown = 0.0,
    })
    local moving_ok, moving_err = combat_moving:start(moving_target)
    T.assert_true(moving_ok == true, "combat start should succeed for moving target chase")
    local moving_update_1 = combat_moving:update()
    T.assert_true(moving_update_1 == true, "first pull update should issue move_to for moving target")
    T.assert_eq(repath_calls.move_to, 1, "first moving-target update should kick off move_to")
    T.assert_eq(repath_calls.find_path, 0, "first moving-target update should not repath yet")
    nav_client_state.moving = true
    moving_target._position = { x = 46, y = 0, z = 0 }
    local moving_update_2 = combat_moving:update()
    T.assert_true(moving_update_2 == true, "second pull update should async repath while already moving")
    T.assert_eq(repath_calls.move_to, 1, "repath should avoid reissuing move_to while walking")
    T.assert_eq(repath_calls.find_path, 1, "repath should use find_path when destination moves")

    local low_mana_rotation = {
        should_hold_maintenance = function()
            return false
        end,
        get_pull_profile = function() return { pull_spell_id = 20271, max_pull_range = 30 } end,
        tick_once = function() return true, nil end,
    }
    player._mana = 0
    player._max_mana = 100
    local low_mana_target = T.mock_object({
        name = "LowManaTarget",
        position = { x = 8, y = 0, z = 0 },
        health = 100,
        max_health = 100,
    })
    local combat_low_mana_gate = CombatService:new(bus, bb, nav, targeting, low_mana_rotation, {
        combat_timeout = 15,
        pull_timeout = 5,
        min_pull_mana_pct = 0.12,
    })
    local low_mana_ok, low_mana_err = combat_low_mana_gate:start(low_mana_target)
    T.assert_true(low_mana_ok == false and low_mana_err == ErrorCodes.MAINTENANCE_REQUIRED,
        "combat start should hold proactive pulls when player mana is below min_pull_mana_pct")

    local defensive_low_mana_target = T.mock_object({
        name = "DefensiveLowManaTarget",
        position = { x = 8, y = 0, z = 0 },
        health = 100,
        max_health = 100,
        in_combat = true,
        target = player,
    })
    local defensive_low_ok, defensive_low_err = combat_low_mana_gate:start(defensive_low_mana_target)
    T.assert_true(defensive_low_ok == true and defensive_low_err == nil,
        "combat start should bypass min mana pull gate for defensive engagements")
    combat_low_mana_gate:reset()
    player._mana = 100
    player._max_mana = 100

    local resting_rotation = {
        should_hold_maintenance = function()
            return true
        end,
        get_pull_profile = function() return { pull_spell_id = 20271, max_pull_range = 30 } end,
        tick_once = function() return true, nil end,
    }
    local rest_nav_calls = { stop = 0 }
    local rest_nav = {
        stop = function()
            rest_nav_calls.stop = rest_nav_calls.stop + 1
        end,
    }
    target._dead = false
    local combat_rest_gate = CombatService:new(bus, bb, rest_nav, targeting, resting_rotation, {
        combat_timeout = 15,
        pull_timeout = 5,
    })
    local rest_ok, rest_err = combat_rest_gate:start(target)
    T.assert_true(rest_ok == false and rest_err == ErrorCodes.MAINTENANCE_REQUIRED,
        "combat start should defer pulls while maintenance hold is required")
    T.assert_eq(rest_nav_calls.stop, 1, "maintenance-required start should stop movement")

    local maintenance_calls = { ticks = 0 }
    local combat_maintenance_skip = CombatService:new(bus, bb, rest_nav, targeting, {
        should_hold_maintenance = function()
            return false
        end,
        tick_maintenance_once = function()
            maintenance_calls.ticks = maintenance_calls.ticks + 1
            return true, nil
        end,
    }, {
        combat_timeout = 15,
        pull_timeout = 5,
    })
    local maintenance_ok, maintenance_err = combat_maintenance_skip:run_maintenance()
    T.assert_true(maintenance_ok == false and maintenance_err == nil,
        "maintenance tick should be skipped when hold conditions are not met")
    T.assert_eq(maintenance_calls.ticks, 0, "maintenance tick should not execute when hold is false")
    local forced_maintenance_ok, forced_maintenance_err = combat_maintenance_skip:run_maintenance(true)
    T.assert_true(forced_maintenance_ok == true and forced_maintenance_err == nil,
        "forced maintenance tick should execute even when hold conditions are not met")
    T.assert_eq(maintenance_calls.ticks, 1, "forced maintenance tick should call rotation maintenance once")

    local primary_target = T.mock_object({
        name = "PrimaryTarget",
        position = { x = 32, y = 0, z = 0 },
        health = 100,
        max_health = 100,
    })
    local attacker_add = T.mock_object({
        name = "AttackerAdd",
        position = { x = 6, y = 0, z = 0 },
        health = 100,
        max_health = 100,
        in_combat = true,
        target = player,
    })
    local retarget_calls = { tick = 0 }
    local combat_retarget = CombatService:new(bus, bb, nav_far, {
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
        tick_once = function()
            retarget_calls.tick = retarget_calls.tick + 1
            return true, nil
        end,
        get_movement_profile = function()
            return { combat_chase_range = 5.5 }
        end,
    }, {
        combat_timeout = 15,
        pull_timeout = 5,
    })
    local retarget_ok, retarget_err = combat_retarget:start(primary_target)
    T.assert_true(retarget_ok == true, "combat start should succeed for defensive retarget scenario")
    local retarget_update = combat_retarget:update()
    T.assert_true(retarget_update == true, "combat update should continue after defensive retarget switch")
    T.assert_eq(combat_retarget:get_state(), "combat",
        "combat should switch from pull to combat when a different attacker engages first")
    T.assert_true(bb:get("combat.target") == attacker_add,
        "combat target should switch to the attacking add when defensive retarget triggers")
    T.assert_eq(retarget_calls.tick, 1, "rotation should tick against the defensive retargeted target")

    local chase_target = T.mock_object({
        name = "ChaseTarget",
        position = { x = 14, y = 0, z = 0 },
        health = 100,
        max_health = 100,
        in_combat = true,
        target = player,
    })
    local chase_nav_calls = { move_to = 0, stop = 0 }
    local chase_nav = {
        move_to = function()
            chase_nav_calls.move_to = chase_nav_calls.move_to + 1
        end,
        stop = function()
            chase_nav_calls.stop = chase_nav_calls.stop + 1
        end,
    }
    local chase_rotation = {
        get_pull_profile = function()
            return { pull_spell_id = 20271, max_pull_range = 30 }
        end,
        get_movement_profile = function()
            return { combat_chase_range = 5.5 }
        end,
        tick_once = function()
            return true, nil
        end,
    }
    local chase_targeting = {
        get_target = function()
            return chase_target
        end,
        acquire_defensive_target = function(_, preferred)
            return preferred, nil
        end,
    }
    local chase_combat = CombatService:new(bus, bb, chase_nav, chase_targeting, chase_rotation, {
        combat_timeout = 15,
        pull_timeout = 5,
        combat_chase_range = 5.5,
        combat_chase_move_to_cooldown = 0.0,
        combat_chase_repath_cooldown = 0.0,
    })
    local chase_ok, chase_err = chase_combat:start(chase_target)
    T.assert_true(chase_ok == true, "combat start should succeed for combat chase scenario")
    local chase_update_pull = chase_combat:update()
    T.assert_true(chase_update_pull == true, "first update should transition to combat")
    local chase_update_combat = chase_combat:update()
    T.assert_true(chase_update_combat == true, "combat chase update should run")
    T.assert_true(chase_nav_calls.move_to >= 1, "combat chase should move toward target when outside melee chase range")
    chase_target._position = { x = 4, y = 0, z = 0 }
    local look_at_before_close = look_at_calls
    local chase_update_close = chase_combat:update()
    T.assert_true(chase_update_close == true, "combat close-range update should run")
    T.assert_true(chase_nav_calls.stop >= 1, "combat chase should stop navigation after re-entering melee range")
    T.assert_true(look_at_calls > look_at_before_close, "combat update should face target after entering melee range")
    chase_target._position = { x = 5.2, y = 0, z = 0 }
    local look_at_before_realign = look_at_calls
    local chase_update_realign = chase_combat:update()
    T.assert_true(chase_update_realign == true, "combat update should run while target repositions in melee range")
    T.assert_true(look_at_calls > look_at_before_realign, "combat update should reface target when it repositions")

    return {
        sc009_combat_loop = true,
        sc009_combat_stale_target_guard = true,
        sc009_pull_chase_no_stop_spam = true,
        sc009_pull_chase_soft_repath = true,
        sc009_pull_start_rest_gate = true,
        sc009_defensive_retarget = true,
        sc009_combat_chase = true,
        sc009_combat_reface = true,
    }
end

return { run = run }
