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

    -- run_offline's harness only calls run() when it exists (test* functions below are
    -- ignored in that case), so drive the rest of the suite from here.
    M.test_get_shared_returns_same_instance_for_same_bus()
    M.test_get_shared_returns_distinct_instance_per_bus()
    M.test_ownership_blocks_other_callers_until_release()
    M.test_release_rejects_non_owner()
end

-- B4: app.lua, combat/init.lua, and runtime_profile.lua each used to construct their
-- own private NavAdapter around the single _G.SentinelNavClient.client. get_shared()
-- collapses them onto one instance per event_bus so their belief about active nav
-- state can no longer desync.
function M.test_get_shared_returns_same_instance_for_same_bus()
    local bus = EventBus:new()
    local a = NavAdapter.get_shared(bus)
    local b = NavAdapter.get_shared(bus)
    T.assert_true(a == b, "get_shared must return the identical instance for the same event_bus")
end

function M.test_get_shared_returns_distinct_instance_per_bus()
    local a = NavAdapter.get_shared(EventBus:new())
    local b = NavAdapter.get_shared(EventBus:new())
    T.assert_true(a ~= b, "get_shared must not share instances across distinct event_bus objects")
end

-- B4: ownership contract -- a claimed adapter rejects other callers (including
-- unowned ones) unless they preempt; only the owner may release or stop it.
function M.test_ownership_blocks_other_callers_until_release()
    _G.SentinelNavClient = {
        client = {
            move_to = function() end,
            stop = function() end,
            get_state = function() return "idle" end,
            get_full_state = function() return "idle" end,
            get_progress = function() return {} end,
        },
    }
    core = { object_manager = {} }

    local adapter = NavAdapter:new(EventBus:new())

    local ok = adapter:move_to({ x = 1, y = 1, z = 1 }, { owner = "combat" })
    T.assert_true(ok, "the first claim on an unowned adapter must succeed")
    T.assert_equal(adapter:get_owner(), "combat")

    -- Questing (or anyone else) issuing an unowned command while combat holds the
    -- adapter must be rejected -- this is exactly the B4 steal that used to happen.
    local ok2, err2 = adapter:move_to({ x = 2, y = 2, z = 2 }, {})
    T.assert_true(ok2 == false, "a non-owner move_to must be rejected while combat owns the adapter")
    T.assert_equal(err2, "owned_by_other")

    -- A non-owner cannot stop another owner's motion.
    local stop_ok = adapter:stop("questing_arrived")
    T.assert_true(stop_ok == false, "a non-owner must not be able to stop another owner's motion")

    -- Preempt overrides the existing owner (combat interrupting itself here for
    -- simplicity -- what matters is preempt bypasses the ownership check).
    local ok3 = adapter:move_to({ x = 3, y = 3, z = 3 }, { owner = "combat", preempt = true })
    T.assert_true(ok3, "preempt must be allowed to override the current owner")

    -- Release clears ownership so the next unowned caller can claim it again.
    local released = adapter:release("combat")
    T.assert_true(released, "the owner must be able to release its own claim")
    T.assert_equal(adapter:get_owner(), nil)

    local ok4 = adapter:move_to({ x = 4, y = 4, z = 4 }, {})
    T.assert_true(ok4, "once released, an unowned caller must be able to claim the adapter again")
end

function M.test_release_rejects_non_owner()
    local adapter = NavAdapter:new(EventBus:new())
    adapter:move_to({ x = 1, y = 1, z = 1 }, { owner = "combat" })
    local released = adapter:release("questing")
    T.assert_true(released == false, "a non-owner must not be able to release another owner's claim")
    T.assert_equal(adapter:get_owner(), "combat")
end

return M
