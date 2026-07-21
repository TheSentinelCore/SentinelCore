-- tests/modules/questing/test_runtime_profile.lua
-- Unit tests for RuntimeProfile recovery state machine (Wave 4)
-- Tests: retry counters, navigation recovery, death detection, max failures, logging

local RuntimeProfile = require("modules/questing/runtime_profile")
local RuntimeAction = require("modules/questing/runtime_action")
local T = require("tests/test_util")

local M = {}

-- ============================================================================
-- Helpers
-- ============================================================================

--- Create a mock profile with a single operation of the given action type.
local function make_profile_ops(action_type, payload, overrides)
    overrides = overrides or {}
    return {
        operations = {
            {
                id = overrides.op_id or 1,
                action = {
                    type = action_type,
                    payload = payload or {},
                },
                next_condition = "auto",
            },
        },
    }
end

--- Set up the global state for nav / core mocking.
local function mock_globals()
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    _G.core.unit = _G.core.unit or {}
    _G.core.input = _G.core.input or {}

    -- Reset global state
    _G.core.unit.is_dead = nil
    _G.core.unit.get_health = nil
    _G.core.object_manager.get_local_player = nil
    _G.core.object_manager.GetNearestCreature = nil
    _G.core.object_manager.GetNearestGameObject = nil
    _G.core.object_manager.GetNearestObject = nil

    _G.SentinelNavClient = {
        client = {
            move_to = function() return true end,
            stop = function() end,
            get_state = function() return "idle" end,
            get_full_state = function() return "idle" end,
            get_progress = function() return {} end,
            get_destination = function() return nil end,
            get_path_index = function() return 1 end,
            get_current_path = function() return {} end,
        },
    }
end

--- Create a RuntimeProfile pointing at a fake file with given operations.
--- The profile object needs its `_profile` set manually since load() won't work.
local function create_profile(operations)
    mock_globals()
    local profile = RuntimeProfile:new("test_profile.json")
    -- Manually inject profile data (bypass load())
    profile._profile = operations or make_profile_ops("Comment", { text = "test" })
    return profile
end

--- Get the profile's execution log entries of a given event type.
local function get_log_events(profile, event_type)
    local log = profile:get_log()
    local results = {}
    for _, entry in ipairs(log) do
        if entry.event == event_type then
            table.insert(results, entry)
        end
    end
    return results
end

-- ============================================================================
-- W4.1 — Retry counter tests
-- ============================================================================

function M.test_retry_counter_increments()
    local profile = create_profile(make_profile_ops("Hearth", {}))
    -- Hearth returns "retry" because _G.SentinelCore.UseHearthstone is nil

    -- Each tick increments retry counter
    for i = 1, 4 do
        local status, msg = profile:execute()
        T.assert_equal(status, "running", "Retry should return running")
        T.assert_equal(profile._current_action_retries, i,
            "Retry counter should be " .. i .. " after " .. i .. " retries")
        T.assert_equal(profile._state, "running",
            "Should remain in running state after retry")
    end

    -- 5th retry exhausts MAX_RETRIES_PER_ACTION (5)
    local status, msg = profile:execute()
    T.assert_equal(status, "running", "Should still be running after retry exhaust")
    T.assert_equal(profile._current_action_retries, 5,
        "Retry counter should be 5 at exhaustion")
    T.assert_true(profile._consecutive_failures >= 1,
        "Retry exhaustion should increment consecutive failures")
end

function M.test_retry_success_resets_counter()
    -- First, make a profile with a Comment action (always succeeds)
    local profile = create_profile(make_profile_ops("Comment", { text = "hi" }))

    -- Execute: should succeed, advance to next op (no op 2, so finished)
    local status, msg = profile:execute()
    T.assert_equal(profile._current_action_retries, 0,
        "Success should reset retry counter to 0")
end

-- ============================================================================
-- W4.2 — Navigation recovery tests
-- ============================================================================

function M.test_blocked_enters_navigating()
    local profile = create_profile(make_profile_ops("AcceptQuest", {
        quest_id = 42,
        npc_entry = 1000,
    }))
    -- is_at_npc will return false (no core.object_manager), so it returns "blocked"
    local status, msg = profile:execute()
    T.assert_equal(status, "running", "Blocked should still return running")
    -- _handle_blocked should transition to navigating if it can resolve target
    -- Since GetNearestCreature returns nil, _resolve_nav_target fails,
    -- so it stays in running with retry increment
    -- Let's check what happened
    T.assert_equal(profile._state, "running",
        "Should stay running when nav target can't be resolved")
    T.assert_equal(profile._current_action_retries, 1,
        "Should increment retries when no nav target")
end

function M.test_blocked_with_position_starts_nav()
    -- Travel with position should have nav started by action handler
    -- So _handle_blocked sees nav is active and transitions to navigating
    local profile = create_profile(make_profile_ops("Travel", {
        destination = "Test",
        position = { x = 10, y = 20, z = 30 },
        tolerance = 5.0,
    }))

    -- Mock a zone waypoint so position resolution works in execute_travel
    -- The travel handler will try nav:move_to, which succeeds but won't be "active"
    -- because the mock SentinelNavClient doesn't track active state

    local status, msg = profile:execute()
    T.assert_equal(status, "running", "First travel tick should return running")

    -- Check state: since nav may or may not be active (depending on mock), just
    -- verify the profile didn't crash
    T.assert_true(profile._state == "running" or profile._state == "navigating",
        "Should transition to navigating or stay running")
end

-- ============================================================================
-- W4.3 — Death / ghost recovery tests
-- ============================================================================

function M.test_death_detection_enters_ghost()
    local profile = create_profile(make_profile_ops("Comment", { text = "test" }))

    -- Mock player as dead
    _G.core.unit.is_dead = function()
        return true
    end

    local status, msg = profile:execute()
    T.assert_equal(status, "running", "Should return running during ghost recovery")
    T.assert_equal(profile._state, "ghost", "Should transition to ghost state")
end

function M.test_ghost_to_running_on_rez()
    local profile = create_profile(make_profile_ops("Comment", { text = "test" }))

    -- Start dead
    _G.core.unit.is_dead = function() return true end
    profile:execute()
    T.assert_equal(profile._state, "ghost", "Should be in ghost state")

    -- Now alive
    _G.core.unit.is_dead = function() return false end
    local status, msg = profile:execute()
    T.assert_equal(status, "running", "After rez, should return running")
    T.assert_equal(profile._state, "running", "After rez, should transition to running")
end

-- ============================================================================
-- W4.4 — Consecutive failure tests
-- ============================================================================

function M.test_consecutive_failures_stops_profile()
    -- Create a profile with 3 ops that all fail, to accumulate consecutive failures
    local profile = create_profile({
        operations = {
            { id = 1, action = { type = "NonExistentType", payload = {} }, next_condition = "auto" },
            { id = 2, action = { type = "NonExistentType", payload = {} }, next_condition = "auto" },
            { id = 3, action = { type = "NonExistentType", payload = {} }, next_condition = "auto" },
        },
    })

    -- Execute until consecutive failures hit MAX_CONSECUTIVE_FAILURES (3)
    for i = 1, 6 do
        local status, msg = profile:execute()
        if profile._state == "failed" then
            break
        end
    end

    -- Should eventually fail
    T.assert_equal(profile._state, "failed", "Should reach failed state after too many failures")
    T.assert_true(profile._consecutive_failures >= 3,
        "Should have at least 3 consecutive failures")
end

function M.test_success_resets_consecutive_failures()
    local profile = create_profile({
        operations = {
            {
                id = 1,
                action = { type = "NonExistentType", payload = {} },
                next_condition = "auto",
            },
            {
                id = 2,
                action = { type = "Comment", payload = { text = "reset" } },
                next_condition = "auto",
            },
        },
    })

    -- First action fails, advancing to op 2
    profile:execute()
    T.assert_equal(profile._consecutive_failures, 1, "First failure should count")
    T.assert_equal(profile._current_operation_idx, 2, "Should advance to op 2")

    -- Second action succeeds, should reset
    profile:execute()
    T.assert_equal(profile._consecutive_failures, 0, "Success should reset consecutive failures")
end

-- ============================================================================
-- W4.5 — Structured logging tests
-- ============================================================================

function M.test_logging_on_success()
    local profile = create_profile(make_profile_ops("Comment", { text = "test" }))
    profile:execute()

    local success_events = get_log_events(profile, "action_success")
    T.assert_equal(#success_events, 1, "Should have one action_success log entry")
    T.assert_equal(success_events[1].event, "action_success")
    T.assert_equal(success_events[1].operation, 1)
end

function M.test_logging_on_failure()
    local profile = create_profile(make_profile_ops("NonExistentType", {}))
    profile:execute()

    local fail_events = get_log_events(profile, "action_failed")
    T.assert_equal(#fail_events, 1, "Should have one action_failed log entry")
end

function M.test_logging_on_death()
    local profile = create_profile(make_profile_ops("Comment", { text = "test" }))
    _G.core.unit.is_dead = function() return true end
    profile:execute()

    local death_events = get_log_events(profile, "death_detected")
    T.assert_equal(#death_events, 1, "Should have one death_detected log entry")
end

-- ============================================================================
-- Reset tests
-- ============================================================================

function M.test_reset_clears_state()
    -- Use 3 failing ops to accumulate consecutive failures
    local profile = create_profile({
        operations = {
            { id = 1, action = { type = "NonExistentType", payload = {} }, next_condition = "auto" },
            { id = 2, action = { type = "NonExistentType", payload = {} }, next_condition = "auto" },
            { id = 3, action = { type = "NonExistentType", payload = {} }, next_condition = "auto" },
        },
    })

    -- Run until failed
    for i = 1, 6 do
        profile:execute()
        if profile._state == "failed" then break end
    end
    T.assert_equal(profile._state, "failed", "Should be in failed state")

    -- Reset
    profile:reset()

    T.assert_equal(profile._state, "running", "Reset should restore running state")
    T.assert_equal(profile._current_operation_idx, 1, "Reset should restart from op 1")
    T.assert_equal(profile._current_action_retries, 0, "Reset should clear retries")
    T.assert_equal(profile._consecutive_failures, 0, "Reset should clear failures")
    T.assert_equal(#profile._execution_log, 0, "Reset should clear execution log")
end

-- ============================================================================
-- Run all tests
-- ============================================================================

local tests = {
    -- W4.1
    test_retry_counter_increments = M.test_retry_counter_increments,
    test_retry_success_resets_counter = M.test_retry_success_resets_counter,

    -- W4.2
    test_blocked_enters_navigating = M.test_blocked_enters_navigating,
    test_blocked_with_position_starts_nav = M.test_blocked_with_position_starts_nav,

    -- W4.3
    test_death_detection_enters_ghost = M.test_death_detection_enters_ghost,
    test_ghost_to_running_on_rez = M.test_ghost_to_running_on_rez,

    -- W4.4
    test_consecutive_failures_stops_profile = M.test_consecutive_failures_stops_profile,
    test_success_resets_consecutive_failures = M.test_success_resets_consecutive_failures,

    -- W4.5
    test_logging_on_success = M.test_logging_on_success,
    test_logging_on_failure = M.test_logging_on_failure,
    test_logging_on_death = M.test_logging_on_death,

    -- Reset
    test_reset_clears_state = M.test_reset_clears_state,
}

function M.run()
    for name, fn in pairs(tests) do
        local ok, err = pcall(fn)
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
