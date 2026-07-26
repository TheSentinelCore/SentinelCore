-- tests/modules/questing/test_event_contract.lua
-- ADR 09a §1.5 / ADR 09 §7.2 — the event contract as RuntimeProfile:_log_event actually emits it.
--
-- test_event_schema.lua pins the shape; this pins the wiring. The contract was added to a log
-- that already had three live consumers (runner_state.lua, the save file's execution_history,
-- and the `questing:log` bus topic), so every case here exists to prove the addition stayed
-- additive -- a v1 field appearing is worthless if a pre-v1 field moved.

local RuntimeProfile = require("modules/questing/runtime_profile")
local EventSchema = require("core/event_schema")
local RunnerState = require("modules/questing/runner_state")
local T = require("tests/test_util")

local M = {}

local written_files = {}

local function mock_globals()
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    _G.core.write_data_file = function(path, content)
        written_files[path] = content
        return true
    end
    _G.core.read_data_file = function(path) return written_files[path] end
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

local function make_profile()
    mock_globals()
    local profile = RuntimeProfile:new("test_event_contract.json")
    profile._profile = {
        content_hash = "eventcontracthash",
        operations = {
            { id = 1, actions = { { type = "Comment", payload = { text = "t" } } }, next_condition = "auto" },
        },
    }
    profile._save_path = profile:_compute_save_path()
    return profile
end

-- ============================================================================
-- run_id
-- ============================================================================

function M.test_run_id_is_stable_across_every_event_of_one_run()
    local profile = make_profile()
    for i = 1, 50 do
        profile:_log_event("action_success", { i = i })
    end
    local first = profile._execution_log[1].run_id
    T.assert_equal(type(first), "string", "run_id is minted on the first event")
    T.assert_true(#first > 0, "run_id is non-empty")
    for _, entry in ipairs(profile._execution_log) do
        T.assert_equal(entry.run_id, first, "run_id must not change mid-run")
    end
end

function M.test_run_id_differs_between_runs()
    local a = make_profile()
    a:_log_event("load_fresh", {})
    local b = make_profile()
    b:_log_event("load_fresh", {})
    T.assert_true(a._execution_log[1].run_id ~= b._execution_log[1].run_id,
        "two executors are two runs")
end

function M.test_reset_opens_a_new_run()
    -- reset() zeroes _log_total, so seq restarts at 1. Keeping the old run_id would make
    -- (run_id, seq) ambiguous -- the pair is the only stable key a replay or timeline can join on.
    local profile = make_profile()
    profile:_log_event("action_success", {})
    local before = profile._execution_log[1].run_id
    profile:reset()
    profile:_log_event("action_success", {})
    local after = profile._execution_log[1].run_id
    T.assert_equal(profile._execution_log[1].seq, 1, "seq restarts after reset")
    T.assert_true(after ~= before, "a restarted seq sequence is a new run")
end

-- ============================================================================
-- node_id
-- ============================================================================

function M.test_node_id_is_null_for_profile_scoped_events()
    local profile = make_profile()
    profile:_log_event("load_fresh", {})
    T.assert_nil(profile._execution_log[1].node_id,
        "nothing in the questing executor is graph-scoped yet")
end

-- ============================================================================
-- Pure addition: the pre-v1 consumers
-- ============================================================================

function M.test_pre_v1_fields_are_all_still_present()
    local profile = make_profile()
    profile._current_operation_idx = 4
    profile._state = "navigating"
    profile:_log_event("action_failed", { action_type = "Kill", msg = "target gone" })

    local e = profile._execution_log[1]
    T.assert_equal(e.event, "action_failed", "event")
    T.assert_equal(e.operation, 4, "operation")
    T.assert_equal(e.state, "navigating", "state")
    T.assert_equal(type(e.timestamp), "number", "timestamp")
    T.assert_equal(e.seq, 1, "seq")
    T.assert_equal(e.action_type, "Kill", "flattened payload key")
    T.assert_equal(e.msg, "target gone", "flattened payload key")
end

function M.test_every_emitted_event_validates()
    local profile = make_profile()
    profile:_log_event("nav_started", { destination = { x = 1, y = 2, z = 3 } })
    profile:_log_event("death_detected", { state = profile._state })
    profile:_log_event("operation_already_done", { operation = 9 })
    for _, entry in ipairs(profile._execution_log) do
        local ok, err = EventSchema.validate(entry)
        T.assert_true(ok, "emitted event failed validation: " .. tostring(err))
    end
end

function M.test_runner_state_still_renders_the_event_list()
    local profile = make_profile()
    profile:_log_event("action_failed", { action_type = "Kill", msg = "target gone" })
    local vm = RunnerState.build({ executor = profile, now = 100 })
    T.assert_true(#vm.events >= 1, "the cockpit must still see events")
    T.assert_equal(vm.events[1].event, "action_failed", "event name")
    T.assert_equal(vm.events[1].text, "target gone", "text still comes off the flat payload")
end

function M.test_bus_and_blackboard_still_receive_the_entry()
    local profile = make_profile()
    local seen
    profile._event_bus:subscribe("questing:log", function(entry) seen = entry end)
    profile:_log_event("action_success", { msg = "ok" })
    T.assert_not_nil(seen, "questing:log must still be published")
    T.assert_equal(seen.event, "action_success", "bus payload is the entry")
    T.assert_equal(seen.schema_version, 1, "and it carries the contract")
    local last = profile._blackboard:get("module.questing.last_log")
    T.assert_equal(last.seq, seen.seq, "module.questing.last_log must still be the same entry")
end

function M.test_a_resumed_session_is_a_new_run_over_a_continuing_seq()
    -- _load_save rehydrates execution_history and takes _log_total from the last entry's seq, so
    -- seq keeps counting across a resume (it is an absolute index, not a per-session one) while
    -- the resumed events belong to a different run than the restored ones.
    written_files = {}
    local first = make_profile()
    first:_log_event("action_success", { msg = "before the logout" })
    local old_run_id = first._execution_log[1].run_id
    first:_save()

    local second = make_profile()
    T.assert_true(second:_load_save(), "the save must restore")
    local restored = second._execution_log[1]
    T.assert_equal(restored.run_id, old_run_id, "restored entries keep the run that produced them")
    T.assert_equal(restored.seq, 1, "the restored entry keeps its original absolute index")

    -- _load_save emits `save_restored` itself, so the resumed run has already opened by here.
    local before = second._log_total
    second:_log_event("action_success", { msg = "after the logout" })
    local fresh = second._execution_log[#second._execution_log]
    T.assert_true(fresh.run_id ~= old_run_id, "the resumed session is its own run")
    T.assert_equal(fresh.seq, before + 1, "seq keeps counting across the resume")
end

function M.test_execution_history_round_trips_through_the_save()
    local profile = make_profile()
    profile:_log_event("action_success", { msg = "ok" })
    local state = profile:_serialize_state()
    T.assert_equal(#state.execution_history, 1, "history is serialized")
    T.assert_equal(state.execution_history[1].schema_version, 1, "with the contract intact")
    T.assert_equal(state.execution_history[1].run_id, profile._execution_log[1].run_id, "and the run id")
end

-- ============================================================================
-- seq stays absolute
-- ============================================================================

function M.test_seq_stays_absolute_after_the_ring_buffer_wraps()
    local profile = make_profile()
    for i = 1, 600 do
        profile:_log_event("action_success", { i = i })
    end
    local log = profile._execution_log
    T.assert_equal(#log, 500, "ring buffer still caps at 500")
    T.assert_equal(log[1].seq, 101, "the oldest surviving entry keeps its absolute index")
    T.assert_equal(log[#log].seq, 600, "and the newest is the absolute total")
    T.assert_equal(profile._log_total, 600, "the counter is not reset by the wrap")
    local run_id = log[1].run_id
    for _, entry in ipairs(log) do
        T.assert_equal(entry.run_id, run_id, "a wrap is not a new run")
    end
end

return M
