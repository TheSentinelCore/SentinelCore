-- tests/modules/questing/test_runner_state.lua
-- Unit tests for the runner cockpit view-model (pure logic, no Sylvannas rendering).
-- The cockpit's value is answering operator questions — is it alive, is it progressing, why is
-- it blocked, is it lying to me, when do I intervene — so those are exactly what is tested here.

local RunnerState = require("modules/questing/runner_state")
local T = require("tests/test_util")

local M = {}

--- Minimal fake executor exposing only what the view-model reads.
local function fake_executor(o)
    o = o or {}
    return {
        _state = o.state or "running",
        _current_operation_idx = o.op or 1,
        _current_action_idx = o.action_idx or 1,
        _current_action_retries = o.retries or 0,
        _consecutive_failures = o.failures or 0,
        _wait_started_at = o.wait_started_at,
        _wait_action_key = o.wait_key,
        _execution_log = o.log or {},
        _profile = { operations = o.operations or {} },
    }
end

local function ops(n, action_type)
    local list = {}
    for i = 1, n do
        list[i] = { id = i, actions = { { type = action_type or "Comment", payload = {} } } }
    end
    return list
end

-- ============================================================================
-- Health verdict — the one-glance "do I need to intervene?" answer
-- ============================================================================

function M.test_idle_when_no_executor()
    local vm = RunnerState.build({ executor = nil, now = 100 })
    T.assert_equal(vm.health.status, "IDLE", "no executor should read IDLE")
    T.assert_equal(vm.health.is_alarm, false, "IDLE is not an alarm state")
end

function M.test_running_is_not_an_alarm()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(10) }),
        now = 100, started_at = 100,
    })
    T.assert_equal(vm.health.status, "RUNNING", "running executor reads RUNNING")
    T.assert_equal(vm.health.is_alarm, false, "RUNNING is not an alarm")
end

function M.test_failed_state_is_an_alarm()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "failed", operations = ops(10) }),
        now = 100, started_at = 0,
    })
    T.assert_equal(vm.health.status, "FAILED", "failed executor reads FAILED")
    T.assert_equal(vm.health.is_alarm, true, "FAILED must raise an alarm")
end

-- A long wait is the failure mode a status-only UI hides: WAITING 4s and WAITING 40m look
-- identical unless the view-model promotes a stale wait to STUCK.
function M.test_long_wait_is_promoted_to_stuck()
    local vm = RunnerState.build({
        executor = fake_executor({
            state = "running", wait_started_at = 100, wait_key = "1:1", operations = ops(10),
        }),
        now = 100 + 400, started_at = 0, stall_threshold_s = 300,
    })
    T.assert_equal(vm.health.status, "STUCK", "a wait past the stall threshold must read STUCK")
    T.assert_equal(vm.health.is_alarm, true, "STUCK must raise an alarm")
end

function M.test_short_wait_is_not_stuck()
    local vm = RunnerState.build({
        executor = fake_executor({
            state = "running", wait_started_at = 100, wait_key = "1:1", operations = ops(10),
        }),
        now = 100 + 5, started_at = 0, stall_threshold_s = 300,
    })
    T.assert_equal(vm.health.status, "WAITING", "a fresh wait reads WAITING, not STUCK")
    T.assert_equal(vm.health.is_alarm, false, "a short wait is not an alarm")
end

-- ============================================================================
-- Liveness — time in step / since progress (the signal the first mockup lacked)
-- ============================================================================

function M.test_liveness_reports_wait_duration()
    local vm = RunnerState.build({
        executor = fake_executor({
            state = "running", wait_started_at = 1000, wait_key = "1:1", operations = ops(10),
        }),
        now = 1042, started_at = 900,
    })
    T.assert_equal(vm.liveness.time_in_step_s, 42, "time in step is now - wait_started_at")
    T.assert_equal(vm.liveness.session_elapsed_s, 142, "session elapsed is now - started_at")
end

function M.test_liveness_uses_last_progress_marker()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(10) }),
        now = 500, started_at = 0, last_progress_at = 470,
    })
    T.assert_equal(vm.liveness.time_since_progress_s, 30,
        "time since progress is now - last_progress_at")
end

-- ============================================================================
-- Progress — step/total, percent, rate and ETA
-- ============================================================================

function M.test_progress_percent_and_eta()
    -- 10 of 100 steps in 1000s -> 100s/step -> 90 remaining -> 9000s ETA.
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", op = 11, operations = ops(100) }),
        now = 1000, started_at = 0,
    })
    T.assert_equal(vm.progress.step, 11, "step is the current operation index")
    T.assert_equal(vm.progress.total, 100, "total is the operation count")
    T.assert_equal(vm.progress.pct, 10, "10 completed of 100 is 10%")
    T.assert_equal(vm.progress.eta_s, 9000, "90 remaining at 100s/step is 9000s")
end

function M.test_progress_eta_is_nil_before_any_step_completes()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", op = 1, operations = ops(100) }),
        now = 50, started_at = 0,
    })
    T.assert_equal(vm.progress.eta_s, nil, "no completed steps yet means no ETA estimate")
end

-- ============================================================================
-- Blocked reason — human text, with the raw condition behind disclosure
-- ============================================================================

function M.test_blocked_exposes_human_reason_and_raw_condition()
    local cond = { type = "ObjectiveComplete", payload = { 1234, 1 } }
    local vm = RunnerState.build({
        executor = fake_executor({
            state = "running", wait_started_at = 10, wait_key = "1:1",
            operations = {
                { id = 1, actions = { { type = "Condition", payload = { condition = cond, role = "Completion" } } } },
            },
        }),
        now = 20, started_at = 0,
    })
    T.assert_equal(vm.blocked.is_blocked, true, "a waiting gate is blocked")
    T.assert_true(vm.blocked.human_reason ~= nil and #vm.blocked.human_reason > 0,
        "blocked state must carry a human-readable reason")
    T.assert_equal(vm.blocked.raw_condition, cond,
        "raw condition is preserved for the details disclosure")
end

function M.test_not_blocked_when_running_normally()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 10, started_at = 0,
    })
    T.assert_equal(vm.blocked.is_blocked, false, "a normally running profile is not blocked")
end

-- ============================================================================
-- Quest-log desync — the silent failure mode
-- ============================================================================

function M.test_sync_ok_when_tracked_quests_are_in_the_log()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 10, started_at = 0,
        tracked_quests = { 100, 200 },
        quest_log = { [100] = true, [200] = true },
    })
    T.assert_equal(vm.sync.tracked, 2, "two tracked quests")
    T.assert_equal(vm.sync.in_log, 2, "both present in the quest log")
    T.assert_equal(vm.sync.ok, true, "no desync")
end

function M.test_sync_flags_missing_quests()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 10, started_at = 0,
        tracked_quests = { 100, 200, 300 },
        quest_log = { [100] = true },
    })
    T.assert_equal(vm.sync.in_log, 1, "only one of three is really in the log")
    T.assert_equal(vm.sync.ok, false, "a mismatch must be flagged, not hidden")
    T.assert_equal(#vm.sync.missing, 2, "the missing quest ids are listed for triage")
end

-- ============================================================================
-- Guardrails — unattended safety
-- ============================================================================

function M.test_guardrail_trips_on_death_limit()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 10, started_at = 0,
        deaths = 3,
        guardrails = { stop_after_deaths = 3 },
    })
    T.assert_equal(vm.guardrails.tripped, true, "reaching the death limit trips the guardrail")
    T.assert_true(vm.guardrails.reason ~= nil, "a tripped guardrail must say why")
end

function M.test_guardrail_not_tripped_below_limit()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 10, started_at = 0,
        deaths = 1,
        guardrails = { stop_after_deaths = 3 },
    })
    T.assert_equal(vm.guardrails.tripped, false, "below the limit the guardrail is armed, not tripped")
end

function M.test_guardrail_trips_on_stuck_duration()
    local vm = RunnerState.build({
        executor = fake_executor({
            state = "running", wait_started_at = 0, wait_key = "1:1", operations = ops(5),
        }),
        now = 400, started_at = 0,
        guardrails = { stop_if_stuck_s = 300 },
    })
    T.assert_equal(vm.guardrails.tripped, true, "being stuck past the limit trips the guardrail")
end

-- ============================================================================
-- Events — newest-first, severity-tagged, capped for triage
-- ============================================================================

function M.test_events_are_newest_first_and_capped()
    local log = {}
    for i = 1, 50 do
        log[i] = { event = "action_success", timestamp = i, operation = i }
    end
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", log = log, operations = ops(5) }),
        now = 100, started_at = 0, max_events = 10,
    })
    T.assert_equal(#vm.events, 10, "event list is capped for readability")
    T.assert_equal(vm.events[1].t, 50, "newest event comes first")
end

function M.test_events_carry_severity()
    local vm = RunnerState.build({
        executor = fake_executor({
            state = "running", operations = ops(5),
            log = {
                { event = "action_success", timestamp = 1 },
                { event = "action_retry", timestamp = 2 },
                { event = "action_failed", timestamp = 3 },
            },
        }),
        now = 10, started_at = 0,
    })
    local by_sev = {}
    for _, e in ipairs(vm.events) do by_sev[e.sev] = (by_sev[e.sev] or 0) + 1 end
    T.assert_equal(by_sev.error, 1, "failures are errors")
    T.assert_equal(by_sev.warn, 1, "retries are warnings")
    T.assert_equal(by_sev.info, 1, "successes are info")
end

-- ============================================================================
-- Event severity table integrity (E6) — every key must have a real emitter.
-- Encodes the exhaustive set of event names actually passed to
-- RuntimeProfile:_log_event(...) (modules/questing/runtime_profile.lua) so a severity
-- entry can never again go dead (e.g. the removed `operation_advance`, which no
-- `_log_event` call ever emitted) without this test failing.
-- ============================================================================

local REAL_LOG_EVENTS = {
    save_restored = true,
    load_with_save = true,
    load_fresh = true,
    hot_reload_skip = true,
    hot_reload = true,
    death_detected = true,
    operation_already_done = true,
    action_success = true,
    action_skipped = true,
    condition_wait_timeout = true,
    action_retry = true,
    action_retry_exhausted = true,
    action_blocked = true,
    action_failed = true,
    profile_failed = true,
    nav_arrived = true,
    nav_idle_unconfirmed = true,
    nav_timeout = true,
    nav_stuck = true,
    nav_failed = true,
    ghost_rezzed = true,
    ghost_timeout = true,
    ghost_release_spirit = true,
    ghost_resurrect_attempt = true,
    nav_already_active = true,
    nav_dispatch_failed = true,
    nav_started = true,
}

function M.test_every_event_severity_key_has_a_real_emitter()
    for event_name in pairs(RunnerState.EVENT_SEVERITY) do
        T.assert_true(REAL_LOG_EVENTS[event_name] ~= nil,
            "EVENT_SEVERITY['" .. tostring(event_name) ..
            "'] has no matching RuntimeProfile:_log_event(...) call site -- dead entry")
    end
end

local tests = {
    test_idle_when_no_executor = M.test_idle_when_no_executor,
    test_running_is_not_an_alarm = M.test_running_is_not_an_alarm,
    test_failed_state_is_an_alarm = M.test_failed_state_is_an_alarm,
    test_long_wait_is_promoted_to_stuck = M.test_long_wait_is_promoted_to_stuck,
    test_short_wait_is_not_stuck = M.test_short_wait_is_not_stuck,
    test_liveness_reports_wait_duration = M.test_liveness_reports_wait_duration,
    test_liveness_uses_last_progress_marker = M.test_liveness_uses_last_progress_marker,
    test_progress_percent_and_eta = M.test_progress_percent_and_eta,
    test_progress_eta_is_nil_before_any_step_completes = M.test_progress_eta_is_nil_before_any_step_completes,
    test_blocked_exposes_human_reason_and_raw_condition = M.test_blocked_exposes_human_reason_and_raw_condition,
    test_not_blocked_when_running_normally = M.test_not_blocked_when_running_normally,
    test_sync_ok_when_tracked_quests_are_in_the_log = M.test_sync_ok_when_tracked_quests_are_in_the_log,
    test_sync_flags_missing_quests = M.test_sync_flags_missing_quests,
    test_guardrail_trips_on_death_limit = M.test_guardrail_trips_on_death_limit,
    test_guardrail_not_tripped_below_limit = M.test_guardrail_not_tripped_below_limit,
    test_guardrail_trips_on_stuck_duration = M.test_guardrail_trips_on_stuck_duration,
    test_events_are_newest_first_and_capped = M.test_events_are_newest_first_and_capped,
    test_events_carry_severity = M.test_events_carry_severity,
    test_every_event_severity_key_has_a_real_emitter = M.test_every_event_severity_key_has_a_real_emitter,
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
            error(name .. ": " .. tostring(err), 0)
        end
    end
end

M.tests = tests
return M
