local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local FleeSubTree = require("bt/FleeSubTree")
    local CombatInterruptSubTree = require("bt/CombatInterruptSubTree")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    local nav_calls = {}
    local mock_nav = {
        move_to = function(_, pos)
            nav_calls[#nav_calls + 1] = { action = "move_to", pos = pos }
        end,
    }

    -- =====================
    -- FleeSubTree tests
    -- =====================
    local flee = FleeSubTree.build(bb, mock_nav)

    -- Test 1: FAILURE when not in combat
    bb:set("player.in_combat", false)
    bb:set("player.health", 100)
    bb:set("player.max_health", 1000)
    bb:set("combat.enemy_count", 3)
    assert(flee:tick() == S.FAILURE, "should fail when not in combat")

    -- Test 2: FAILURE when health is ok (even multi-enemies)
    bb:set("player.in_combat", true)
    bb:set("player.health", 500)
    bb:set("combat.enemy_count", 3)
    assert(flee:tick() == S.FAILURE, "should fail when health is ok")

    -- Test 3: FAILURE when low HP but single enemy
    bb:set("player.health", 100)
    bb:set("combat.enemy_count", 1)
    assert(flee:tick() == S.FAILURE, "should fail with single enemy")

    -- Test 4: RUNNING when should flee (low HP + multiple enemies)
    bb:set("player.health", 100)
    bb:set("combat.enemy_count", 3)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    local enemy = TU.mock_object({ position = { x = 5, y = 0, z = 0 } })
    bb:set("combat.target", enemy)
    flee:reset()
    assert(flee:tick() == S.RUNNING, "should run when fleeing")
    assert(#nav_calls > 0, "should navigate away")
    -- Flee direction should be away from enemy (negative x)
    local flee_pos = nav_calls[#nav_calls].pos
    assert(flee_pos.x < 0, "should flee opposite direction from enemy")

    -- Test 5: SUCCESS when out of combat during flee
    bb:set("player.in_combat", false)
    assert(flee:tick() == S.SUCCESS, "should succeed when out of combat")

    -- =====================
    -- CombatInterruptSubTree tests
    -- =====================
    local interrupt = CombatInterruptSubTree.build(bb)

    -- Test 6: FAILURE when not in combat
    bb:set("player.in_combat", false)
    bb:set("combat.was_resting", true)
    assert(interrupt:tick() == S.FAILURE, "interrupt should fail when not in combat")

    -- Test 7: FAILURE when in combat but wasn't doing anything
    bb:set("player.in_combat", true)
    bb:set("combat.was_resting", false)
    bb:set("combat.was_looting", false)
    assert(interrupt:tick() == S.FAILURE, "interrupt should fail when not interrupted")

    -- Test 8: SUCCESS when in combat and was resting
    bb:set("combat.was_resting", true)
    interrupt:reset()
    assert(interrupt:tick() == S.SUCCESS, "interrupt should succeed when was resting")
    assert(bb:get("combat.was_resting") == false, "should clear was_resting")

    -- Test 9: SUCCESS when in combat and was looting
    bb:set("combat.was_looting", true)
    interrupt:reset()
    assert(interrupt:tick() == S.SUCCESS, "interrupt should succeed when was looting")
    assert(bb:get("combat.was_looting") == false, "should clear was_looting")

    env.restore()
    return true
end

return M
