local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local RestSubTree = require("bt/RestSubTree")
    local MaintenanceSubTree = require("bt/MaintenanceSubTree")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    -- =====================
    -- RestSubTree tests
    -- =====================
    local rest = RestSubTree.build(bb)

    -- Test 1: FAILURE when health is high
    bb:set("player.in_combat", false)
    bb:set("player.health", 900)
    bb:set("player.max_health", 1000)
    assert(rest:tick() == S.FAILURE, "rest should fail at high health")

    -- Test 2: FAILURE when in combat (even if low HP)
    bb:set("player.in_combat", true)
    bb:set("player.health", 300)
    assert(rest:tick() == S.FAILURE, "rest should fail in combat")

    -- Test 3: RUNNING when low health and not in combat
    bb:set("player.in_combat", false)
    bb:set("player.health", 500)
    rest:reset()
    assert(rest:tick() == S.RUNNING, "rest should run when low health")
    assert(bb:get("combat.was_resting") == true, "should set was_resting flag")

    -- Test 4: SUCCESS when recovered
    bb:set("player.health", 950)
    assert(rest:tick() == S.SUCCESS, "rest should succeed when recovered")
    assert(bb:get("combat.was_resting") == false, "should clear was_resting flag")

    -- Test 5: FAILURE if combat starts during rest
    bb:set("player.health", 500)
    rest:reset()
    rest:tick()  -- start resting
    bb:set("player.in_combat", true)
    assert(rest:tick() == S.FAILURE, "rest should fail if combat starts")

    -- =====================
    -- MaintenanceSubTree tests
    -- =====================
    local maint = MaintenanceSubTree.build(bb)

    -- Test 6: FAILURE when in combat
    bb:set("player.in_combat", true)
    bb:set("player.needs_aura", true)
    assert(maint:tick() == S.FAILURE, "maintenance should fail in combat")

    -- Test 7: FAILURE when no buffs needed
    bb:set("player.in_combat", false)
    bb:set("player.needs_aura", false)
    bb:set("player.needs_blessing", false)
    bb:set("player.needs_seal", false)
    assert(maint:tick() == S.FAILURE, "maintenance should fail when no buffs needed")

    -- Test 8: SUCCESS when aura needed
    bb:set("player.needs_aura", true)
    maint:reset()
    assert(maint:tick() == S.SUCCESS, "maintenance should succeed casting aura")

    -- Test 9: SUCCESS when blessing needed
    bb:set("player.needs_aura", false)
    bb:set("player.needs_blessing", true)
    maint:reset()
    assert(maint:tick() == S.SUCCESS, "maintenance should succeed casting blessing")

    -- Test 10: SUCCESS when seal needed
    bb:set("player.needs_blessing", false)
    bb:set("player.needs_seal", true)
    maint:reset()
    assert(maint:tick() == S.SUCCESS, "maintenance should succeed casting seal")

    env.restore()
    return true
end

return M
