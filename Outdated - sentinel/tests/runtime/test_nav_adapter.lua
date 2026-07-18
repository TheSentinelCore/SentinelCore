local EventBus = require("core/event_bus")
local NavAdapter = require("integrations/nav_client/adapter")
local T = require("tests/test_util")

local M = {}

function M.run()
    local follow_path_calls = 0
    local start_route_calls = 0
    local move_to_calls = 0
    local state = "idle"
    local full_state = "idle"

    _G.SentinelNavClient = {
        client = {
            move_to = function(_self, target, _callback, _opts)
                move_to_calls = move_to_calls + 1
                T.assert_equal(target.x, 1)
            end,
            follow_path = function(_self, nodes, _callback, _opts)
                follow_path_calls = follow_path_calls + 1
                T.assert_equal(#nodes, 2)
            end,
            start_route = function(_self, nodes, _callback, _opts)
                start_route_calls = start_route_calls + 1
                T.assert_equal(#nodes, 2)
            end,
            stop = function() end,
            get_state = function()
                return state
            end,
            get_full_state = function()
                return full_state
            end,
            get_progress = function()
                return { current_index = 2, total_waypoints = 5 }
            end,
            get_destination = function()
                return { x = 9, y = 9, z = 9 }
            end,
            get_path_index = function()
                return 2
            end,
            get_current_path = function()
                return {
                    { x = 0, y = 0, z = 0 },
                    { x = 9, y = 9, z = 9 },
                }
            end,
        },
    }

    core = {
        object_manager = {
            get_local_player = function()
                return {
                    get_position = function()
                        return { x = 0, y = 0, z = 0 }
                    end,
                }
            end,
        },
    }

    local adapter = NavAdapter:new(EventBus:new())
    local ok = adapter:move_to({ x = 1, y = 2, z = 3 }, {})
    T.assert_true(ok)
    T.assert_equal(move_to_calls, 1)

    ok = adapter:follow_path({
        { x = 1, y = 1, z = 1 },
        { x = 2, y = 2, z = 2 },
    }, {})
    T.assert_true(ok)
    T.assert_equal(follow_path_calls, 1)

    ok = adapter:plan_route({
        { x = 1, y = 1, z = 1 },
        { x = 2, y = 2, z = 2 },
    }, {})
    T.assert_true(ok)
    T.assert_equal(start_route_calls, 1)

    state = "navigating"
    full_state = "navigating.awaiting_path"
    local normalized, progress = adapter:poll()
    T.assert_equal(normalized, "requesting_path")
    T.assert_equal(progress.path_index, 2)
    T.assert_equal(progress.path_count, 2)

    full_state = "navigating.following_path"
    normalized = adapter:poll()
    T.assert_equal(normalized, "moving")

    full_state = "navigating.recovering.jumping"
    normalized = adapter:poll()
    T.assert_equal(normalized, "stuck")
end

return M
