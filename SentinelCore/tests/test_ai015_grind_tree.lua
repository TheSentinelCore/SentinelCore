local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local UE = require("ai/UtilityEvaluator")
local HumanTiming = require("ai/HumanTiming")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local GrindTree = require("bt/GrindTree")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end
    math.randomseed(42)

    local nav_calls = {}
    local nav_moving = false
    local mock_nav = {
        move_to = function(_, pos)
            nav_calls[#nav_calls + 1] = pos
            nav_moving = true
        end,
        is_moving = function() return nav_moving end,
        stop = function() nav_moving = false end,
        soft_repath = function(_, pos, cb)
            nav_calls[#nav_calls + 1] = pos
            if cb then cb(true) end
        end,
    }

    local eval = UE:new()
    eval:register({
        id = "test_strike",
        action_type = "cast_spell_target",
        spell_id = 100,
        weight = 1.0,
        considerations = {
            { input = "in_combat", curve = "step_above", params = { threshold = 0.5 } },
        },
    })

    local ht = HumanTiming:new()
    local executed = {}
    local spell_executor = function(action)
        executed[#executed + 1] = action
    end

    local mock_targeting = {
        acquire_target = function()
            return TU.mock_object({
                health = 500, max_health = 1000,
                position = { x = 20, y = 0, z = 0 },
            })
        end,
    }

    local explore_ticks = 0
    local mock_explore = {
        tick = function() explore_ticks = explore_ticks + 1 end,
    }

    local tree = GrindTree.build({
        bb = bb,
        evaluator = eval,
        swing_timer = nil,
        human_timing = ht,
        spell_executor = spell_executor,
        navigation = mock_nav,
        targeting = mock_targeting,
        vendor_service = nil,
        exploration_service = mock_explore,
    })

    -- Test 1: Death recovery takes highest priority
    bb:set("player.is_dead", true)
    bb:set("player.is_ghost", false)
    bb:set("player.in_combat", false)
    bb:set("combat.target", nil)
    assert(tree:tick() == S.RUNNING, "death recovery should be RUNNING")

    -- Test 2: When alive and idle, explore takes over (lowest priority succeeds)
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", false)
    bb:set("player.in_combat", false)
    bb:set("combat.target", nil)
    bb:set("combat.has_aggro", false)
    bb:set("combat.was_resting", false)
    bb:set("combat.was_looting", false)
    bb:set("player.health", 1000)
    bb:set("player.max_health", 1000)
    bb:set("inventory.free_slots", 20)
    bb:set("inventory.durability_pct", 1.0)
    bb:set("player.needs_aura", false)
    bb:set("player.needs_blessing", false)
    bb:set("player.needs_seal", false)
    bb:set("loot.lootable_objects", nil)
    bb:set("exploration.destination", { x = 100, y = 100, z = 0 })
    tree:reset()
    -- FindTarget will find a target, so it should succeed before Explore
    local status = tree:tick()
    -- FindTarget should run and set combat.target
    local target = bb:get("combat.target")
    assert(target ~= nil, "FindTarget should have acquired a target")

    -- Test 3: With valid target far away and no combat, PullSubTree should navigate
    -- Move target far enough to trigger navigation (>30 yd)
    local far_target = TU.mock_object({
        health = 500, max_health = 1000,
        position = { x = 50, y = 0, z = 0 },
    })
    bb:set("combat.target", far_target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    tree:reset()
    now = now + 0.1
    nav_calls = {}
    status = tree:tick()
    assert(status == S.RUNNING, "pull should be RUNNING")
    assert(#nav_calls > 0, "pull should navigate to distant target")

    -- Test 4: In combat, CombatSubTree takes priority
    bb:set("player.in_combat", true)
    bb:set("combat.has_aggro", true)
    bb:set("combat.enemy_count", 1)
    tree:reset()
    now = now + 0.1
    status = tree:tick()
    assert(status == S.RUNNING, "combat should be RUNNING")

    -- Test 5: CombatInterrupt when was_resting and entered combat
    bb:set("combat.was_resting", true)
    tree:reset()
    status = tree:tick()
    assert(status == S.SUCCESS, "combat interrupt should succeed")
    assert(bb:get("combat.was_resting") == false, "should clear was_resting")

    -- Test 6: Low health rest after combat
    bb:set("player.in_combat", false)
    bb:set("combat.has_aggro", false)
    bb:set("combat.target", nil)
    bb:set("player.health", 300)
    bb:set("player.max_health", 1000)
    bb:set("loot.lootable_objects", nil)
    -- Make targeting return nil so FindTarget fails
    mock_targeting.acquire_target = function() return nil end
    tree:reset()
    now = now + 0.1
    status = tree:tick()
    assert(status == S.RUNNING, "rest should be RUNNING when low health")

    env.restore()
    return true
end

return M
