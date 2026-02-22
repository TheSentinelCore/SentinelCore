local T = require("tests/TestUtil")
local ErrorCodes = require("events/ErrorCodes")

local function run()
    local player = T.mock_object({
        level = 10,
        class_id = 2,
        position = { x = 0, y = 0, z = 0 },
    })

    local target_near_lowhp = T.mock_object({
        name = "NearLowHp",
        level = 10,
        health = 20,
        max_health = 100,
        position = { x = 5, y = 0, z = 0 },
    })

    local target_far_fullhp = T.mock_object({
        name = "FarFullHp",
        level = 10,
        health = 100,
        max_health = 100,
        position = { x = 35, y = 0, z = 0 },
    })

    T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return { target_far_fullhp, target_near_lowhp } end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local TargetingService = require("services/TargetingService")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)

    bb:set("player.object", player)
    bb:set("player.position", player:get_position())
    bb:set("player.in_combat", false)
    bb:set("player.faction_team", "horde")

    local targeting = TargetingService:new(bus, bb, {
        base_radius = 40,
        max_radius = 60,
        only_engage_opposing_faction_if_attacked = true,
        score_weights = {
            kill_speed = 0.5,
            loot_value = 0.2,
            travel_cost = 0.2,
            risk = 0.1,
        },
    })

    local target, err = targeting:acquire_target()
    T.assert_true(target ~= nil and target:get_name() == "NearLowHp", "target scoring should be deterministic")
    T.assert_eq(bb:get("combat.enemy_count", 0), 1, "nearby enemy count should be populated for rotation aoe routing")

    local neutral_attackable = T.mock_object({
        name = "NeutralAttackable",
        level = 1,
        health = 100,
        max_health = 100,
        position = { x = 4, y = 0, z = 0 },
        can_attack = true,
        is_enemy = false,
    })
    local non_engageable = T.mock_object({
        name = "NonEngageable",
        level = 1,
        health = 100,
        max_health = 100,
        position = { x = 6, y = 0, z = 0 },
        can_attack = false,
        is_enemy = false,
    })
    local other_player = T.mock_object({
        name = "OtherPlayer",
        level = 1,
        position = { x = 7, y = 0, z = 0 },
        is_enemy = false,
    })
    local engaged_by_other = T.mock_object({
        name = "EngagedByOther",
        level = 1,
        health = 100,
        max_health = 100,
        position = { x = 5, y = 0, z = 0 },
        can_attack = true,
        in_combat = true,
        target = other_player,
    })

    core.object_manager.get_visible_objects = function()
        return { engaged_by_other, non_engageable, neutral_attackable }
    end
    local target2, err2 = targeting:acquire_target()
    T.assert_true(target2 ~= nil and target2:get_name() == "NeutralAttackable",
        "targeting should include neutral but attackable mobs (starter-zone compatibility)")

    local hostile_player_idle = T.mock_object({
        name = "HostilePlayerIdle",
        level = 12,
        health = 100,
        max_health = 100,
        position = { x = 5, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
        faction_id = 469, -- alliance
    })
    function hostile_player_idle:is_player() return true end

    local hostile_player_attacking = T.mock_object({
        name = "HostilePlayerAttacking",
        level = 12,
        health = 100,
        max_health = 100,
        position = { x = 4, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
        faction_id = 469, -- alliance
        in_combat = true,
        target = player,
    })
    function hostile_player_attacking:is_player() return true end

    core.object_manager.get_visible_objects = function()
        return { hostile_player_idle, hostile_player_attacking }
    end
    local target3, err3 = targeting:acquire_target()
    T.assert_true(target3 ~= nil and target3:get_name() == "HostilePlayerAttacking",
        "targeting should only defend against opposing-faction players when they attack first")

    core.object_manager.get_visible_objects = function()
        return { hostile_player_idle }
    end
    local target4, err4 = targeting:acquire_target()
    T.assert_true(target4 == nil and err4 ~= nil,
        "targeting should skip opposing-faction players when they are not attacking us")

    local passive_pull_target = T.mock_object({
        name = "PassivePullTarget",
        level = 10,
        health = 100,
        max_health = 100,
        position = { x = 20, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })
    local add_attacker = T.mock_object({
        name = "AddAttacker",
        level = 10,
        health = 100,
        max_health = 100,
        position = { x = 6, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
        in_combat = true,
        target = player,
    })
    core.object_manager.get_visible_objects = function()
        return { passive_pull_target, add_attacker }
    end
    local defensive_target, defensive_err = targeting:acquire_defensive_target(passive_pull_target)
    T.assert_true(defensive_target ~= nil and defensive_target:get_name() == "AddAttacker",
        "defensive retarget should prefer mobs that are actively attacking the player")
    targeting:clear_target("blacklist_setup")

    local blacklisted_target = T.mock_object({
        name = "BlacklistedTarget",
        level = 10,
        health = 15,
        max_health = 100,
        position = { x = 5, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })
    local fallback_target = T.mock_object({
        name = "FallbackTarget",
        level = 10,
        health = 100,
        max_health = 100,
        position = { x = 12, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })

    core.object_manager.get_visible_objects = function()
        return { fallback_target, blacklisted_target }
    end

    targeting:mark_target_failed(blacklisted_target, ErrorCodes.PULL_FAILED, 3.0)
    T.assert_true(targeting:is_target_blacklisted(blacklisted_target) == true,
        "marked failed target should be blacklisted until TTL expires")

    local target5, err5 = targeting:acquire_target()
    T.assert_true(target5 ~= nil and target5:get_name() == "FallbackTarget",
        "acquire_target should skip blacklisted candidates while blacklist TTL is active")

    if core and core._set_time and core.time then
        core._set_time(core.time() + 3.2)
    end
    T.assert_true(targeting:is_target_blacklisted(blacklisted_target) == false,
        "blacklist entry should expire after its TTL elapses")

    targeting:clear_target("blacklist_expired")
    local target6, err6 = targeting:acquire_target()
    T.assert_true(target6 ~= nil and target6:get_name() == "BlacklistedTarget",
        "expired blacklist should allow high-score target to be selected again")

    local nav_calls = { estimates = 0 }
    local fake_nav = {
        estimate_path_cost = function(_, from_pos, to_pos, cb)
            nav_calls.estimates = nav_calls.estimates + 1
            local x = tonumber(to_pos and to_pos.x) or 0
            if x >= 30 then
                cb(true, 120, nil)
            else
                cb(true, math.max(5, x), nil)
            end
        end,
    }

    local targeting_risk = TargetingService:new(bus, bb, {
        base_radius = 45,
        max_radius = 60,
        pull_risk_budget = 0.25,
        pull_add_scan_radius = 10,
        pull_add_risk_weight = 0.30,
        score_weights = {
            kill_speed = 0.5,
            loot_value = 0.2,
            travel_cost = 0.2,
            risk = 0.3,
        },
    }, fake_nav)

    local risky_target = T.mock_object({
        name = "RiskyTarget",
        level = 10,
        health = 15,
        max_health = 100,
        position = { x = 8, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })
    local risky_add_1 = T.mock_object({
        name = "RiskyAdd1",
        level = 10,
        health = 100,
        max_health = 100,
        position = { x = 9, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })
    local risky_add_2 = T.mock_object({
        name = "RiskyAdd2",
        level = 10,
        health = 100,
        max_health = 100,
        position = { x = 10, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })
    local safe_target = T.mock_object({
        name = "SafeTarget",
        level = 10,
        health = 80,
        max_health = 100,
        position = { x = 24, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })

    core.object_manager.get_visible_objects = function()
        return { risky_target, risky_add_1, risky_add_2, safe_target }
    end
    local risk_pick, risk_err = targeting_risk:acquire_target()
    T.assert_true(risk_pick ~= nil and risk_pick:get_name() == "SafeTarget",
        "pull risk budget should skip high-pressure targets even when kill-speed score is attractive")
    T.assert_true(nav_calls.estimates >= 2, "target scoring should warm path cost estimates during acquisition")

    local targeting_adaptive = TargetingService:new(bus, bb, {
        base_radius = 45,
        max_radius = 60,
        pull_risk_budget = 1.10,
        pull_risk_deaths_per_hour_low = 0.20,
        pull_risk_deaths_per_hour_high = 2.00,
        pull_risk_budget_min_scale = 0.30,
        pull_risk_budget_max_scale = 1.00,
        pull_risk_budget_min_absolute = 0.10,
        pull_add_scan_radius = 10,
        pull_add_risk_weight = 0.60,
        score_weights = {
            kill_speed = 0.5,
            loot_value = 0.2,
            travel_cost = 0.2,
            risk = 0.3,
        },
    })

    bb:set("telemetry.rates.deaths_per_hour", 0.0)
    local adaptive_safe_pick, adaptive_safe_err = targeting_adaptive:acquire_target()
    T.assert_true(adaptive_safe_pick ~= nil and adaptive_safe_pick:get_name() == "RiskyTarget",
        "adaptive pull-risk budget should stay permissive at low deaths/hour")
    T.assert_true((tonumber(bb:get("targeting.pull_risk_budget.effective", 0)) or 0) >= 1.0,
        "adaptive pull-risk budget should remain near base budget when deaths/hour is low")

    targeting_adaptive:clear_target("adaptive_high_death_budget")
    bb:set("telemetry.rates.deaths_per_hour", 3.0)
    local adaptive_high_death_pick, adaptive_high_death_err = targeting_adaptive:acquire_target()
    T.assert_true(adaptive_high_death_pick ~= nil and adaptive_high_death_pick:get_name() == "SafeTarget",
        "adaptive pull-risk budget should become conservative as deaths/hour increases")
    T.assert_true((tonumber(bb:get("targeting.pull_risk_budget.effective", 0)) or 0) <= 0.5,
        "adaptive pull-risk budget should shrink under sustained high death rate")

    local fake_nav_path = {
        estimate_path_cost = function(_, from_pos, to_pos, cb)
            local x = tonumber(to_pos and to_pos.x) or 0
            if x < 12 then
                cb(true, 140, nil)
            else
                cb(true, 18, nil)
            end
        end,
    }
    local targeting_path = TargetingService:new(bus, bb, {
        base_radius = 45,
        max_radius = 60,
        pull_risk_budget = 5.0,
        score_weights = {
            kill_speed = 0.35,
            loot_value = 0.1,
            travel_cost = 0.45,
            risk = 0.10,
        },
    }, fake_nav_path)
    local near_bad_path = T.mock_object({
        name = "NearBadPath",
        level = 10,
        health = 20,
        max_health = 100,
        position = { x = 9, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })
    local far_good_path = T.mock_object({
        name = "FarGoodPath",
        level = 10,
        health = 28,
        max_health = 100,
        position = { x = 16, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })
    core.object_manager.get_visible_objects = function()
        return { near_bad_path, far_good_path }
    end
    local path_pick, path_err = targeting_path:acquire_target()
    T.assert_true(path_pick ~= nil and path_pick:get_name() == "FarGoodPath",
        "path-cost-aware scoring should favor lower path-cost targets over closer but expensive-path targets")

    local fake_nav_unreachable = {
        estimate_path_cost = function(_, from_pos, to_pos, cb)
            local x = tonumber(to_pos and to_pos.x) or 0
            if x <= 11 then
                cb(false, nil, ErrorCodes.NAV_MOVE_FAILED)
            else
                cb(true, x, nil)
            end
        end,
    }
    local targeting_unreachable = TargetingService:new(bus, bb, {
        base_radius = 45,
        max_radius = 60,
        path_unreachable_ttl = 5.0,
        pull_risk_budget = 5.0,
    }, fake_nav_unreachable)
    local unreachable_target = T.mock_object({
        name = "UnreachableTarget",
        level = 10,
        health = 30,
        max_health = 100,
        position = { x = 10, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })
    local reachable_target = T.mock_object({
        name = "ReachableTarget",
        level = 10,
        health = 40,
        max_health = 100,
        position = { x = 15, y = 0, z = 0 },
        can_attack = true,
        is_enemy = true,
    })
    core.object_manager.get_visible_objects = function()
        return { unreachable_target, reachable_target }
    end
    local unreachable_pick, unreachable_err = targeting_unreachable:acquire_target()
    T.assert_true(unreachable_pick ~= nil and unreachable_pick:get_name() == "ReachableTarget",
        "unreachable path estimates should blacklist bad candidates and select reachable alternatives")
    T.assert_true(targeting_unreachable:is_target_blacklisted(unreachable_target) == true,
        "unreachable candidate should be temporarily blacklisted from future pulls")

    return {
        sc007_target_scoring = true,
        sc007_faction_defense_only = true,
        sc007_defensive_retarget = true,
        sc007_target_blacklist_ttl = true,
        sc007_target_risk_budget_and_path_cost = true,
        sc007_adaptive_pull_risk_budget = true,
    }
end

return { run = run }
