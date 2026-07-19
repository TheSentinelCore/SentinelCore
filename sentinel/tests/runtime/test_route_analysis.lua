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

function M.test_reorder_actions()
    M.setup()
    local RouteAnalysis = require("runtime/route_analysis")

    local ra = RouteAnalysis:new()

    local actions = {
        { id = "a1", action_type = "GoToAction", params = { destination = { x = 100, y = 100, z = 0 } } },
        { id = "a2", action_type = "GoToAction", params = { destination = { x = 50, y = 50, z = 0 } } },
    }

    -- Currently returns nil (placeholder implementation)
    local reordered = ra:reorder_actions(actions, true, nil)
    T.assert_nil(reordered, "Should return nil in placeholder implementation")

    print("  PASS")
end

function M.run()
    print("=== Route Analysis Tests (SENT-6.7) ===")
    M.test_get_action_end_position_goto()
    M.test_get_action_end_position_talk_to_npc()
    M.test_get_action_end_position_vendor()
    M.test_compute_total_travel()
    M.test_can_swap_actions_goal_critical()
    M.test_can_swap_actions_quest_dependency()
    M.test_can_swap_actions_allowed()
    M.test_reorder_actions()
    print("\n=== All Route Analysis Tests PASSED ===")
end

return M