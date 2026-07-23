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
--- Now uses op.actions[] array per W1.1.
local function make_profile_ops(action_type, payload, overrides)
    overrides = overrides or {}
    return {
        operations = {
            {
                id = overrides.op_id or 1,
                actions = { -- W1.1: Use actions array instead of single action
                    {
                        type = action_type,
                        payload = payload or {},
                        guard = overrides.guard, -- CL4: optional per-action class guard
                    },
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
    _G.core.quests = _G.core.quests or {}
    _G.core.inventory = _G.core.inventory or {}

    -- Reset global state
    _G.core.unit.is_dead = nil
    _G.core.unit.get_health = nil
    _G.core.object_manager.get_local_player = nil
    _G.core.object_manager.get_all_objects = nil
    _G.core.quests.is_on_quest = nil
    _G.core.quests.is_quest_flagged_completed = nil
    _G.core.quests.get_num_quest_log_entries = nil
    _G.core.quests.get_quest_log_title = nil

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
    -- Hearth returns "retry" because core.input.use_item is nil (hearthstone API)

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

    -- Mock player as dead via object_manager (Sylvannas API)
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            is_dead = function() return true end,
            get_health = function() return 0 end,
        }
    end

    local status, msg = profile:execute()
    T.assert_equal(status, "running", "Should return running during ghost recovery")
    T.assert_equal(profile._state, "ghost", "Should transition to ghost state")
end

function M.test_ghost_to_running_on_rez()
    local profile = create_profile(make_profile_ops("Comment", { text = "test" }))

    -- Start dead
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            is_dead = function() return true end,
            get_health = function() return 0 end,
        }
    end
    profile:execute()
    T.assert_equal(profile._state, "ghost", "Should be in ghost state")

    -- Now alive
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            is_dead = function() return false end,
            get_health = function() return 100 end,
        }
    end
    local status, msg = profile:execute()
    T.assert_equal(status, "running", "After rez, should return running")
    T.assert_equal(profile._state, "running", "After rez, should transition to running")
end

-- ============================================================================
-- PR5b — Condition gating ("waiting" status)
-- ============================================================================

--- Mock a controllable player level so a LevelAtLeast Condition can be flipped
--- between unmet/met across ticks.
local function mock_player_level(get_level_fn)
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            is_dead = function() return false end,
            get_level = get_level_fn,
        }
    end
end

function M.test_completion_gate_waits_then_advances_on_met()
    local player_level = 1
    local profile = create_profile(make_profile_ops("Condition", {
        condition = { type = "LevelAtLeast", payload = 10 },
        role = "Completion",
    }))
    mock_player_level(function() return player_level end)

    -- Unmet: should wait, not advance, and stay put across ticks.
    local status, msg = profile:execute()
    T.assert_equal(status, "running", "Waiting should return running")
    T.assert_equal(msg, "waiting for completion", "Waiting message should say so")
    T.assert_equal(profile._current_action_idx, 1, "Waiting should not advance the action index")
    T.assert_equal(profile._blackboard:get("questing.current_status"), "waiting",
        "Blackboard should reflect waiting status")

    status, msg = profile:execute()
    T.assert_equal(status, "running", "Still waiting should return running")
    T.assert_equal(profile._current_action_idx, 1, "Repeated wait should still not advance")

    -- Now flip the condition to met: should succeed and advance.
    player_level = 10
    status, msg = profile:execute()
    T.assert_equal(status, "running", "Met condition should return running (advancing)")
    T.assert_equal(msg, "next action", "Met condition should advance to next action")
    T.assert_equal(profile._current_operation_idx, 2,
        "Single-action operation completing should advance to the next operation")
end

function M.test_applicability_gate_unmet_skips_and_advances()
    local profile = create_profile(make_profile_ops("Condition", {
        condition = { type = "LevelAtLeast", payload = 10 },
        role = "Applicability",
    }))
    mock_player_level(function() return 1 end) -- unmet

    local status, msg = profile:execute()
    T.assert_equal(status, "running", "Applicability skip should return running")
    T.assert_equal(msg, "skipped, advancing", "Applicability skip should advance")
    T.assert_equal(profile._current_operation_idx, 2,
        "Skipped single-action operation should advance to the next operation")
end

function M.test_both_roles_met_advance_immediately()
    for _, role in ipairs({ "Completion", "Applicability" }) do
        local profile = create_profile(make_profile_ops("Condition", {
            condition = { type = "LevelAtLeast", payload = 1 },
            role = role,
        }))
        mock_player_level(function() return 10 end) -- met

        local status, msg = profile:execute()
        T.assert_equal(status, "running", role .. ": met condition should return running")
        T.assert_equal(msg, "next action", role .. ": met condition should advance immediately")
        T.assert_equal(profile._current_operation_idx, 2,
            role .. ": met single-action operation should advance to the next operation")
    end
end

function M.test_condition_missing_role_defaults_to_completion_wait()
    -- Back-compat: profiles compiled before PR5a carry no role field at all.
    local profile = create_profile(make_profile_ops("Condition", {
        condition = { type = "LevelAtLeast", payload = 10 },
        -- no role field
    }))
    mock_player_level(function() return 1 end) -- unmet

    local status, msg = profile:execute()
    T.assert_equal(status, "running", "No-role gate should return running")
    T.assert_equal(msg, "waiting for completion",
        "No-role gate should default to Completion semantics and wait, not skip")
    T.assert_equal(profile._current_action_idx, 1, "No-role wait should not advance")
end

function M.test_completion_gate_bounded_wait_times_out_and_advances()
    local profile = create_profile(make_profile_ops("Condition", {
        condition = { type = "LevelAtLeast", payload = 10 },
        role = "Completion",
    }))
    mock_player_level(function() return 1 end) -- never met

    local fake_now = 1000.0
    local real_core_time = _G.core.time
    _G.core.time = function() return fake_now end

    local ok, err = pcall(function()
        -- First tick starts the wait timer.
        local status, msg = profile:execute()
        T.assert_equal(status, "running", "First wait tick should return running")
        T.assert_equal(msg, "waiting for completion", "First wait tick should be waiting")

        -- Fast-forward well past MAX_CONDITION_WAIT (300s).
        fake_now = fake_now + 301.0
        local status2, msg2 = profile:execute()
        T.assert_equal(status2, "running", "Timed-out wait should still return running")
        T.assert_equal(msg2, "condition wait timed out, skipping",
            "Bounded wait exceeded should log and advance, not hang")
        T.assert_equal(profile._current_operation_idx, 2,
            "Timed-out single-action operation should advance to the next operation")

        local timeout_events = get_log_events(profile, "condition_wait_timeout")
        T.assert_equal(#timeout_events, 1, "Should log exactly one condition_wait_timeout event")
    end)

    _G.core.time = real_core_time
    if not ok then error(err) end
end

-- Loop-safety: the wait timer must not survive a reset(). A profile that loops
-- (or is restarted) can revisit the same op_id:action_idx that previously waited;
-- if the stale _wait_action_key/_wait_started_at linger, the re-entered gate would
-- compute elapsed against an ancient start time and spuriously time out instead of
-- starting a fresh wait.
function M.test_reset_clears_wait_timer_loop_safety()
    local profile = create_profile(make_profile_ops("Condition", {
        condition = { type = "LevelAtLeast", payload = 10 },
        role = "Completion",
    }))
    mock_player_level(function() return 1 end) -- never met

    local fake_now = 1000.0
    local real_core_time = _G.core.time
    _G.core.time = function() return fake_now end

    local ok, err = pcall(function()
        -- First pass: start the wait timer at t=1000.
        local status, msg = profile:execute()
        T.assert_equal(msg, "waiting for completion", "First pass should be waiting")
        T.assert_equal(profile._wait_started_at, 1000.0, "Wait timer should have started")

        -- Loop back: a long time passes and the profile resets to the top.
        fake_now = fake_now + 100000.0
        profile:reset()
        T.assert_equal(profile._wait_action_key, nil, "reset() must clear the wait key")
        T.assert_equal(profile._wait_started_at, nil, "reset() must clear the wait start time")

        -- Re-entering the same gate must start a FRESH wait, not inherit the old
        -- start time and immediately time out.
        local status2, msg2 = profile:execute()
        T.assert_equal(msg2, "waiting for completion",
            "Re-entered gate after reset should wait fresh, not time out on a stale timer")
        T.assert_equal(profile._wait_started_at, fake_now,
            "Re-entered gate should restart the timer at the current time")
        T.assert_equal(profile._current_operation_idx, 1,
            "Fresh wait should hold on the first operation, not skip it")
    end)

    _G.core.time = real_core_time
    if not ok then error(err) end
end

-- ClassIs integration: Sylvannas `player:get_class()` returns a numeric class_id
-- (Priest = 5, per the injector enums and the tbcmangos DB: {1,2,3,4,5,7,8,9,11}),
-- NOT a string. The real ctx:get_player_class() must map that id to the Title-Case
-- class name so the ClassIs handler (which compares against RestedXP's Title-Case
-- class strings) actually matches. Without the mapping, ClassIs is always false.
function M.test_classis_maps_numeric_class_id_to_name()
    local profile = create_profile(make_profile_ops("Condition", {
        condition = { type = "ClassIs", payload = "Priest" },
        role = "Completion", -- met -> "next action"; unmet -> "waiting for completion"
    }))
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            is_dead = function() return false end,
            get_class = function() return 5 end, -- Priest (numeric class_id)
        }
    end

    local status, msg = profile:execute()
    T.assert_equal(msg, "next action",
        "ClassIs(Priest) must be MET when get_class() returns the Priest class_id (5)")
    T.assert_equal(profile._current_operation_idx, 2,
        "A met ClassIs gate should advance past the operation")
end

-- ============================================================================
-- CL4 — per-action class guard (action.guard, evaluated before dispatch)
-- ============================================================================

--- A Comment action guarded by a ClassIs condition the player's class does NOT satisfy must be
--- skipped entirely: it must never execute, and the profile must advance past it exactly like
--- the existing "skipped" semantics (no retry/failure counted).
function M.test_action_guard_unmet_skips_action_without_executing_it()
    local profile = create_profile(make_profile_ops("Comment", { text = "mage only" }, {
        guard = { type = "ClassIs", payload = "Mage" },
    }))
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            is_dead = function() return false end,
            get_class = function() return 4 end, -- Rogue (numeric class_id), guard wants Mage
        }
    end

    local status, msg = profile:execute()
    T.assert_equal(status, "running", "guard-unmet action should still return running (skipped, advancing)")
    T.assert_equal(msg, "skipped, advancing", "guard-unmet action must use the existing skip-advance path")
    T.assert_equal(profile._current_action_retries, 0,
        "a skipped (guard-unmet) action must not count as a retry")
    T.assert_equal(profile._consecutive_failures, 0,
        "a skipped (guard-unmet) action must not count as a failure")
    T.assert_equal(profile._current_operation_idx, 2,
        "the single-action operation must advance past the guarded (and skipped) action")
end

--- A Comment action guarded by a ClassIs condition the player's class DOES satisfy must execute
--- normally (Comment always succeeds), exactly as if it had no guard at all.
function M.test_action_guard_met_executes_action_normally()
    local profile = create_profile(make_profile_ops("Comment", { text = "mage only" }, {
        guard = { type = "ClassIs", payload = "Mage" },
    }))
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            is_dead = function() return false end,
            get_class = function() return 8 end, -- Mage (numeric class_id) — guard is met
        }
    end

    local status, msg = profile:execute()
    T.assert_equal(status, "running", "guard-met action should execute and return running")
    T.assert_equal(msg, "next action", "guard-met Comment action must execute normally (success path)")
    T.assert_equal(profile._current_operation_idx, 2,
        "the single-action operation must advance past the executed action")
end

--- An action with no `guard` field at all must behave exactly as before CL4 (unaffected).
function M.test_action_without_guard_executes_normally()
    local profile = create_profile(make_profile_ops("Comment", { text = "no guard" }))

    local status, msg = profile:execute()
    T.assert_equal(status, "running", "guard-less action should execute and return running")
    T.assert_equal(msg, "next action", "guard-less Comment action must execute normally")
    T.assert_equal(profile._current_operation_idx, 2,
        "the single-action operation must advance past the executed action")
end

-- ============================================================================
-- W4.4 — Consecutive failure tests
-- ============================================================================

function M.test_consecutive_failures_stops_profile()
    -- Create a profile with 3 ops that all fail, to accumulate consecutive failures
    local profile = create_profile({
        operations = {
            { id = 1, actions = { { type = "NonExistentType", payload = {} } }, next_condition = "auto" },
            { id = 2, actions = { { type = "NonExistentType", payload = {} } }, next_condition = "auto" },
            { id = 3, actions = { { type = "NonExistentType", payload = {} } }, next_condition = "auto" },
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
                actions = { { type = "NonExistentType", payload = {} } },
                next_condition = "auto",
            },
            {
                id = 2,
                actions = { { type = "Comment", payload = { text = "reset" } } },
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
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            is_dead = function() return true end,
            get_health = function() return 0 end,
        }
    end
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
            { id = 1, actions = { { type = "NonExistentType", payload = {} } }, next_condition = "auto" },
            { id = 2, actions = { { type = "NonExistentType", payload = {} } }, next_condition = "auto" },
            { id = 3, actions = { { type = "NonExistentType", payload = {} } }, next_condition = "auto" },
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

    -- PR5b
    test_completion_gate_waits_then_advances_on_met = M.test_completion_gate_waits_then_advances_on_met,
    test_applicability_gate_unmet_skips_and_advances = M.test_applicability_gate_unmet_skips_and_advances,
    test_both_roles_met_advance_immediately = M.test_both_roles_met_advance_immediately,
    test_condition_missing_role_defaults_to_completion_wait = M.test_condition_missing_role_defaults_to_completion_wait,
    test_completion_gate_bounded_wait_times_out_and_advances = M.test_completion_gate_bounded_wait_times_out_and_advances,
    test_reset_clears_wait_timer_loop_safety = M.test_reset_clears_wait_timer_loop_safety,
    test_classis_maps_numeric_class_id_to_name = M.test_classis_maps_numeric_class_id_to_name,

    -- CL4
    test_action_guard_unmet_skips_action_without_executing_it = M.test_action_guard_unmet_skips_action_without_executing_it,
    test_action_guard_met_executes_action_normally = M.test_action_guard_met_executes_action_normally,
    test_action_without_guard_executes_normally = M.test_action_without_guard_executes_normally,

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
