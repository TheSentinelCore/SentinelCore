-- sentinel/tests/runtime/test_route_analysis.lua
-- Tests for SENT-6.7: Route Analysis for In-Operation Reordering

local T = require("tests/test_util")

local M = {}

function M.setup()
    package.loaded["runtime/route_analysis"] = nil
    package.loaded["core/geometry"] = nil
end

function M.test_get_action_end_position_goto()
    print("Test: get_action_end_position - GoToAction")

    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    local action = {
        action_type = "GoToAction",
        params = {
            destination = { x = 100, y = 200, z = 50 }
        }
    }

    local pos = ra:_get_action_end_position(action)
    T.assert_equal(pos.x, 100, "Destination x")
    T.assert_equal(pos.y, 200, "Destination y")
    T.assert_equal(pos.z, 50, "Destination z")

    print("  PASS")
end

function M.test_get_action_end_position_talk_to_npc()
    print("Test: get_action_end_position - TalkToNpc")

    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    local action = {
        action_type = "TalkToNpc",
        params = {
            npc = { position = { x = 300, y = 400, z = 60 } }
        }
    }

    local pos = ra:_get_action_end_position(action)
    T.assert_equal(pos.x, 300, "NPC position x")
    T.assert_equal(pos.y, 400, "NPC position y")

    print("  PASS")
end

function M.test_get_action_end_position_vendor()
    print("Test: get_action_end_position - Vendor")

    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    local action = {
        action_type = "Vendor",
        params = {
            vendor = { position = { x = 500, y = 600, z = 70 } }
        }
    }

    local pos = ra:_get_action_end_position(action)
    T.assert_equal(pos.x, 500, "Vendor position x")

    print("  PASS")
end

function M.test_compute_total_travel()
    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")
    local Geometry = require("core/geometry")

    local ra = RouteAnalysis:new()

    local actions = {
        { action_type = "GoToAction", params = { destination = { x = 0, y = 0, z = 0 } } },
        { action_type = "GoToAction", params = { destination = { x = 3, y = 4, z = 0 } } },
        { action_type = "GoToAction", params = { destination = { x = 6, y = 8, z = 0 } } },
    }

    local total = ra:compute_total_travel(actions, nil)
    -- Distance from (0,0) to (3,4) = 5, then to (6,8) = 5, total = 10
    T.assert_near(total, 10, 0.1, "Total travel distance should be 10")

    print("  PASS")
end

function M.test_can_swap_actions_goal_critical()
    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    local actions = {
        { id = "a1", action_type = "PickupQuest", quest_id = 33 },
        { id = "a2", action_type = "Kill", entry = 123 },
    }

    local can_swap = ra:can_swap_actions(actions, 1, 2)
    T.assert_false(can_swap, "Should not swap when PickupQuest is goal-critical")

    print("  PASS")
end

function M.test_can_swap_actions_quest_dependency()
    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    local actions = {
        { id = "a1", action_type = "TurnInQuest", quest_id = 33 },
        { id = "a2", action_type = "PickupQuest", quest_id = 33 },
    }

    local can_swap = ra:can_swap_actions(actions, 1, 2)
    T.assert_false(can_swap, "Should not swap when quest order is wrong")

    print("  PASS")
end

function M.test_can_swap_actions_allowed()
    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    local actions = {
        { id = "a1", action_type = "Kill", entry = 123 },
        { id = "a2", action_type = "Kill", entry = 456 },
    }

    local can_swap = ra:can_swap_actions(actions, 1, 2)
    T.assert_true(can_swap, "Should allow swapping non-critical kills")

    print("  PASS")
end

function M.test_reorder_actions_improves_travel()
    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    -- Original order visits far point last; reorder should visit it first.
    local actions = {
        { id = "a1", action_type = "GoToAction",  params = { destination = { x = 0,   y = 0,   z = 0 } } },
        { id = "a2", action_type = "wait",        params = { duration_ms = 100 } },
        { id = "a3", action_type = "TalkToNpc",   params = { npc = { position = { x = 100, y = 100, z = 0 } } } },
        { id = "a4", action_type = "GoToAction",  params = { destination = { x = 10,  y = 10,  z = 0 } } },
    }

    local original_cost = ra:compute_total_travel(actions, nil)
    local reordered = ra:reorder_actions(actions, true, nil)
    T.assert_not_nil(reordered, "Should return a reordered list when travel improves")
    local reordered_cost = ra:compute_total_travel(reordered, nil)
    T.assert_true(reordered_cost < original_cost,
        "Reordered travel (" .. reordered_cost .. ") should be less than original (" .. original_cost .. ")")
    -- Positionless 'wait' must keep its relative slot
    T.assert_equal(reordered[2].id, "a2", "Wait action should remain in its slot")

    print("  PASS")
end

function M.test_reorder_actions_preserves_quest_order()
    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    -- TurnIn is geographically nearer the start, but must not jump before Pickup.
    local actions = {
        { id = "pick", action_type = "PickupQuest", quest_id = 5, params = { npc = { position = { x = 100, y = 100, z = 0 } } } },
        { id = "talk", action_type = "TalkToNpc",  params = { npc = { position = { x = 5,   y = 5,   z = 0 } } } },
        { id = "turn", action_type = "TurnInQuest", quest_id = 5, params = { npc = { position = { x = 10,  y = 10,  z = 0 } } } },
    }

    local reordered = ra:reorder_actions(actions, true, nil)
    T.assert_not_nil(reordered, "Should return a reordered list")
    local pi, ti = 99, -1
    for i, a in ipairs(reordered) do
        if a.id == "pick" then pi = i end
        if a.id == "turn" then ti = i end
    end
    T.assert_true(pi < ti, "PickupQuest must precede TurnInQuest after reordering")

    print("  PASS")
end

function M.test_reorder_actions_no_improvement_returns_nil()
    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    -- Already optimal nearest-neighbor order: no reorder should be returned.
    local actions = {
        { id = "a1", action_type = "GoToAction", params = { destination = { x = 0,  y = 0,  z = 0 } } },
        { id = "a2", action_type = "GoToAction", params = { destination = { x = 10, y = 10, z = 0 } } },
        { id = "a3", action_type = "GoToAction", params = { destination = { x = 20, y = 20, z = 0 } } },
    }

    local reordered = ra:reorder_actions(actions, true, nil)
    T.assert_nil(reordered, "Should return nil when no travel improvement exists")

    print("  PASS")
end

function M.test_compute_total_travel_preserves_gap()
    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    -- A positionless action in the middle must not reset the travel chain.
    local actions = {
        { action_type = "GoToAction", params = { destination = { x = 0, y = 0, z = 0 } } },
        { action_type = "wait",       params = { duration_ms = 100 } },
        { action_type = "GoToAction", params = { destination = { x = 3, y = 4, z = 0 } } },
        { action_type = "GoToAction", params = { destination = { x = 6, y = 8, z = 0 } } },
    }

    local total = ra:compute_total_travel(actions, nil)
    -- (0,0)->(3,4)=5, (3,4)->(6,8)=5, total 10 (not just 5)
    T.assert_near(total, 10, 0.1, "Positionless action must not break the travel chain")

    print("  PASS")
end

function M.run()
    print("=== Route Analysis Tests (SENT-6.7) ===")
    M.test_get_action_end_position_goto()
    M.test_get_action_end_position_talk_to_npc()
    M.test_get_action_end_position_vendor()
    M.test_compute_total_travel()
    M.test_compute_total_travel_preserves_gap()
    M.test_can_swap_actions_goal_critical()
    M.test_can_swap_actions_quest_dependency()
    M.test_can_swap_actions_allowed()
    M.test_reorder_actions_improves_travel()
    M.test_reorder_actions_preserves_quest_order()
    M.test_reorder_actions_no_improvement_returns_nil()
    print("\n=== All Route Analysis Tests PASSED ===")
end

return M