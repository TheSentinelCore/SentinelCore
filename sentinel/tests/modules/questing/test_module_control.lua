-- tests/modules/questing/test_module_control.lua
-- Control-surface tests for the questing module: the verbs the runner cockpit drives.
-- These target control semantics (pause/resume/stop/skip/guardrails/profile discovery), not file
-- IO — the executor is injected so a mis-wired control verb cannot hide behind a load failure.

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
}

function M.run()
    for name, fn in pairs(tests) do
        local ok, err = pcall(fn)
        if not ok then
            error(name .. ": " .. tostring(err), 0)
        end
    end
end

M.tests = tests
return M
