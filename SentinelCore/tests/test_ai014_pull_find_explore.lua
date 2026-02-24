local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local PullSubTree = require("bt/PullSubTree")
    local FindTargetSubTree = require("bt/FindTargetSubTree")
    local ExploreSubTree = require("bt/ExploreSubTree")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    local nav_calls = {}
    local nav_moving = false
    local mock_nav = {
        move_to = function(_, pos)
            nav_calls[#nav_calls + 1] = { action = "move_to", pos = pos }
            nav_moving = true
        end,
        is_moving = function() return nav_moving end,
        stop = function() nav_moving = false end,
        soft_repath = function(_, pos, cb)
            nav_calls[#nav_calls + 1] = { action = "soft_repath", pos = pos }
            if cb then cb(true) end
        end,
    }

    -- =====================
    -- PullSubTree tests
    -- =====================
    local pull = PullSubTree.build(bb, mock_nav)

    -- Test 1: FAILURE when no target
    bb:set("combat.target", nil)
    bb:set("player.in_combat", false)
    assert(pull:tick() == S.FAILURE, "pull should fail with no target")

    -- Test 2: RUNNING when target far away (navigate)
    local target = TU.mock_object({
        health = 500, max_health = 1000,
        position = { x = 50, y = 0, z = 0 },
    })
    bb:set("combat.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.in_combat", false)
    pull:reset()
    nav_calls = {}
    assert(pull:tick() == S.RUNNING, "pull should run when navigating to target")
    assert(#nav_calls > 0, "should navigate to target")

    -- Test 3: RUNNING when in pull range (attacking)
    bb:set("player.position", { x = 25, y = 0, z = 0 })
    pull:reset()
    now = now + 0.1
    assert(pull:tick() == S.RUNNING, "pull should run when in pull range")

    -- Test 4: FAILURE when entering combat (gate blocks in-combat pull)
    bb:set("player.in_combat", true)
    pull:reset()
    now = now + 0.1
    assert(pull:tick() == S.FAILURE, "pull gate should block when in combat")

    -- Test 5: FAILURE on timeout
    bb:set("player.in_combat", false)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    pull:reset()
    now = now + 0.1
    pull:tick()  -- start timer
    now = now + 15
    assert(pull:tick() == S.FAILURE, "pull should fail on timeout")

    -- Test 6: FAILURE when target is dead
    local dead_target = TU.mock_object({
        health = 0, max_health = 1000,
        position = { x = 10, y = 0, z = 0 },
    })
    bb:set("combat.target", dead_target)
    pull:reset()
    now = now + 0.1
    assert(pull:tick() == S.FAILURE, "pull should fail on dead target")

    -- =====================
    -- FindTargetSubTree tests
    -- =====================
    local acquired_target = TU.mock_object({
        health = 800, max_health = 1000,
        position = { x = 20, y = 0, z = 0 },
    })
    local mock_targeting = {
        acquire_target = function()
            return acquired_target
        end,
    }

    local find = FindTargetSubTree.build(bb, mock_targeting)

    -- Test 7: FAILURE when already has valid target
    local alive_target = TU.mock_object({
        health = 500, max_health = 1000,
        position = { x = 10, y = 0, z = 0 },
    })
    bb:set("combat.target", alive_target)
    assert(find:tick() == S.FAILURE, "find should fail when target exists")

    -- Test 8: SUCCESS when no target, acquires one
    bb:set("combat.target", nil)
    find:reset()
    assert(find:tick() == S.SUCCESS, "find should succeed acquiring target")
    assert(bb:get("combat.target") == acquired_target, "should set acquired target on BB")

    -- Test 9: SUCCESS with dead target (needs new one)
    bb:set("combat.target", dead_target)
    find:reset()
    assert(find:tick() == S.SUCCESS, "find should succeed when current target dead")

    -- Test 10: FAILURE when targeting service returns nil
    local empty_targeting = {
        acquire_target = function() return nil end,
    }
    local find_empty = FindTargetSubTree.build(bb, empty_targeting)
    bb:set("combat.target", nil)
    assert(find_empty:tick() == S.FAILURE, "find should fail when no candidates")

    -- =====================
    -- ExploreSubTree tests
    -- =====================
    local explore_ticks = 0
    local mock_explore = {
        tick = function()
            explore_ticks = explore_ticks + 1
        end,
    }

    local explore = ExploreSubTree.build(bb, mock_nav, mock_explore)

    -- Test 11: FAILURE when in combat
    bb:set("player.in_combat", true)
    bb:set("combat.target", nil)
    assert(explore:tick() == S.FAILURE, "explore should fail in combat")

    -- Test 12: FAILURE when has valid target
    bb:set("player.in_combat", false)
    bb:set("combat.target", alive_target)
    assert(explore:tick() == S.FAILURE, "explore should fail with valid target")

    -- Test 13: RUNNING when idle and exploring
    -- ExploreSubTree delegates navigation to ExplorationService internally,
    -- so we only verify exploration_service:tick() is called and dest exists.
    bb:set("combat.target", nil)
    bb:set("exploration.destination", { x = 100, y = 200, z = 0 })
    explore:reset()
    explore_ticks = 0
    assert(explore:tick() == S.RUNNING, "explore should run when idle")
    assert(explore_ticks > 0, "should tick exploration service")

    env.restore()
    return true
end

return M
