-- tests/modules/questing/test_module_control.lua
-- Control-surface tests for the questing module: the verbs the runner cockpit drives.
-- These target control semantics (pause/resume/stop/skip/guardrails/profile discovery), not file
-- IO — the executor is injected so a mis-wired control verb cannot hide behind a load failure.

local RuntimeProfile = require("modules/questing/runtime_profile")
local QuestingModule = require("modules/questing/module")
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

local function fake_executor(o)
    o = o or {}
    local ex = {
        _state = o.state or "running",
        _current_operation_idx = o.op or 1,
        _current_action_idx = 1,
        _current_action_retries = 0,
        _consecutive_failures = 0,
        _execution_log = {},
        _profile = { operations = o.operations or { { id = 1, actions = {} }, { id = 2, actions = {} } } },
        _json_path = o.path or "p.json",
        executed = 0,
    }
    function ex:execute()
        self.executed = self.executed + 1
        return "running", "ok"
    end
    return ex
end

local function new_module()
    local m = QuestingModule:new(Blackboard:new(), EventBus:new())
    m._executor = fake_executor()
    m._enabled = true
    return m
end

-- ============================================================================
-- pause / resume must preserve progress — the whole point of pause vs stop
-- ============================================================================

function M.test_pause_halts_execution_but_keeps_the_executor()
    local m = new_module()
    m:pause()
    m:tick(0.1)
    T.assert_equal(m._executor.executed, 0, "a paused module must not execute actions")
    T.assert_true(m._executor ~= nil, "pause must keep the executor so progress is not lost")
    T.assert_equal(m:is_paused(), true, "pause sets the paused flag")
end

function M.test_resume_continues_from_the_same_executor()
    local m = new_module()
    m._executor._current_operation_idx = 7
    m:pause()
    m:resume()
    m:tick(0.1)
    T.assert_equal(m:is_paused(), false, "resume clears the paused flag")
    T.assert_equal(m._executor.executed, 1, "a resumed module executes again")
    T.assert_equal(m._executor._current_operation_idx, 7,
        "resume must not reset progress")
end

function M.test_stop_clears_the_executor()
    local m = new_module()
    m:stop()
    m:tick(0.1)
    T.assert_equal(m._executor, nil, "stop releases the executor")
    T.assert_equal(m:is_enabled(), false, "stop disables the module")
end

-- ============================================================================
-- skip step — the primary manual recovery lever
-- ============================================================================

function M.test_skip_current_step_advances_the_operation()
    local m = new_module()
    m._executor._current_operation_idx = 1
    m._executor._current_action_idx = 3
    local ok = m:skip_current_step()
    T.assert_equal(ok, true, "skip succeeds when an executor is loaded")
    T.assert_equal(m._executor._current_operation_idx, 2, "skip advances to the next operation")
    T.assert_equal(m._executor._current_action_idx, 1, "skip resets the action index")
end

function M.test_skip_without_executor_is_a_safe_noop()
    local m = QuestingModule:new(Blackboard:new(), EventBus:new())
    T.assert_equal(m:skip_current_step(), false, "skip with nothing loaded must not error")
end

-- ============================================================================
-- Terminal-failure recovery — `failed` used to have no exit.
--
-- MEASURED before the fix: `RuntimeProfile:_check_consecutive_failures` sets
-- `_state = "failed"` at MAX_CONSECUTIVE_FAILURES (3), and `execute()` then returns
-- "error" on every later tick. `skip_current_step` reset the operation index, action index,
-- retry counter and wait timers but NOT `_state` and NOT `_consecutive_failures` — so the
-- cockpit's own recovery verb could not rescue a failed run; only stop() + start() could.
-- For an unattended bot, three consecutive failing actions ended the session permanently
-- while `tick` kept re-calling an executor that could only answer "error".
-- ============================================================================

--- A REAL RuntimeProfile whose first three operations cannot execute (an unknown action type
--- resolves to "failed" every tick), followed by executable Comment operations so recovery has
--- somewhere to land. Deliberately NOT dry_run: dry-run mode short-circuits into
--- `_execute_dry_run` and never reaches the failure state machine under test.
local function executor_that_fails_three_times()
    local executor = RuntimeProfile:new("test_failed.json")
    local function failing_op(id)
        return { id = id, actions = { { type = "NonExistentType", payload = {} } }, next_condition = "auto" }
    end
    local function comment_op(id, text)
        return { id = id, actions = { { type = "Comment", payload = { text = text } } }, next_condition = "auto" }
    end
    executor._profile = {
        content_hash = "test",
        operations = {
            failing_op(1), failing_op(2), failing_op(3),
            comment_op(4, "recovered"), comment_op(5, "still going"),
        },
    }
    return executor
end

--- Tick the module until its executor reaches the terminal `failed` state (bounded, so a
--- regression that never fails reports as an assertion rather than hanging the suite).
local function drive_until_failed(m)
    for _ = 1, 20 do
        if m._executor._state == "failed" then return end
        m:tick(0.1)
    end
end

function M.test_three_consecutive_failures_end_the_run()
    local m = QuestingModule:new(Blackboard:new(), EventBus:new())
    m._executor = executor_that_fails_three_times()
    m._enabled = true
    drive_until_failed(m)

    T.assert_equal(m._executor._state, "failed",
        "three consecutive action failures must drive the executor into `failed`")
    T.assert_true(m._executor._consecutive_failures >= 3,
        "the consecutive-failure tally is what tripped the terminal state")
    T.assert_equal(select(1, m._executor:execute()), "error",
        "`failed` is terminal -- every later execute() answers error, so the run is over")
end

function M.test_tick_pauses_the_run_on_executor_error_instead_of_spinning()
    local bus = EventBus:new()
    local published = {}
    bus:subscribe("questing:failed", function(payload) published[#published + 1] = payload end)
    local m = QuestingModule:new(Blackboard:new(), bus)
    m._executor = executor_that_fails_three_times()
    m._enabled = true
    drive_until_failed(m)
    m:tick(0.1) -- the first tick that observes status == "error"

    T.assert_equal(m:is_paused(), true,
        "an errored executor must park the run, not be re-executed every tick forever")
    T.assert_equal(#published, 1,
        "the cockpit learns about the terminal failure through exactly one questing:failed event")
end

function M.test_skip_current_step_recovers_a_failed_run()
    local m = QuestingModule:new(Blackboard:new(), EventBus:new())
    m._executor = executor_that_fails_three_times()
    m._enabled = true
    drive_until_failed(m)
    T.assert_equal(m._executor._state, "failed", "precondition: the run really is failed")

    T.assert_equal(m:skip_current_step(), true, "skip succeeds on a failed run")
    T.assert_equal(m._executor._state, "running",
        "skip must clear the terminal state -- otherwise the only exit is stop() + start()")
    T.assert_equal(m._executor._consecutive_failures, 0,
        "a stale failure tally would re-trip `failed` on the very next single failure")
    T.assert_true(select(1, m._executor:execute()) ~= "error",
        "after recovery the executor executes again rather than answering error")
end

-- ============================================================================
-- guardrails — unattended safety, the reason this is production-shaped
-- ============================================================================

function M.test_guardrail_trip_auto_pauses_the_run()
    local m = new_module()
    m:set_guardrails({ stop_after_deaths = 2 })
    m._deaths = 2
    m:tick(0.1)
    T.assert_equal(m:is_paused(), true,
        "a tripped guardrail must halt the run rather than keep going unattended")
    T.assert_equal(m._executor.executed, 0, "no action executes on the tripping tick")
end

function M.test_guardrail_below_limit_keeps_running()
    local m = new_module()
    m:set_guardrails({ stop_after_deaths = 3 })
    m._deaths = 1
    m:tick(0.1)
    T.assert_equal(m:is_paused(), false, "below the limit the run continues")
    T.assert_equal(m._executor.executed, 1, "execution proceeds normally")
end

-- ============================================================================
-- profile discovery — core.read_dir backs the picker (no hardcoded list)
-- ============================================================================

function M.test_list_profiles_returns_json_stems_only()
    local saved = core.read_dir
    core.read_dir = function(_dir)
        return { "elwynn.json", "notes.txt", "durotar.json", "subfolder" }
    end
    local m = new_module()
    local list = m:list_profiles("SentinelCore/questing")
    core.read_dir = saved

    T.assert_equal(#list, 2, "only .json files are offered as profiles")
    T.assert_equal(list[1], "durotar", "entries are sorted and extension-stripped")
    T.assert_equal(list[2], "elwynn", "entries are sorted and extension-stripped")
end

function M.test_list_profiles_handles_missing_directory()
    local saved = core.read_dir
    core.read_dir = function(_dir) return nil end
    local m = new_module()
    local list = m:list_profiles("nope")
    core.read_dir = saved
    T.assert_equal(#list, 0, "a missing directory yields an empty list, never an error")
end

-- ============================================================================
-- view-model wiring — the cockpit reads one snapshot
-- ============================================================================

function M.test_get_view_returns_a_cockpit_snapshot()
    local m = new_module()
    local vm = m:get_view()
    T.assert_true(vm ~= nil, "get_view returns a snapshot")
    T.assert_true(vm.health ~= nil, "snapshot carries health")
    T.assert_true(vm.progress ~= nil, "snapshot carries progress")
    T.assert_equal(vm.progress.total, 2, "progress reflects the loaded profile")
end

function M.test_get_view_without_executor_reads_idle()
    local m = QuestingModule:new(Blackboard:new(), EventBus:new())
    local vm = m:get_view()
    T.assert_equal(vm.health.status, "IDLE", "nothing loaded reads IDLE")
end

-- ============================================================================
-- Quest-log desync wiring (C5) — module.questing.tracked_quests / module.questing.quest_log were read
-- everywhere and written nowhere, so the cockpit's "is it lying to me?" panel always read
-- ok=true. These use a REAL RuntimeProfile (not the tick-only fake_executor above) so the
-- desync is computed from the exact same profile-replay and quest-log-refresh logic the
-- production module runs, mocking only the Sylvannas core.quests boundary.
-- ============================================================================

--- Install a quest log shaped like the live client's (see test_quest_objectives.lua).
local function mock_quest_log(entries)
    _G.core = _G.core or {}
    _G.core.quests = _G.core.quests or {}
    _G.core.quests.get_num_quest_log_entries = function() return #entries end
    _G.core.quests.get_quest_log_title = function(i) return entries[i] end
end

--- A RuntimeProfile whose compiled operations accept quest 33 in operation 1, so a module
--- that has progressed to operation 2 believes quest 33 is currently tracked.
local function executor_that_accepted_quest_33()
    local executor = RuntimeProfile:new("test.json", true) -- dry_run, no disk IO
    executor._profile = {
        content_hash = "test",
        operations = {
            { id = 1, actions = { { type = "AcceptQuest", payload = { quest_id = 33 } } } },
            { id = 2, actions = { { type = "Travel", payload = { destination = "somewhere" } } } },
        },
    }
    executor._current_operation_idx = 2 -- operation 1 (the accept) is already behind us
    return executor
end

function M.test_quest_sync_flags_a_real_tracked_vs_log_mismatch()
    mock_quest_log({
        { quest_id = 0, title = "Zone Header", is_header = true },
        { quest_id = 7, title = "Some Other Quest", is_header = false, is_complete = false },
    })
    local m = QuestingModule:new(Blackboard:new(), EventBus:new())
    m._executor = executor_that_accepted_quest_33()
    m:_refresh_quest_sync()
    local vm = m:get_view()

    T.assert_equal(vm.sync.tracked, 1, "the profile believes it accepted one quest")
    T.assert_equal(vm.sync.ok, false, "quest 33 is not in the real quest log -- this must be flagged")
    T.assert_equal(#vm.sync.missing, 1, "exactly one quest id is missing")
    T.assert_equal(vm.sync.missing[1], "33", "the missing quest id is the one the profile accepted")
end

function M.test_quest_sync_reads_ok_when_tracked_quest_is_really_in_the_log()
    mock_quest_log({
        { quest_id = 0, title = "Zone Header", is_header = true },
        { quest_id = 33, title = "Wolves Across the Border", is_header = false, is_complete = false },
    })
    local m = QuestingModule:new(Blackboard:new(), EventBus:new())
    m._executor = executor_that_accepted_quest_33()
    m:_refresh_quest_sync()
    local vm = m:get_view()

    T.assert_equal(vm.sync.ok, true, "quest 33 really is in the log -- no desync")
    T.assert_equal(vm.sync.in_log, 1, "the one tracked quest is present in the log")
end

function M.test_quest_sync_defaults_are_written_not_left_as_default_ok()
    -- Before C5, nothing wrote these keys and the panel silently defaulted to ok=true even
    -- with an active profile. Confirm the blackboard keys are actually populated.
    mock_quest_log({})
    local bb = Blackboard:new()
    local m = QuestingModule:new(bb, EventBus:new())
    m._executor = executor_that_accepted_quest_33()
    m:_refresh_quest_sync()

    local tracked = bb:get("module.questing.tracked_quests", nil)
    T.assert_true(tracked ~= nil, "module.questing.tracked_quests must be written by the module")
    T.assert_equal(#tracked, 1, "one accepted quest is tracked")

    local qlog = bb:get("module.questing.quest_log", nil)
    T.assert_true(qlog ~= nil, "module.questing.quest_log must be written by the module")
end

function M.test_quest_sync_refresh_is_throttled()
    local m = new_module()
    local calls = 0
    m._refresh_quest_sync = function() calls = calls + 1 end
    local now = 1000
    local saved_time = core.time
    core.time = function() return now end

    m:tick(0.1)
    m:tick(0.1) -- same instant: the full quest-log scan must not run again
    local immediate = calls
    now = 1006 -- past the 5s throttle window
    m:tick(0.1)
    local after_window = calls

    core.time = saved_time
    T.assert_equal(immediate, 1, "two immediate ticks must scan the quest log only once")
    T.assert_equal(after_window, 2, "the scan must resume once the throttle window passes")
end

-- ============================================================================
-- View caching — one build per tick timestamp, invalidated by control verbs
-- ============================================================================

function M.test_get_view_is_cached_within_one_tick()
    local now = 1000
    local saved_time = core.time
    core.time = function() return now end
    local m = new_module()

    local v1 = m:get_view()
    local v2 = m:get_view()
    T.assert_true(rawequal(v1, v2), "two get_view calls at the same tick share one snapshot")
    now = 1001
    local v3 = m:get_view()
    T.assert_true(not rawequal(v1, v3), "advancing the clock invalidates the cached view")

    core.time = saved_time
end

function M.test_control_verbs_invalidate_the_view_cache()
    local now = 1000
    local saved_time = core.time
    core.time = function() return now end
    local m = new_module()

    local v1 = m:get_view()
    m:pause()
    local v2 = m:get_view()
    T.assert_true(not rawequal(v1, v2), "a control verb must rebuild the view within the tick")

    core.time = saved_time
end

-- ============================================================================
-- Pause clock — paused time must not inflate the session clock or trip stall
-- ============================================================================

function M.test_pause_freezes_the_session_clock()
    local now = 0
    local saved_time = core.time
    core.time = function() return now end
    local m = new_module()
    m._started_at = 0

    now = 50
    m:pause()
    now = 150
    m:resume()
    now = 160
    local vm = m:get_view()
    T.assert_equal(vm.liveness.session_elapsed_s, 60,
        "a 100s pause must not count into session elapsed")

    core.time = saved_time
end

function M.test_resume_shifts_the_wait_clock_past_the_pause()
    local now = 0
    local saved_time = core.time
    core.time = function() return now end
    local m = new_module()
    m._executor._wait_started_at = 40
    m._executor._wait_action_key = "1:1"

    now = 50
    m:pause()
    now = 150
    m:resume()
    T.assert_equal(m._executor._wait_started_at, 140,
        "the wait clock shifts by the pause duration so stall cannot false-trip")

    core.time = saved_time
end

-- ============================================================================
-- Status routing — the executor's message reaches the view, not a dead key
-- ============================================================================

function M.test_status_message_routes_to_view_not_blackboard()
    local bb = Blackboard:new()
    local m = QuestingModule:new(bb, EventBus:new())
    m._executor = fake_executor()
    m._enabled = true
    m:tick(0.1)
    T.assert_equal(bb:get("module.questing.status", nil), nil,
        "the dead module.questing.status blackboard write must be gone")
    T.assert_equal(bb:get("module.questing.message", nil), nil,
        "the dead module.questing.message blackboard write must be gone")
    local vm = m:get_view()
    T.assert_equal(vm.health.message, "ok", "the executor's message reaches the view directly")
end

function M.test_nav_error_reaches_the_view()
    local now = 1000
    local saved_time = core.time
    core.time = function() return now end
    local m = new_module()
    m._executor._nav = {
        get_last_error = function()
            return { command = "move_to", reason = "unreachable", at = 1000,
                     target = { x = 1, y = 2, z = 3 } }
        end,
    }
    local vm = m:get_view()
    T.assert_equal(vm.blocked.kind, "nav", "the executor's nav error reaches the blocked union")

    core.time = saved_time
end

-- ============================================================================
-- Completion ring — recent step completions feed the windowed ETA
-- ============================================================================

function M.test_completion_ring_records_and_caps()
    local now = 0
    local saved_time = core.time
    core.time = function() return now end
    local m = new_module()
    for i = 1, 12 do
        now = i * 10
        m._executor._current_operation_idx = i + 1
        m:tick(0.1)
    end
    T.assert_equal(#m._recent_completions, 10, "the completion ring holds at most 10 samples")
    T.assert_equal(m._recent_completions[10], 120, "the newest completion time is kept")
    T.assert_equal(m._recent_completions[1], 30, "the oldest samples are evicted first")

    core.time = saved_time
end

-- ============================================================================
-- Profile chaining — 1-70 continuity. A finished profile must load its RestedXP
-- #next successor for the character's class instead of just stopping the run.
-- ============================================================================

--- A fake executor that reports "finished" and knows its class + path.
local function finished_executor(path, class_name)
    local ex = fake_executor({ path = path })
    ex.execute = function(self)
        self.executed = self.executed + 1
        return "finished", "done"
    end
    ex.create_context = function()
        return { get_player_class = function() return class_name end }
    end
    return ex
end

function M.test_finished_profile_advances_to_next_in_chain()
    local m = new_module()
    m._executor = finished_executor("sentinel/data/profiles/quests/1-11-Elwynn-Forest.json", "Paladin")
    -- Inject the manifest (bypasses chain.json file IO) and the on-disk profile set.
    m._chain = {
        entries = {
            ["1-11-Elwynn-Forest"] = { next = { { slug = "11-12-Loch-Modan", class_not = "Warlock" } } },
            ["11-12-Loch-Modan"] = { next = {} },
        },
    }
    m.list_profiles = function() return { "1-11-Elwynn-Forest", "11-12-Loch-Modan" } end
    local started = {}
    m.start = function(_, path) started[#started + 1] = path; return true end

    m:tick(0.1)
    T.assert_equal(#started, 1, "a finished profile must start its chain successor")
    T.assert_true(started[1]:match("11%-12%-Loch%-Modan%.json$") ~= nil,
        "must start the resolved next slug, got: " .. tostring(started[1]))
    T.assert_equal(m:is_enabled(), true, "advancing the chain keeps the module enabled")
end

function M.test_finished_at_chain_end_finalizes_the_run()
    local m = new_module()
    m._executor = finished_executor("sentinel/data/profiles/quests/69-70-Shadowmoon.json", "Paladin")
    m._chain = { entries = { ["69-70-Shadowmoon"] = { next = {} } } }
    m.list_profiles = function() return { "69-70-Shadowmoon" } end
    local started = {}
    m.start = function(_, path) started[#started + 1] = path; return true end

    m:tick(0.1)
    T.assert_equal(#started, 0, "the end of the chain must not start another profile")
    T.assert_equal(m:is_enabled(), false, "the end of the chain finalizes the run (disables)")
end

function M.test_finished_with_uncompiled_successor_finalizes()
    -- The manifest names a successor, but no compiled profile exists for it: the run must
    -- finalize rather than try to start a missing file.
    local m = new_module()
    m._executor = finished_executor("sentinel/data/profiles/quests/A.json", "Paladin")
    m._chain = { entries = { ["A"] = { next = { { slug = "B" } } }, ["B"] = { next = {} } } }
    m.list_profiles = function() return { "A" } end
    local started = {}
    m.start = function(_, path) started[#started + 1] = path; return true end

    m:tick(0.1)
    T.assert_equal(#started, 0, "a successor with no compiled file must not be started")
    T.assert_equal(m:is_enabled(), false, "an uncompiled successor finalizes the run")
end

-- ============================================================================
-- Vendor-maintenance known-vendor fallback — bags fill at remote grind spots
-- where no vendor is visible; the detour must navigate to a known route vendor.
-- ============================================================================

function M.test_find_known_vendor_picks_nearest_by_route()
    local m = new_module()
    local ops = {}
    for i = 1, 25 do ops[i] = { id = i, actions = {} } end
    ops[5].actions = { { type = "Vendor", payload = { npc_entry = 100 } } }
    ops[20].actions = { { type = "Vendor", payload = { npc_entry = 200 } } }
    m._executor._profile = { operations = ops }
    m._executor._current_operation_idx = 18

    T.assert_equal(m:_find_known_vendor(), 200,
        "the vendor whose op is nearest the current route position (op 20) must win over op 5")
end

function M.test_find_known_vendor_nil_without_any_vendor_action()
    local m = new_module()
    m._executor._profile = { operations = {
        { id = 1, actions = { { type = "Kill", payload = { creature_entries = { 5 } } } } },
    } }
    m._executor._current_operation_idx = 1
    T.assert_equal(m:_find_known_vendor(), nil, "no Vendor action anywhere must yield nil")
end

local tests = {
    test_find_known_vendor_picks_nearest_by_route = M.test_find_known_vendor_picks_nearest_by_route,
    test_find_known_vendor_nil_without_any_vendor_action = M.test_find_known_vendor_nil_without_any_vendor_action,
    test_finished_profile_advances_to_next_in_chain = M.test_finished_profile_advances_to_next_in_chain,
    test_finished_at_chain_end_finalizes_the_run = M.test_finished_at_chain_end_finalizes_the_run,
    test_finished_with_uncompiled_successor_finalizes = M.test_finished_with_uncompiled_successor_finalizes,
    test_quest_sync_refresh_is_throttled = M.test_quest_sync_refresh_is_throttled,
    test_get_view_is_cached_within_one_tick = M.test_get_view_is_cached_within_one_tick,
    test_control_verbs_invalidate_the_view_cache = M.test_control_verbs_invalidate_the_view_cache,
    test_pause_freezes_the_session_clock = M.test_pause_freezes_the_session_clock,
    test_resume_shifts_the_wait_clock_past_the_pause = M.test_resume_shifts_the_wait_clock_past_the_pause,
    test_status_message_routes_to_view_not_blackboard = M.test_status_message_routes_to_view_not_blackboard,
    test_nav_error_reaches_the_view = M.test_nav_error_reaches_the_view,
    test_completion_ring_records_and_caps = M.test_completion_ring_records_and_caps,
    test_pause_halts_execution_but_keeps_the_executor = M.test_pause_halts_execution_but_keeps_the_executor,
    test_resume_continues_from_the_same_executor = M.test_resume_continues_from_the_same_executor,
    test_stop_clears_the_executor = M.test_stop_clears_the_executor,
    test_skip_current_step_advances_the_operation = M.test_skip_current_step_advances_the_operation,
    test_skip_without_executor_is_a_safe_noop = M.test_skip_without_executor_is_a_safe_noop,
    test_three_consecutive_failures_end_the_run = M.test_three_consecutive_failures_end_the_run,
    test_tick_pauses_the_run_on_executor_error_instead_of_spinning = M.test_tick_pauses_the_run_on_executor_error_instead_of_spinning,
    test_skip_current_step_recovers_a_failed_run = M.test_skip_current_step_recovers_a_failed_run,
    test_guardrail_trip_auto_pauses_the_run = M.test_guardrail_trip_auto_pauses_the_run,
    test_guardrail_below_limit_keeps_running = M.test_guardrail_below_limit_keeps_running,
    test_list_profiles_returns_json_stems_only = M.test_list_profiles_returns_json_stems_only,
    test_list_profiles_handles_missing_directory = M.test_list_profiles_handles_missing_directory,
    test_get_view_returns_a_cockpit_snapshot = M.test_get_view_returns_a_cockpit_snapshot,
    test_get_view_without_executor_reads_idle = M.test_get_view_without_executor_reads_idle,
    test_quest_sync_flags_a_real_tracked_vs_log_mismatch = M.test_quest_sync_flags_a_real_tracked_vs_log_mismatch,
    test_quest_sync_reads_ok_when_tracked_quest_is_really_in_the_log = M.test_quest_sync_reads_ok_when_tracked_quest_is_really_in_the_log,
    test_quest_sync_defaults_are_written_not_left_as_default_ok = M.test_quest_sync_defaults_are_written_not_left_as_default_ok,
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
