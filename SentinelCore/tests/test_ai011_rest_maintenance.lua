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

    -- Test 1: FAILURE when health is high (90% >= 80% threshold)
    bb:set("player.in_combat", false)
    bb:set("player.health", 900)
    bb:set("player.max_health", 1000)
    assert(rest:tick() == S.FAILURE, "rest should fail at high health")

    -- Test 2: FAILURE when in combat (even if low HP)
    bb:set("player.in_combat", true)
    bb:set("player.health", 300)
    assert(rest:tick() == S.FAILURE, "rest should fail in combat")

    -- Test 3: RUNNING when low health and not in combat (below 50% threshold)
    bb:set("player.in_combat", false)
    bb:set("player.health", 400)
    rest:reset()
    now = now + 0.1
    assert(rest:tick() == S.RUNNING, "rest should run when low health")
    assert(bb:get("combat.was_resting") == true, "should set was_resting flag")

    -- Test 4: FAILURE when recovered (gate exits at 90%, cleans up was_resting)
    bb:set("player.health", 950)
    now = now + 0.1
    assert(rest:tick() == S.FAILURE, "rest gate should fail when recovered")
    assert(bb:get("combat.was_resting") == false, "should clear was_resting flag on recovery")

    -- Test 5: FAILURE if combat starts during rest (gate cleans up)
    bb:set("player.health", 400)
    rest:reset()
    now = now + 0.1
    rest:tick()  -- start resting
    assert(bb:get("combat.was_resting") == true, "should be resting")
    bb:set("player.in_combat", true)
    now = now + 0.1
    assert(rest:tick() == S.FAILURE, "rest should fail if combat starts")
    assert(bb:get("combat.was_resting") == false, "should clear was_resting on combat")

    -- =====================
    -- MaintenanceSubTree tests
    -- =====================
    -- MaintenanceSubTree queries player:has_buff(spell_id) directly.
    -- Provide a mock player with configurable has_buff results.
    local SANCTITY_AURA = 20218
    local BLESSING_OF_MIGHT = 27140
    local SEAL_OF_BLOOD = 31892
    local SEAL_OF_COMMAND = 20375

    local active_buffs = {}
    local mock_player = TU.mock_object({ health = 1000, max_health = 1000 })
    mock_player.has_buff = function(_, spell_id)
        return active_buffs[spell_id] == true
    end

    local maint = MaintenanceSubTree.build(bb)

    -- Test 6: FAILURE when in combat
    bb:set("player.in_combat", true)
    bb:set("player.object", mock_player)
    active_buffs = {}
    assert(maint:tick() == S.FAILURE, "maintenance should fail in combat")

    -- Test 7: FAILURE when all buffs present
    bb:set("player.in_combat", false)
    active_buffs = {
        [SANCTITY_AURA] = true,
        [BLESSING_OF_MIGHT] = true,
        [SEAL_OF_BLOOD] = true,
    }
    maint:reset()
    assert(maint:tick() == S.FAILURE, "maintenance should fail when all buffs present")

    -- Test 8: FAILURE when aura needed (fire-and-forget: always FAILURE)
    active_buffs = {
        [BLESSING_OF_MIGHT] = true,
        [SEAL_OF_BLOOD] = true,
    }
    maint:reset()
    assert(maint:tick() == S.FAILURE, "maintenance should fail (fire-and-forget) after casting aura")

    -- Test 9: FAILURE when blessing needed (fire-and-forget: always FAILURE)
    active_buffs = {
        [SANCTITY_AURA] = true,
        [SEAL_OF_BLOOD] = true,
    }
    maint:reset()
    assert(maint:tick() == S.FAILURE, "maintenance should fail (fire-and-forget) after casting blessing")

    -- Test 10: FAILURE when seal needed (fire-and-forget: always FAILURE)
    active_buffs = {
        [SANCTITY_AURA] = true,
        [BLESSING_OF_MIGHT] = true,
    }
    maint:reset()
    assert(maint:tick() == S.FAILURE, "maintenance should fail (fire-and-forget) after casting seal")

    env.restore()
    return true
end

return M
