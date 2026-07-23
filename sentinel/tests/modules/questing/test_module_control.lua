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
-- Quest-log desync wiring (C5) — questing.tracked_quests / questing.quest_log were read
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

    local tracked = bb:get("questing.tracked_quests", nil)
    T.assert_true(tracked ~= nil, "questing.tracked_quests must be written by the module")
    T.assert_equal(#tracked, 1, "one accepted quest is tracked")

    local qlog = bb:get("questing.quest_log", nil)
    T.assert_true(qlog ~= nil, "questing.quest_log must be written by the module")
end

local tests = {
    test_pause_halts_execution_but_keeps_the_executor = M.test_pause_halts_execution_but_keeps_the_executor,
    test_resume_continues_from_the_same_executor = M.test_resume_continues_from_the_same_executor,
    test_stop_clears_the_executor = M.test_stop_clears_the_executor,
    test_skip_current_step_advances_the_operation = M.test_skip_current_step_advances_the_operation,
    test_skip_without_executor_is_a_safe_noop = M.test_skip_without_executor_is_a_safe_noop,
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
