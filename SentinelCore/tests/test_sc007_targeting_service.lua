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

    return {
        sc007_target_scoring = true,
        sc007_faction_defense_only = true,
        sc007_defensive_retarget = true,
        sc007_target_blacklist_ttl = true,
    }
end

return { run = run }
