local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local Events = require("events/Events")

    -- Test 1: Events module has BT and Utility event constants
    assert(Events.BT_TICK == "bt.tick", "BT_TICK event should exist")
    assert(Events.BT_SUBTREE_ENTERED == "bt.subtree_entered", "BT_SUBTREE_ENTERED should exist")
    assert(Events.BT_SUBTREE_EXITED == "bt.subtree_exited", "BT_SUBTREE_EXITED should exist")
    assert(Events.UTILITY_EVALUATED == "utility.evaluated", "UTILITY_EVALUATED should exist")
    assert(Events.UTILITY_ACTION_SELECTED == "utility.action_selected", "UTILITY_ACTION_SELECTED should exist")

    -- Test 2: GrindTree can be built with deps table
    local GrindTree = require("bt/GrindTree")
    local UE = require("ai/UtilityEvaluator")
    local HumanTiming = require("ai/HumanTiming")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end
    math.randomseed(42)

    local eval = UE:new()
    local ht = HumanTiming:new()
    local executed = {}

    local mock_nav = {
        move_to = function() end,
        stop = function() end,
    }
    local mock_targeting = {
        acquire_target = function() return nil end,
    }
    local mock_explore = {
        tick = function() end,
    }

    local tree = GrindTree.build({
        bb = bb,
        evaluator = eval,
        swing_timer = nil,
        human_timing = ht,
        spell_executor = function(action) executed[#executed + 1] = action end,
        navigation = mock_nav,
        targeting = mock_targeting,
        vendor_service = nil,
        exploration_service = mock_explore,
    })
    assert(tree ~= nil, "GrindTree should build successfully")

    -- Test 3: Tree ticks without error when all BB keys empty
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

    local tick_ok, tick_err = pcall(function() return tree:tick() end)
    assert(tick_ok, "tree tick should not error: " .. tostring(tick_err))

    -- Test 4: Client._execute_action bridges to spell_queue
    local Client_mod = require("core/Client")
    -- Just verify the module loads without error (full Client:new needs runtime)
    assert(Client_mod ~= nil, "Client module should load")

    env.restore()
    return true
end

return M
