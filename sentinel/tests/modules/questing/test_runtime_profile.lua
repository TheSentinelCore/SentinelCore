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
    _G.core.input = _G.core.input or {}
    _G.core.quests = _G.core.quests or {}
    _G.core.inventory = _G.core.inventory or {}

    -- Reset global state. Death/health state is read off the game_object
    -- returned by get_local_player() (is_dead()/get_health() methods), not a
    -- fictional core.unit.* namespace — see sylvannas_api.lua mock header.
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

    -- 5th retry exhausts MAX_RETRIES_PER_ACTION (5). A1: _advance_action resets the retry
    -- counter to 0 as part of moving past the exhausted action, so the NEXT action starts with
    -- its own fresh budget instead of inheriting an already-exhausted counter.
    local status, msg = profile:execute()
    T.assert_equal(status, "running", "Should still be running after retry exhaust")
    T.assert_equal(profile._current_action_retries, 0,
        "Retry counter should reset to 0 after advancing past the exhausted action (A1)")
    T.assert_true(profile._consecutive_failures >= 1,
        "Retry exhaustion should increment consecutive failures")
end

function M.test_a1_each_retry_returning_action_gets_full_budget()
    -- A1 repro (PROVEN in the audit register): 4 retry-returning actions in one operation.
    -- Before the fix, only the FIRST action in an operation got a fresh retry counter (reset
    -- happened only on success or operation change) — every action after it inherited a
    -- shared, already-exhausted counter. Action 1 got 5 attempts; actions 2/3/4 got exactly
    -- ONE each; _consecutive_failures hit MAX_CONSECUTIVE_FAILURES (3) and the profile entered
    -- "failed" after only ~7 ticks. With _advance_action resetting the counter on every
    -- advance, each action gets its own MAX_RETRIES_PER_ACTION (5) budget, so the profile must
    -- survive at least 3 actions x 5 retries = 15 ticks before the 3rd exhaustion fails it.
    local profile = create_profile({
        operations = {
            {
                id = 1,
                actions = {
                    { type = "Hearth", payload = {} },
                    { type = "Hearth", payload = {} },
                    { type = "Hearth", payload = {} },
                    { type = "Hearth", payload = {} },
                },
                next_condition = "auto",
            },
        },
    })

    local ticks_to_failure = 0
    for _tick = 1, 30 do
        profile:execute()
        ticks_to_failure = ticks_to_failure + 1
        if profile._state == "failed" then break end
    end

    T.assert_true(profile._state == "failed", "profile should eventually fail (all-retry actions)")
    T.assert_true(ticks_to_failure >= 15,
        "each action should get its own full retry budget (expected >=15 ticks to failure, got "
            .. tostring(ticks_to_failure) .. ") — a shared/exhausted counter fails by tick ~7")
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

function M.test_is_at_npc_fails_closed_when_player_pos_unreadable()
    -- A10: get_nearest_creature scans the FULL visible range (get_all_objects), not just
    -- nearby — an NPC found there can be ~90yd away. Without an actual distance check there is
    -- no basis to claim "at" the NPC, so is_at_npc must fail closed (routes callers to
    -- "blocked" -> navigate) instead of the old best-effort "true" when the player position
    -- could not be read.
    local profile = create_profile(make_profile_ops("Comment", { text = "test" }))
    local ctx = profile:create_context()

    _G.core.object_manager.get_all_objects = function()
        return {
            {
                is_valid = function() return true end,
                is_unit = function() return true end,
                get_npc_id = function() return 1000 end,
                get_position = function() return { x = 100, y = 100, z = 0 } end,
            },
        }
    end
    -- No get_local_player mocked here — player position is unreadable.
    _G.core.object_manager.get_local_player = nil

    T.assert_false(ctx:is_at_npc(1000),
        "is_at_npc must return false, not best-effort true, when the player position can't be read")
end

function M.test_navigating_idle_without_arrival_is_not_treated_as_arrival()
    -- B5: _execute_navigating used to treat client state "idle" as arrival with NO position
    -- check. Anything that calls stop() on the shared nav client (combat preempting it, a
    -- reload, another module) drives it idle without the player having actually arrived.
    -- Require a real position confirmation before accepting "idle" as arrival.
    local profile = create_profile(make_profile_ops("Travel", {
        position = { x = 500, y = 500, z = 0 },
        tolerance = 5.0,
    }))
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            get_position = function() return { x = 0, y = 0, z = 0 } end, -- far from the target
        }
    end

    profile._state = "navigating"
    profile._last_blocked_action = profile._profile.operations[1].actions[1]
    local retries_before = profile._current_action_retries
    profile._nav = {
        is_active = function() return false end,
        get_state = function() return "idle" end,
        poll = function() return "idle", {} end,
        stop = function() end,
    }

    profile:execute()

    T.assert_equal(#get_log_events(profile, "nav_arrived"), 0,
        "An idle state hundreds of yards from the destination must not be logged as arrival (B5)")
    T.assert_true(#get_log_events(profile, "nav_idle_unconfirmed") >= 1,
        "An unconfirmed idle must be logged distinctly, not silently accepted as arrival")
    T.assert_true(profile._current_action_retries > retries_before,
        "Unconfirmed idle should count toward the retry budget so this cannot wedge forever")
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

local function make_ghost_player()
    return {
        is_valid = function() return true end,
        -- Ghost form: the client reports is_dead() == FALSE. The old is_dead-only check
        -- resumed the route here and fought wolves as a ghost (live-caught 2026-07-23).
        is_dead = function() return false end,
        is_ghost = function() return true end,
        is_dead_or_ghost = function() return true end,
        get_health = function() return 1 end,
        get_position = function() return { x = 0, y = 0, z = 0 } end,
    }
end

function M.test_ghost_form_stays_in_recovery()
    local profile = create_profile(make_profile_ops("Comment", { text = "test" }))
    _G.core.object_manager.get_local_player = make_ghost_player
    profile:execute()
    T.assert_equal(profile._state, "ghost",
        "ghost form (is_dead false, is_ghost true) must stay in recovery, not resume the route")
end

function M.test_ghost_runs_to_corpse_before_resurrecting()
    local profile = create_profile(make_profile_ops("Comment", { text = "test" }))
    local moved_to = nil
    profile._nav = {
        is_active = function() return false end,
        move_to = function(_self, pos) moved_to = pos return true end,
        stop = function() end,
        get_state = function() return "idle" end,
        poll = function() return "idle", {} end,
    }
    _G.core.object_manager.get_local_player = make_ghost_player
    local res_calls = 0
    _G.core.input = _G.core.input or {}
    _G.core.input.resurrect_corpse = function() res_calls = res_calls + 1 end
    _G.core.game_ui = {
        get_corpse_position = function() return { x = 200, y = 0, z = 0 } end,
        get_resurrect_corpse_delay = function() return 0 end,
    }

    profile:execute() -- death detected, enters ghost state
    profile:execute() -- ghost tick: corpse 200yd out → corpse run, no res spam
    T.assert_not_nil(moved_to, "the ghost must navigate toward the corpse")
    T.assert_equal(moved_to and moved_to.x, 200, "corpse-run destination must be the corpse position")
    T.assert_equal(res_calls, 0, "resurrect_corpse must not be spammed while out of range")

    -- Corpse now in range: the resurrect fires.
    _G.core.game_ui.get_corpse_position = function() return { x = 5, y = 0, z = 0 } end
    profile:execute()
    T.assert_true(res_calls >= 1, "within corpse range the resurrect must be attempted")

    _G.core.game_ui = nil
    _G.core.input.resurrect_corpse = nil
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
    T.assert_equal(profile._blackboard:get("module.questing.current_status"), "waiting",
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

-- ============================================================================
-- F3 — per-tick context churn
-- ============================================================================

--- create_context() used to allocate a brand-new ctx table (plus ~20 fresh method closures)
--- on EVERY call. It must now reuse the same cached table across calls on one profile
--- instance, while still refreshing the fields that legitimately change per call.
function M.test_create_context_reuses_the_same_table_across_calls()
    local profile = create_profile(make_profile_ops("Comment", {}))
    local ctx1 = profile:create_context()
    local ctx2 = profile:create_context()
    T.assert_true(ctx1 == ctx2, "create_context() must reuse the same table, not allocate a new one each call")
end

--- `persist` must still be the SAME table across create_context() calls -- this is the escape
--- hatch that keeps action state (kill tallies, in-flight chase target) alive across ticks.
--- Reusing the cached ctx table must not accidentally break that identity.
function M.test_create_context_persist_field_is_stable_across_calls()
    local profile = create_profile(make_profile_ops("Comment", {}))
    local ctx1 = profile:create_context()
    ctx1.persist.marker = "still here"
    local ctx2 = profile:create_context()
    T.assert_true(ctx2.persist == ctx1.persist, "persist must be the same table across calls")
    T.assert_equal(ctx2.persist.marker, "still here", "persist contents must survive context reuse")
end

--- The quest-log cache must still be reset every call so a stale answer from a previous tick
--- is never silently reused -- reusing the ctx TABLE must not also reuse stale quest state.
function M.test_create_context_resets_quest_log_cache_each_call()
    local profile = create_profile(make_profile_ops("Comment", {}))
    local ctx1 = profile:create_context()
    ctx1._completed_quests["123"] = true
    ctx1._quest_log_dirty = false
    local ctx2 = profile:create_context()
    T.assert_true(ctx2._quest_log_dirty == true, "quest log cache must be marked dirty again on each create_context() call")
    T.assert_true(ctx2._completed_quests["123"] == nil, "stale completed-quest cache must not leak across calls")
end

--- _resolve_nav_target's zone-destination branch used to call create_context() a SECOND time
--- in the same tick when reached through _handle_blocked (itself reached from _execute_running,
--- which had already built one). Prove _handle_blocked, given a pre-built ctx, does not trigger
--- another create_context() call.
function M.test_handle_blocked_zone_destination_does_not_double_build_context()
    local profile = create_profile(make_profile_ops("Travel", { destination = "Elwynn Forest" }))
    mock_globals()

    local original_create_context = RuntimeProfile.create_context
    local call_count = 0
    RuntimeProfile.create_context = function(self)
        call_count = call_count + 1
        return original_create_context(self)
    end

    local ok, err = pcall(function()
        local ctx = profile:create_context() -- simulates the ctx already built this tick
        call_count = 0 -- only count calls made DURING _handle_blocked itself
        profile:_handle_blocked({ type = "Travel", payload = { destination = "Elwynn Forest" } }, ctx)
        T.assert_equal(call_count, 0,
            "_handle_blocked must reuse the ctx passed in, not build a second one for a zone destination")
    end)

    RuntimeProfile.create_context = original_create_context
    if not ok then error(err, 0) end
end

-- ============================================================================
-- The origin-waypoint trap, second consumer.
--
-- `_resolve_nav_target` is a FALLBACK CHAIN: explicit position, then npc_entry, then
-- object_entry, then creature_entries, then the zone-destination string. A zeroed waypoint
-- satisfied step 1 (`elseif p.position.world_x then` — and `0` is TRUTHY in LuaJIT, verified with
-- `luajit -e 'if 0 then print("0 is TRUTHY in LuaJIT") else print("0 is falsy") end'`), so it
-- shadowed every later step and handed nav the world origin. Rejecting the sentinel by VALUE lets
-- resolution fall through to the steps that can still answer.
-- ============================================================================

function M.test_resolve_nav_target_rejects_a_zeroed_waypoint_and_falls_through_to_the_zone()
    local profile = create_profile(make_profile_ops("Travel", {}))
    mock_globals()
    local action = { type = "Travel", payload = {
        destination = "Elwynn Forest",
        position = { map = 0, world_x = 0, world_y = 0, world_z = 0 },
    } }

    local ctx = profile:create_context()
    ctx.get_zone_waypoint = function(_self, _zone) return { x = 42, y = -7, z = 11 } end

    local target = profile:_resolve_nav_target(action, ctx)
    T.assert_not_nil(target, "resolution must continue past a zeroed waypoint, not stop at it")
    T.assert_equal(target.x, 42, "the zone-destination step answers once the sentinel is refused")
    T.assert_equal(target.y, -7)
end

function M.test_resolve_nav_target_returns_nil_when_only_a_zeroed_waypoint_is_available()
    local profile = create_profile(make_profile_ops("Travel", {}))
    mock_globals()
    -- No destination string, no npc/object entry: nothing but the sentinel. nil is the only
    -- honest answer -- returning (0, 0) would send the character across the world.
    local action = { type = "Travel", payload = {
        position = { map = 0, world_x = 0, world_y = 0, world_z = 0 },
    } }
    T.assert_equal(profile:_resolve_nav_target(action, profile:create_context()), nil,
        "a zeroed waypoint with no other source must resolve to nil, never to world origin")
end

function M.test_resolve_nav_target_still_honors_a_real_waypoint_with_one_zero_axis()
    local profile = create_profile(make_profile_ops("Travel", {}))
    mock_globals()
    local action = { type = "Travel", payload = {
        destination = "Elwynn Forest",
        position = { map = 0, world_x = 0, world_y = -132.49, world_z = 83.53 },
    } }
    local target = profile:_resolve_nav_target(action, profile:create_context())
    T.assert_not_nil(target, "x == 0 with a real y is a legitimate coordinate")
    T.assert_equal(target.x, 0)
    T.assert_equal(target.y, -132.49)
end

-- ============================================================================
-- XP1 — `.xp` LevelAtLeast Completion gates: hours-long holds + grind-while-gated
-- ============================================================================

--- Level gate helper: a single-op profile holding on LevelAtLeast(level).
local function make_level_gate_profile(level)
    return create_profile(make_profile_ops("Condition", {
        condition = { type = "LevelAtLeast", payload = level },
        role = "Completion",
    }))
end

--- Mock a player whose level (and optionally XP) the test controls.
local function mock_player_level_xp(get_level_fn, get_xp_fn)
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            is_dead = function() return false end,
            get_level = get_level_fn,
            get_xp = get_xp_fn,
        }
    end
end

--- A LevelAtLeast gate legitimately holds for HOURS. Rising level must reset the bounded-wait
--- clock exactly like a rising kill count does — the gate must NOT be force-advanced at
--- MAX_CONDITION_WAIT while the player is still visibly leveling.
function M.test_level_gate_holds_past_timeout_while_level_rises()
    local profile = make_level_gate_profile(10)
    local player_level = 1
    mock_player_level_xp(function() return player_level end)

    local fake_now = 1000.0
    local real_core_time = _G.core.time
    _G.core.time = function() return fake_now end

    local ok, err = pcall(function()
        local _, msg = profile:execute() -- snapshot level 1 at t=1000
        T.assert_equal(msg, "waiting for completion", "Gate should start waiting")

        -- 299s later the level rises: the clock must reset off the progress.
        fake_now = fake_now + 299.0
        player_level = 2
        local _, msg2 = profile:execute()
        T.assert_equal(msg2, "waiting for completion", "Rising level should keep waiting")

        -- 299s after THAT (598s total — far past MAX_CONDITION_WAIT): still under the
        -- reset clock, so the gate must still hold instead of force-advancing.
        fake_now = fake_now + 299.0
        local _, msg3 = profile:execute()
        T.assert_equal(msg3, "waiting for completion",
            "Level gate must hold past 300s total while leveling progress was observed")
        T.assert_equal(#get_log_events(profile, "condition_wait_timeout"), 0,
            "No timeout event while the player is making level progress")

        -- Frozen from here on: a full MAX_CONDITION_WAIT with no progress still times out
        -- (genuinely stuck must never deadlock the bot).
        fake_now = fake_now + 301.0
        local _, msg4 = profile:execute()
        T.assert_equal(msg4, "condition wait timed out, skipping",
            "A frozen level for a full MAX_CONDITION_WAIT must still force-advance")
    end)

    _G.core.time = real_core_time
    if not ok then error(err) end
end

--- Sub-level progress: XP rising while the level is still frozen must also reset the clock
--- (a slow grind can take >300s per level; XP is the finer-grained liveness signal).
function M.test_level_gate_xp_rise_resets_wait_clock()
    local profile = make_level_gate_profile(10)
    local player_xp = 100
    mock_player_level_xp(function() return 5 end, function() return player_xp end)

    local fake_now = 1000.0
    local real_core_time = _G.core.time
    _G.core.time = function() return fake_now end

    local ok, err = pcall(function()
        profile:execute() -- snapshot level 5 / xp 100 at t=1000
        fake_now = fake_now + 299.0
        player_xp = 350
        local _, msg = profile:execute() -- xp rose: clock resets
        T.assert_equal(msg, "waiting for completion", "Rising XP should keep waiting")
        fake_now = fake_now + 299.0
        local _, msg2 = profile:execute()
        T.assert_equal(msg2, "waiting for completion",
            "598s total but XP progress at 299s: the gate must still hold")
    end)

    _G.core.time = real_core_time
    if not ok then error(err) end
end

--- While a level gate holds the bot must GRIND, not idle: the combat module's world
--- auto-engage flag goes up during the hold and comes back down the moment the gate passes.
function M.test_level_gate_sets_grind_flag_while_holding_and_clears_on_met()
    local profile = make_level_gate_profile(10)
    local player_level = 1
    mock_player_level_xp(function() return player_level end)

    T.assert_true(profile._blackboard:get("module.combat.auto_engage_world", false) ~= true,
        "Grind flag must start unset")

    profile:execute() -- holding
    T.assert_equal(profile._blackboard:get("module.combat.auto_engage_world"), true,
        "Holding level gate must raise the combat world auto-engage (grind) flag")

    player_level = 10
    local _, msg = profile:execute() -- gate passes
    T.assert_equal(msg, "next action", "Met gate should advance")
    T.assert_equal(profile._blackboard:get("module.combat.auto_engage_world"), false,
        "Grind flag must be cleared as soon as the gate passes")
end

--- The grind flag must also come down on the force-advance (timeout) exit path, and a
--- non-level Condition gate must never raise it.
function M.test_level_gate_grind_flag_cleared_on_timeout_and_not_set_for_other_gates()
    -- Timeout path.
    local profile = make_level_gate_profile(10)
    mock_player_level_xp(function() return 1 end) -- frozen forever

    local fake_now = 1000.0
    local real_core_time = _G.core.time
    _G.core.time = function() return fake_now end

    local ok, err = pcall(function()
        profile:execute()
        T.assert_equal(profile._blackboard:get("module.combat.auto_engage_world"), true,
            "Holding level gate must raise the grind flag")
        fake_now = fake_now + 301.0
        local _, msg = profile:execute()
        T.assert_equal(msg, "condition wait timed out, skipping", "Frozen gate should time out")
        T.assert_equal(profile._blackboard:get("module.combat.auto_engage_world"), false,
            "Grind flag must be cleared on the timeout exit path")
    end)
    _G.core.time = real_core_time
    if not ok then error(err) end

    -- Non-level gate: never raised.
    local other = create_profile(make_profile_ops("Condition", {
        condition = { type = "QuestCompleted", payload = 1234 },
        role = "Completion",
    }))
    _G.core.quests.is_quest_flagged_completed = function() return false end
    local _, msg = other:execute()
    T.assert_equal(msg, "waiting for completion", "Quest gate should be waiting")
    T.assert_true(other._blackboard:get("module.combat.auto_engage_world", false) ~= true,
        "A non-level Condition gate must not raise the grind flag")
    _G.core.quests.is_quest_flagged_completed = nil
end

-- ============================================================================
-- Mid-flight applicability: a trip that stopped being worth finishing
-- ============================================================================
--
-- USER-REPORTED: accept "A Threat Within" by hand and the bot still walks the whole way to
-- the quest giver. Route reconciliation gets this RIGHT at load and on every operation
-- advance (verified against the real 1-11-Elwynn-Forest profile: with 783 in the log it
-- starts at op 11, skipping the accept at op 10). The hole is narrower: the
-- `_operation_already_done` skip lives in _execute_running and only fires at action index 1,
-- so once a Travel action has handed control to the "navigating" state, nothing re-asks
-- whether the destination still matters. The bot commits to arriving.

function M.test_navigation_aborts_when_quest_work_satisfied_mid_flight()
    local ops = {
        operations = {
            {
                id = 1,
                actions = {
                    { type = "Travel", payload = {
                        destination = "Elwynn Forest",
                        position = { x = 1, y = 1, z = 1 },
                    } },
                    { type = "AcceptQuest", payload = { quest_id = 783, npc_entry = 823 } },
                },
                next_condition = "auto",
            },
            {
                id = 2,
                actions = { { type = "Comment", payload = { text = "the step after" } } },
                next_condition = "auto",
            },
        },
    }
    local profile = create_profile(ops)

    -- Accepted BY HAND while the bot is already en route to the quest giver.
    _G.core.quests.is_on_quest = function(id) return id == 783 end
    _G.core.quests.is_quest_flagged_completed = function() return false end
    _G.core.quests.get_num_quest_log_entries = function() return 0 end
    _G.core.quests.get_quest_log_title = function() return nil end

    local stop_reason = nil
    profile._nav = {
        is_active = function() return true end,
        poll = function() return "moving", {} end,
        get_state = function() return "moving" end,
        move_to = function() return true end,
        stop = function(_, reason) stop_reason = reason end,
    }
    profile._state = "navigating"
    profile._current_operation_idx = 1
    profile._current_action_idx = 1
    profile._nav_start_time = 0

    profile:execute()

    T.assert_true(stop_reason ~= nil,
        "navigation must be stopped once the trip has become moot")
    T.assert_equal(profile._current_operation_idx, 2,
        "the satisfied operation must be skipped instead of walked to")
end

--- The mirror case: nothing has changed, so the trip must continue. A recheck that
--- aborts navigation for an operation still genuinely pending would strand the route.
function M.test_navigation_continues_while_quest_work_is_pending()
    local ops = {
        operations = {
            {
                id = 1,
                actions = {
                    { type = "Travel", payload = {
                        destination = "Elwynn Forest",
                        position = { x = 1, y = 1, z = 1 },
                    } },
                    { type = "AcceptQuest", payload = { quest_id = 783, npc_entry = 823 } },
                },
                next_condition = "auto",
            },
            {
                id = 2,
                actions = { { type = "Comment", payload = { text = "the step after" } } },
                next_condition = "auto",
            },
        },
    }
    local profile = create_profile(ops)

    -- Quest neither accepted nor rewarded: this trip is still required.
    _G.core.quests.is_on_quest = function() return false end
    _G.core.quests.is_quest_flagged_completed = function() return false end
    _G.core.quests.get_num_quest_log_entries = function() return 0 end
    _G.core.quests.get_quest_log_title = function() return nil end

    local stop_reason = nil
    profile._nav = {
        is_active = function() return true end,
        poll = function() return "moving", {} end,
        get_state = function() return "moving" end,
        move_to = function() return true end,
        stop = function(_, reason) stop_reason = reason end,
    }
    profile._state = "navigating"
    profile._current_operation_idx = 1
    profile._current_action_idx = 1
    profile._nav_start_time = 0

    profile:execute()

    T.assert_true(stop_reason == nil,
        "a still-needed trip must not be aborted, got stop reason " .. tostring(stop_reason))
    T.assert_equal(profile._current_operation_idx, 1,
        "a pending operation must stay the current one")
end

local tests = {
    test_navigation_aborts_when_quest_work_satisfied_mid_flight =
        M.test_navigation_aborts_when_quest_work_satisfied_mid_flight,
    test_navigation_continues_while_quest_work_is_pending =
        M.test_navigation_continues_while_quest_work_is_pending,
    -- F3
    test_create_context_reuses_the_same_table_across_calls = M.test_create_context_reuses_the_same_table_across_calls,
    test_create_context_persist_field_is_stable_across_calls = M.test_create_context_persist_field_is_stable_across_calls,
    test_create_context_resets_quest_log_cache_each_call = M.test_create_context_resets_quest_log_cache_each_call,
    test_handle_blocked_zone_destination_does_not_double_build_context = M.test_handle_blocked_zone_destination_does_not_double_build_context,
    test_resolve_nav_target_rejects_a_zeroed_waypoint_and_falls_through_to_the_zone = M.test_resolve_nav_target_rejects_a_zeroed_waypoint_and_falls_through_to_the_zone,
    test_resolve_nav_target_returns_nil_when_only_a_zeroed_waypoint_is_available = M.test_resolve_nav_target_returns_nil_when_only_a_zeroed_waypoint_is_available,
    test_resolve_nav_target_still_honors_a_real_waypoint_with_one_zero_axis = M.test_resolve_nav_target_still_honors_a_real_waypoint_with_one_zero_axis,

    -- W4.1
    test_retry_counter_increments = M.test_retry_counter_increments,
    test_retry_success_resets_counter = M.test_retry_success_resets_counter,
    test_a1_each_retry_returning_action_gets_full_budget = M.test_a1_each_retry_returning_action_gets_full_budget,

    -- W4.2
    test_blocked_enters_navigating = M.test_blocked_enters_navigating,
    test_blocked_with_position_starts_nav = M.test_blocked_with_position_starts_nav,
    test_is_at_npc_fails_closed_when_player_pos_unreadable = M.test_is_at_npc_fails_closed_when_player_pos_unreadable,
    test_navigating_idle_without_arrival_is_not_treated_as_arrival = M.test_navigating_idle_without_arrival_is_not_treated_as_arrival,

    -- W4.3
    test_death_detection_enters_ghost = M.test_death_detection_enters_ghost,
    test_ghost_to_running_on_rez = M.test_ghost_to_running_on_rez,
    test_ghost_form_stays_in_recovery = M.test_ghost_form_stays_in_recovery,
    test_ghost_runs_to_corpse_before_resurrecting = M.test_ghost_runs_to_corpse_before_resurrecting,

    -- PR5b
    test_completion_gate_waits_then_advances_on_met = M.test_completion_gate_waits_then_advances_on_met,
    test_applicability_gate_unmet_skips_and_advances = M.test_applicability_gate_unmet_skips_and_advances,
    test_both_roles_met_advance_immediately = M.test_both_roles_met_advance_immediately,
    test_condition_missing_role_defaults_to_completion_wait = M.test_condition_missing_role_defaults_to_completion_wait,
    test_completion_gate_bounded_wait_times_out_and_advances = M.test_completion_gate_bounded_wait_times_out_and_advances,
    test_reset_clears_wait_timer_loop_safety = M.test_reset_clears_wait_timer_loop_safety,
    test_classis_maps_numeric_class_id_to_name = M.test_classis_maps_numeric_class_id_to_name,

    -- XP1 — `.xp` LevelAtLeast gates
    test_level_gate_holds_past_timeout_while_level_rises = M.test_level_gate_holds_past_timeout_while_level_rises,
    test_level_gate_xp_rise_resets_wait_clock = M.test_level_gate_xp_rise_resets_wait_clock,
    test_level_gate_sets_grind_flag_while_holding_and_clears_on_met = M.test_level_gate_sets_grind_flag_while_holding_and_clears_on_met,
    test_level_gate_grind_flag_cleared_on_timeout_and_not_set_for_other_gates = M.test_level_gate_grind_flag_cleared_on_timeout_and_not_set_for_other_gates,

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
    -- Deterministic order: `pairs` varies per run, turning cross-suite state leakage into an
    -- intermittent failure that reads as flaky.
    local names = {}
    for name in pairs(tests) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(tests[name])
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
