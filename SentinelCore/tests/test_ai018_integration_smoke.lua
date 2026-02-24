local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local UE = require("ai/UtilityEvaluator")
local HumanTiming = require("ai/HumanTiming")
local RetUtil = require("rotations/paladin/RetributionUtility")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local GrindService = require("services/GrindService")
    local TargetingService = require("services/TargetingService")
    local ExplorationService = require("services/ExplorationService")
    local DeathRecoveryService = require("services/DeathRecoveryService")
    local LootService = require("services/LootService")

    env.core.spell_book.has_spell = function() return true end
    env.core.spell_book.is_spell_learned = function() return true end
    env.core.spell_book.get_spell_cooldown = function() return 0 end
    env.core.spell_book.get_global_cooldown = function() return 0 end

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
    RetUtil.register_actions(eval)

    local ht = HumanTiming:new()
    local executed_actions = {}
    local spell_executor = function(action)
        executed_actions[#executed_actions + 1] = action
    end

    local target_available = true
    local mock_targeting = setmetatable({
        _blackboard = bb,
        acquire_target = function()
            if not target_available then return nil end
            return TU.mock_object({
                health = 3000, max_health = 3000,
                position = { x = 40, y = 0, z = 0 },
            })
        end,
    }, { __index = TargetingService })

    local explore_ticks = 0
    local mock_explore = setmetatable({
        _blackboard = bb,
        tick = function() explore_ticks = explore_ticks + 1; return true end,
    }, { __index = ExplorationService })

    local mock_death = setmetatable({
        _blackboard = bb,
        _active = false,
        update = function(self)
            local is_dead = bb:get("player.is_dead", false)
            local is_ghost = bb:get("player.is_ghost", false)
            self._active = is_dead or is_ghost
        end,
        is_active = function(self) return self._active end,
    }, { __index = DeathRecoveryService })

    local loot_svc = LootService:new(eb, bb, {}, mock_nav)

    local tree = GrindService.build({
        bb = bb,
        evaluator = eval,
        swing_timer = nil,
        human_timing = ht,
        spell_executor = spell_executor,
        navigation = mock_nav,
        targeting = mock_targeting,
        vendor_service = nil,
        exploration_service = mock_explore,
        death_recovery_service = mock_death,
        loot_service = loot_svc,
    })

    -- Helper to set common alive/idle state
    local function set_alive_idle()
        bb:set("player.is_dead", false)
        bb:set("player.is_ghost", false)
        bb:set("player.in_combat", false)
        bb:set("player.health", 4000)
        bb:set("player.max_health", 4000)
        bb:set("combat.target", nil)
        bb:set("combat.has_aggro", false)
        bb:set("combat.was_resting", false)
        bb:set("combat.was_looting", false)
        bb:set("combat.enemy_count", 0)
        bb:set("inventory.free_slots", 20)
        bb:set("player.durability_pct", 0.90)
        bb:set("player.needs_aura", false)
        bb:set("player.needs_blessing", false)
        bb:set("player.needs_seal", false)
        bb:set("loot.pending_target", nil)
        bb:set("exploration.destination", { x = 200, y = 200, z = 0 })
        bb:set("player.position", { x = 0, y = 0, z = 0 })
    end

    -- ================================================================
    -- Scenario 1: Full grind cycle
    -- idle -> find target -> pull -> combat -> loot -> rest -> idle
    -- ================================================================

    -- Phase 1a: Idle - FindTarget acquires a mob
    set_alive_idle()
    target_available = true
    tree:reset()
    now = now + 0.1
    local status = tree:tick()
    assert(bb:get("combat.target") ~= nil, "S1: should acquire target")

    -- Phase 1b: Pull - navigate to far target
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    tree:reset()
    now = now + 0.1
    nav_calls = {}
    status = tree:tick()
    assert(status == S.RUNNING, "S1: pull should be RUNNING")

    -- Phase 1c: Combat starts
    bb:set("player.in_combat", true)
    bb:set("combat.has_aggro", true)
    bb:set("combat.enemy_count", 1)
    bb:set("player.position", { x = 38, y = 0, z = 0 })
    tree:reset()
    now = now + 0.1
    status = tree:tick()
    assert(status == S.RUNNING, "S1: combat should be RUNNING")

    -- Phase 1d: Target dies, loot appears
    bb:set("player.in_combat", false)
    bb:set("combat.has_aggro", false)
    bb:set("combat.enemy_count", 0)
    local corpse = TU.mock_object({
        health = 0, max_health = 3000,
        position = { x = 40, y = 0, z = 0 },
    })
    bb:set("combat.target", nil)
    bb:set("loot.pending_target", corpse)
    tree:reset()
    loot_svc:reset()
    now = now + 0.1
    status = tree:tick()
    -- Loot subtree navigates to corpse or interacts
    assert(status == S.RUNNING or bb:get("loot.pending_target") == nil,
        "S1: should be looting or have looted")

    -- Phase 1e: After looting, low HP -> rest
    bb:set("loot.pending_target", nil)
    bb:set("player.health", 1600)  -- 40% (below 50% rest threshold)
    target_available = false
    tree:reset()
    now = now + 0.1
    status = tree:tick()
    assert(status == S.RUNNING, "S1: rest should be RUNNING")
    assert(bb:get("combat.was_resting") == true, "S1: should set resting flag")

    -- Phase 1f: Rested up (gate cleans up at 90%)
    bb:set("player.health", 3800)  -- 95%
    now = now + 0.1
    status = tree:tick()
    assert(bb:get("combat.was_resting") == false, "S1: should clear resting flag")

    -- ================================================================
    -- Scenario 2: Death cycle
    -- die -> release -> corpse run -> resurrect
    -- ================================================================

    set_alive_idle()
    target_available = false
    bb:set("player.is_dead", true)
    tree:reset()
    now = now + 0.1
    status = tree:tick()
    assert(status == S.RUNNING, "S2: death recovery should be RUNNING when dead")

    -- After release, become ghost
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", true)
    bb:set("player.corpse_position", { x = 100, y = 0, z = 0 })
    tree:reset()
    now = now + 0.1
    status = tree:tick()
    assert(status == S.RUNNING, "S2: corpse run should be RUNNING as ghost")

    -- Arrive at corpse, resurrect
    bb:set("player.is_ghost", false)
    tree:reset()
    now = now + 0.1
    status = tree:tick()
    -- Should fall through to explore/find since alive and idle
    assert(status ~= nil, "S2: should get a valid status after resurrection")

    -- ================================================================
    -- Scenario 3: Flee cycle
    -- overwhelmed -> flee -> recover
    -- ================================================================

    set_alive_idle()
    bb:set("player.in_combat", true)
    bb:set("player.health", 600)    -- 15%
    bb:set("player.max_health", 4000)
    bb:set("combat.enemy_count", 3)
    local enemy = TU.mock_object({
        health = 2000, max_health = 3000,
        position = { x = 5, y = 0, z = 0 },
    })
    bb:set("combat.target", enemy)
    tree:reset()
    now = now + 0.1
    nav_calls = {}
    status = tree:tick()
    assert(status == S.RUNNING, "S3: should be running in combat/flee scenario")

    -- ================================================================
    -- Scenario 4: Explore when nothing to do
    -- ================================================================

    set_alive_idle()
    target_available = false
    explore_ticks = 0
    tree:reset()
    now = now + 0.1
    status = tree:tick()
    -- FindTarget fails (no targets), so Explore should activate
    assert(status == S.RUNNING, "S4: explore should be RUNNING")
    assert(explore_ticks > 0, "S4: exploration service should be ticked")

    env.restore()
    return true
end

return M
