local T = require("tests/TestUtil")
local BT = require("lib/BehaviorTree")

local function run()
    local player = T.mock_object({
        name = "Player",
        level = 20,
        class_id = 2,
        faction_id = 67,
        position = { x = 0, y = 0, z = 0 },
    })

    local far_target = T.mock_object({
        name = "FarTarget",
        level = 20,
        health = 100,
        max_health = 100,
        position = { x = 48, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })

    local visible = { far_target }
    T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return visible end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local TargetingService = require("services/TargetingService")
    local ExplorationService = require("services/ExplorationService")
    local Scout = require("behaviors/actions/Scout")
    local CombatKernelTree = require("behaviors/trees/CombatKernelTree")
    local ErrorCodes = require("events/ErrorCodes")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.object", player)
    bb:set("player.position", player:get_position())
    bb:set("player.in_combat", false)
    bb:set("player.is_casting", false)
    bb:set("player.faction_team", "horde")
    bb:set("core.mode", "grind")
    bb:set("grind.anchor", { x = 0, y = 0, z = 0 })
    bb:set("context.canonical", { map_id = 530, zone_id = 3518, area_id = 3520 })

    local nav_calls = {
        move_to = 0,
        soft_repath = 0,
        last_destination = nil,
    }
    local fake_nav = {
        move_to = function(_, destination, callback)
            nav_calls.move_to = nav_calls.move_to + 1
            nav_calls.last_destination = destination
            if callback then
                callback(true, nil, nil)
            end
        end,
        soft_repath = function(_, destination, callback)
            nav_calls.soft_repath = nav_calls.soft_repath + 1
            nav_calls.last_destination = destination
            if callback then
                callback(true, nil, nil)
            end
        end,
        is_moving = function()
            return false
        end,
    }

    local targeting = TargetingService:new(bus, bb, {
        base_radius = 25.0,
        max_radius = 40.0,
        only_engage_opposing_faction_if_attacked = true,
    }, fake_nav)

    local exploration = ExplorationService:new(bus, bb, {
        enabled = true,
        enabled_modes = { "grind" },
        pursuit_extra_radius = 30.0,
        frontier_min_radius = 15.0,
        frontier_max_radius = 35.0,
        move_to_cooldown = 0.01,
        soft_repath_cooldown = 0.01,
    }, fake_nav, targeting)

    local explore_ok, explore_err = exploration:tick()
    T.assert_true(explore_ok == true, "exploration tick should succeed")
    T.assert_true(nav_calls.move_to >= 1, "exploration should issue move_to for visible out-of-range target")
    T.assert_eq(tostring(bb:get("exploration.mode")), "pursuit", "exploration should enter pursuit mode")

    -- With no visible targets, exploration should switch to frontier search.
    visible = {}
    nav_calls.move_to = 0
    core._set_time(core.time() + 2.0)
    local frontier_ok, frontier_err = exploration:tick()
    T.assert_true(frontier_ok == true, "frontier exploration tick should succeed")
    T.assert_true(nav_calls.move_to >= 1, "frontier exploration should issue move_to")
    T.assert_eq(tostring(bb:get("exploration.mode")), "frontier", "exploration should enter frontier mode")

    -- Modes outside enabled_modes should not move.
    bb:set("core.mode", "quest")
    nav_calls.move_to = 0
    core._set_time(core.time() + 1.0)
    local mode_ok, mode_err = exploration:tick()
    T.assert_true(mode_ok == true, "disabled mode exploration tick should still succeed")
    T.assert_eq(nav_calls.move_to, 0, "exploration should be disabled outside configured modes")
    T.assert_eq(bb:get("exploration.active", true), false, "exploration should publish inactive state when disabled")

    -- Scout integration: scout must not block run combat reacquisition loops.
    local runcombat_acquire_calls = 0
    local scout_tick_calls = 0
    local scouting_service = {
        tick = function()
            scout_tick_calls = scout_tick_calls + 1
            return true, nil
        end,
    }

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
            has_work = function() return false end,
            tick = function()
                return "idle", ErrorCodes.OBJECTIVE_NONE_AVAILABLE
            end,
        },
        combat = {
            is_active = function() return false end,
            should_hold_for_maintenance = function() return false end,
            start = function()
                return false, ErrorCodes.TARGET_NOT_FOUND
            end,
            update = function() return true, nil end,
            get_state = function() return "idle" end,
        },
        targeting = {
            acquire_target = function()
                runcombat_acquire_calls = runcombat_acquire_calls + 1
                return nil, ErrorCodes.TARGET_NOT_FOUND
            end,
        },
        exploration = scouting_service,
    }

    local tree = CombatKernelTree.create(services, {
        pause = function() end,
        restart = function() return false end,
        fail = function() end,
    })

    local status1 = tree:tick(bb, 0)
    local status2 = tree:tick(bb, 0)
    T.assert_true(status1 == BT.SUCCESS or status1 == BT.RUNNING, "kernel tick should complete while scouting")
    T.assert_true(status2 == BT.SUCCESS or status2 == BT.RUNNING, "kernel second tick should complete while scouting")
    T.assert_true(runcombat_acquire_calls >= 2, "run combat should still reacquire targets every tick during scout")
    T.assert_true(scout_tick_calls >= 2, "scout exploration tick should execute every tick")

    return {
        sc020_exploration_pursuit = true,
        sc020_exploration_frontier = true,
        sc020_scout_reacquire_loop = true,
    }
end

return { run = run }
