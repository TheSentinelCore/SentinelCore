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
    local GrindService = require("services/GrindService")
    local TargetingService = require("services/TargetingService")
    local ExplorationService = require("services/ExplorationService")
    local DeathRecoveryService = require("services/DeathRecoveryService")

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

    local mock_targeting = setmetatable({
        _blackboard = bb,
        acquire_target = function()
            return TU.mock_object({
                health = 500, max_health = 1000,
                position = { x = 20, y = 0, z = 0 },
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
        loot_service = nil,
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

    -- Test 3: With valid target far away and no combat, PullService should navigate
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

    -- Test 4: In combat, CombatService takes priority
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

    -- Test 7: Bug 4 — chase_target overrides stale exploration navigation
    -- Record all nav actions including stops
    local nav_action_log = {}
    local orig_move_to = mock_nav.move_to
    local orig_nav_stop = mock_nav.stop
    mock_nav.move_to = function(self_or_pos, pos)
        local p = pos or self_or_pos
        nav_action_log[#nav_action_log + 1] = { action = "move_to", pos = p }
        nav_moving = true
    end
    mock_nav.stop = function()
        nav_action_log[#nav_action_log + 1] = { action = "stop" }
        nav_moving = false
    end
    -- Simulate: exploration left nav moving, combat starts
    nav_moving = true
    bb:set("player.in_combat", true)
    bb:set("combat.has_aggro", true)
    bb:set("combat.enemy_count", 1)
    bb:set("combat.was_resting", false)
    bb:set("combat.was_looting", false)
    local chase_mob = TU.mock_object({
        health = 500, max_health = 1000,
        position = { x = 20, y = 0, z = 0 },
    })
    bb:set("combat.target", chase_mob)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health", 1000)
    tree:reset()
    now = now + 0.1
    tree:tick()
    local found_stop = false
    local found_move_after_stop = false
    for _, entry in ipairs(nav_action_log) do
        if entry.action == "stop" then
            found_stop = true
        end
        if found_stop and entry.action == "move_to" then
            found_move_after_stop = true
        end
    end
    assert(found_stop, "Bug 4: should stop stale exploration nav when combat starts")
    assert(found_move_after_stop, "Bug 4: should issue move_to after stopping stale nav")
    -- Test 8: Target change during continuous combat stops stale nav
    -- Simulate: in_combat stays true (chained aggro), target changes,
    -- exploration ran briefly in the gap → stale nav must be stopped.
    nav_action_log = {}
    mock_nav.move_to = function(self_or_pos, pos)
        local p = pos or self_or_pos
        nav_action_log[#nav_action_log + 1] = { action = "move_to", pos = p }
        nav_moving = true
    end
    mock_nav.stop = function()
        nav_action_log[#nav_action_log + 1] = { action = "stop" }
        nav_moving = false
    end
    -- Still in combat from Test 7 — simulate target dying, new target acquired
    local new_mob = TU.mock_object({
        health = 800, max_health = 1000,
        position = { x = -30, y = 0, z = 0 },  -- opposite direction
    })
    -- Simulate exploration nav running during the brief target gap
    nav_moving = true
    bb:set("combat.target", new_mob)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    now = now + 0.1
    tree:tick()
    found_stop = false
    found_move_after_stop = false
    for _, entry in ipairs(nav_action_log) do
        if entry.action == "stop" then
            found_stop = true
        end
        if found_stop and entry.action == "move_to" then
            found_move_after_stop = true
        end
    end
    assert(found_stop, "Test 8: should stop stale nav when target changes mid-combat")
    assert(found_move_after_stop, "Test 8: should issue move_to to new target after stop")

    -- Test 9: Combat grace period prevents exploration during target death gap
    -- When target dies but player is still in_combat, the combat condition's
    -- grace period should keep the combat BT active, blocking exploration from
    -- issuing move_to in the wrong direction.
    nav_action_log = {}
    mock_nav.move_to = function(self_or_pos, pos)
        local p = pos or self_or_pos
        nav_action_log[#nav_action_log + 1] = { action = "move_to", pos = p }
        nav_moving = true
    end
    mock_nav.stop = function()
        nav_action_log[#nav_action_log + 1] = { action = "stop" }
        nav_moving = false
    end

    -- Setup: in combat with a dead target (just killed), no replacement yet
    local dead_mob = TU.mock_object({
        health = 0, max_health = 1000,
        position = { x = 5, y = 0, z = 0 },
        dead = true,
    })
    bb:set("player.in_combat", true)
    bb:set("combat.has_aggro", true)
    bb:set("combat.enemy_count", 1)
    bb:set("combat.target", dead_mob)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health", 1000)
    bb:set("player.max_health", 1000)
    bb:set("exploration.destination", { x = -100, y = -100, z = 0 })
    -- Targeting won't find replacement on this tick
    mock_targeting.acquire_target = function() return nil end
    nav_moving = false
    tree:reset()
    now = now + 0.1
    local explore_before = explore_ticks
    status = tree:tick()

    -- Combat grace period should keep BT active (RUNNING), not fall through to exploration
    assert(status == S.RUNNING, "Test 9: combat grace period should keep BT RUNNING with dead target")
    assert(explore_ticks == explore_before, "Test 9: exploration should NOT tick during grace period")

    -- Verify no nav was issued toward exploration waypoint
    local nav_to_explore = false
    for _, entry in ipairs(nav_action_log) do
        if entry.action == "move_to" and entry.pos and entry.pos.x and entry.pos.x < -50 then
            nav_to_explore = true
        end
    end
    assert(not nav_to_explore, "Test 9: should NOT navigate toward exploration waypoint during grace")

    -- Now simulate: replacement target acquired on next tick
    local replacement_mob = TU.mock_object({
        health = 800, max_health = 1000,
        position = { x = 25, y = 0, z = 0 },
    })
    bb:set("combat.target", replacement_mob)
    nav_action_log = {}
    now = now + 0.1
    status = tree:tick()
    assert(status == S.RUNNING, "Test 9b: combat should resume with replacement target")
    -- Should navigate to replacement mob
    local found_chase_move = false
    for _, entry in ipairs(nav_action_log) do
        if entry.action == "move_to" and entry.pos and entry.pos.x and entry.pos.x > 10 then
            found_chase_move = true
        end
    end
    assert(found_chase_move, "Test 9b: should navigate to replacement target")

    -- Restore mock nav and targeting
    mock_nav.move_to = orig_move_to
    mock_nav.stop = orig_nav_stop
    mock_targeting.acquire_target = function()
        return TU.mock_object({
            health = 500, max_health = 1000,
            position = { x = 20, y = 0, z = 0 },
        })
    end

    env.restore()
    return true
end

return M
