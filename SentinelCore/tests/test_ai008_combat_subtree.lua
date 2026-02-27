local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local UE = require("ai/UtilityEvaluator")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local CombatService = require("services/CombatService")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

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

    local HumanTiming = require("ai/HumanTiming")
    local ht = HumanTiming:new()
    math.randomseed(42)

    local executed_actions = {}
    local spell_executor = function(action)
        executed_actions[#executed_actions + 1] = action
    end

    local tree = CombatService.build_bt(bb, eval, nil, ht, spell_executor, nil, nil)

    -- Test 1: FAILURE when not in combat
    bb:set("player.in_combat", false)
    bb:set("combat.has_aggro", false)
    assert(tree:tick() == S.FAILURE, "should fail when not in combat")

    -- Test 2: RUNNING when in combat
    bb:set("player.in_combat", true)
    bb:set("player.health", 800)
    bb:set("player.max_health", 1000)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    local target = TU.mock_object({
        health = 500, max_health = 1000,
        position = { x = 3, y = 0, z = 0 },
        in_combat = true,
    })
    bb:set("combat.target", target)
    bb:set("combat.enemy_count", 1)

    assert(tree:tick() == S.RUNNING, "should be running in combat")

    -- Test 3: After delay, action should be executed
    now = now + 1.0  -- advance past human timing delay
    tree:tick()
    now = now + 1.0
    tree:tick()
    assert(#executed_actions > 0, "should have executed an action")
    assert(executed_actions[1].id == "test_strike", "should execute test_strike")

    env.restore()
    return true
end

return M
