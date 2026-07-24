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
-- Blocked-reason union — nav / failed / ghost / gate all answer "why is it stopped?"
-- ============================================================================

function M.test_nav_error_populates_blocked_nav()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 100, started_at = 0,
        nav_error = { command = "move_to", reason = "unreachable", at = 95,
                      target = { x = 1, y = 2, z = 3 } },
    })
    T.assert_equal(vm.blocked.is_blocked, true, "a recent nav failure blocks the run")
    T.assert_equal(vm.blocked.kind, "nav", "nav failure reads kind=nav")
    T.assert_true(vm.blocked.human_reason:find("unreachable", 1, true) ~= nil,
        "the nav reason string must survive into the human reason")
    T.assert_equal(vm.blocked.detail.target.x, 1, "target coords are preserved for triage")
    T.assert_equal(vm.health.severity, "alarm", "a nav terminal failure is an alarm")
end

function M.test_stale_nav_error_does_not_block()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 500, started_at = 0,
        nav_error = { command = "move_to", reason = "unreachable", at = 10, target = {} },
    })
    T.assert_equal(vm.blocked.is_blocked, false, "an old nav error must not block forever")
    T.assert_equal(vm.health.severity, "ok", "a recovered run reads ok again")
end

function M.test_failed_state_populates_blocked_failed()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "failed", failures = 4, operations = ops(5) }),
        now = 100, started_at = 0,
    })
    T.assert_equal(vm.blocked.kind, "failed", "executor failure reads kind=failed")
    T.assert_true(#vm.blocked.human_reason > 0, "failed must carry a human reason")
    T.assert_equal(vm.blocked.detail.consecutive_failures, 4,
        "consecutive-failure context is preserved")
end

function M.test_ghost_state_populates_blocked_ghost_and_recovery()
    local ex = fake_executor({ state = "ghost", operations = ops(5) })
    ex._ghost_start_time = 40
    local vm = RunnerState.build({ executor = ex, now = 100, started_at = 0 })
    T.assert_equal(vm.blocked.kind, "ghost", "ghost state reads kind=ghost")
    T.assert_equal(vm.recovery.ghost_elapsed, 60, "ghost recovery elapsed is now - ghost start")
    T.assert_equal(vm.health.severity, "alarm", "ghost is an alarm state")
end

function M.test_gate_blocked_carries_kind_gate()
    local cond = { type = "QuestAccepted", payload = 33 }
    local vm = RunnerState.build({
        executor = fake_executor({
            state = "running", wait_started_at = 10, wait_key = "1:1",
            operations = {
                { id = 1, actions = { { type = "Condition", payload = { condition = cond, role = "Completion" } } } },
            },
        }),
        now = 20, started_at = 0,
    })
    T.assert_equal(vm.blocked.kind, "gate", "a completion gate reads kind=gate")
    T.assert_equal(vm.blocked.waited_s, 10, "gate keeps the waited duration")
    T.assert_equal(vm.blocked.raw_condition, cond, "gate keeps the raw condition")
end

-- ============================================================================
-- Health severity — the render layer switches on this and nothing else
-- ============================================================================

function M.test_severity_per_state()
    local function sev(o, extra)
        local opts = {
            executor = fake_executor(o), now = extra and extra.now or 100,
            started_at = 0, stall_threshold_s = 300,
        }
        for k, v in pairs(extra or {}) do opts[k] = v end
        return RunnerState.build(opts).health.severity
    end
    T.assert_equal(sev({ state = "running", operations = ops(5) }), "ok", "RUNNING is ok")
    T.assert_equal(sev({ state = "navigating", operations = ops(5) }), "warn", "NAVIGATING is warn")
    T.assert_equal(sev({ state = "running", wait_started_at = 95, wait_key = "1:1",
        operations = ops(5) }), "warn", "WAITING is warn")
    T.assert_equal(sev({ state = "running", wait_started_at = 95, wait_key = "1:1",
        operations = ops(5) }, { now = 500 }), "alarm", "STUCK is alarm")
    T.assert_equal(sev({ state = "failed", operations = ops(5) }), "alarm", "FAILED is alarm")
    T.assert_equal(sev({ state = "ghost", operations = ops(5) }), "alarm", "GHOST is alarm")
end

function M.test_module_fault_surfaces_and_alarms()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 100, started_at = 0,
        module_faults = { questing = { count = 5, last_error = "boom" } },
    })
    T.assert_equal(vm.health.module_fault.name, "questing", "the faulting module is named")
    T.assert_equal(vm.health.module_fault.count, 5, "the fault count is surfaced")
    T.assert_equal(vm.health.severity, "alarm", "a module fault is an alarm")
end

function M.test_status_message_passthrough()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 100, started_at = 0,
        status_message = "nav timeout, retry",
    })
    T.assert_equal(vm.health.message, "nav timeout, retry",
        "the executor's last status message reaches the view")
end

-- ============================================================================
-- Maintenance visibility — a vendor detour must not look like a hang
-- ============================================================================

function M.test_maintenance_visible_and_warn()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 100, started_at = 0,
        maintenance = { state = "vendoring", vendor_entry = 42, started_at = 90 },
    })
    T.assert_equal(vm.maintenance.active, true, "an active detour is visible")
    T.assert_equal(vm.maintenance.phase, "vendoring", "the detour phase is surfaced")
    T.assert_equal(vm.maintenance.vendor_entry, 42, "the vendor entry is surfaced")
    T.assert_equal(vm.health.severity, "warn", "maintenance reads warn, not alarm")
end

function M.test_maintenance_idle_is_inactive()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", operations = ops(5) }),
        now = 100, started_at = 0,
        maintenance = { state = "idle" },
    })
    T.assert_equal(vm.maintenance.active, false, "idle maintenance is not active")
    T.assert_equal(vm.health.severity, "ok", "idle maintenance does not change severity")
end

-- ============================================================================
-- Pause clock — paused time must not inflate elapsed / ETA
-- ============================================================================

function M.test_paused_time_excluded_from_elapsed_and_eta()
    -- 10 of 100 steps; 1000s wall but 400s paused -> 600s effective -> 60s/step -> ETA 5400.
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", op = 11, operations = ops(100) }),
        now = 1000, started_at = 0, paused_s = 400,
    })
    T.assert_equal(vm.liveness.session_elapsed_s, 600, "paused time is excluded from elapsed")
    T.assert_equal(vm.progress.eta_s, 5400, "ETA uses the effective (unpaused) elapsed")
end

-- ============================================================================
-- Windowed ETA — recent rate beats the whole-session average
-- ============================================================================

function M.test_windowed_eta_uses_recent_rate()
    -- Session average says 100s/step, but the last 10 completions ran at 10s/step.
    local completions = {}
    for i = 1, 10 do completions[i] = 900 + i * 10 end  -- 910..1000
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", op = 11, operations = ops(100) }),
        now = 1000, started_at = 0,
        recent_completions = completions,
    })
    T.assert_equal(vm.progress.eta_s, 900, "ETA reflects the recent 10s/step rate, not 100s/step")
    T.assert_equal(vm.progress.steps_per_hour, 360, "rate comes from the recent window")
end

function M.test_windowed_eta_falls_back_below_three_samples()
    local vm = RunnerState.build({
        executor = fake_executor({ state = "running", op = 11, operations = ops(100) }),
        now = 1000, started_at = 0,
        recent_completions = { 990, 1000 },
    })
    T.assert_equal(vm.progress.eta_s, 9000, "under 3 samples the session average is used")
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
    test_nav_error_populates_blocked_nav = M.test_nav_error_populates_blocked_nav,
    test_stale_nav_error_does_not_block = M.test_stale_nav_error_does_not_block,
    test_failed_state_populates_blocked_failed = M.test_failed_state_populates_blocked_failed,
    test_ghost_state_populates_blocked_ghost_and_recovery = M.test_ghost_state_populates_blocked_ghost_and_recovery,
    test_gate_blocked_carries_kind_gate = M.test_gate_blocked_carries_kind_gate,
    test_severity_per_state = M.test_severity_per_state,
    test_module_fault_surfaces_and_alarms = M.test_module_fault_surfaces_and_alarms,
    test_status_message_passthrough = M.test_status_message_passthrough,
    test_maintenance_visible_and_warn = M.test_maintenance_visible_and_warn,
    test_maintenance_idle_is_inactive = M.test_maintenance_idle_is_inactive,
    test_paused_time_excluded_from_elapsed_and_eta = M.test_paused_time_excluded_from_elapsed_and_eta,
    test_windowed_eta_uses_recent_rate = M.test_windowed_eta_uses_recent_rate,
    test_windowed_eta_falls_back_below_three_samples = M.test_windowed_eta_falls_back_below_three_samples,
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
