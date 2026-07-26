-- tests/core/test_event_schema.lua
-- ADR 09a §1.5 — the versioned event contract, tested as a pure module.
--
-- The reason this contract has its own module (and this suite) is drift: the execution log has
-- ~30 emit sites, each of which built its own flat table, so nothing stopped a producer from
-- omitting a field or shadowing one with a payload key of the same name. Everything below pins
-- the shape at the single construction point instead of at 30 call sites.

local EventSchema = require("core/event_schema")
local T = require("tests/test_util")

local M = {}

-- ============================================================================
-- §1.5 shape
-- ============================================================================

function M.test_build_carries_every_contract_field()
    local e = EventSchema.build({
        event = "action_success",
        timestamp = 1204.83,
        state = "running",
        seq = 42,
        run_id = "018f2c3a-0001-0002",
        node_id = "018f3a11-0003-0004",
        data = { action_type = "AcceptQuest" },
    })

    T.assert_equal(e.schema_version, 1, "schema_version")
    T.assert_equal(e.seq, 42, "seq")
    T.assert_equal(e.run_id, "018f2c3a-0001-0002", "run_id")
    T.assert_equal(e.node_id, "018f3a11-0003-0004", "node_id")
    T.assert_equal(e.event, "action_success", "event")
    T.assert_equal(e.timestamp, 1204.83, "timestamp")
    T.assert_equal(e.state, "running", "state")
    T.assert_equal(type(e.data), "table", "data must be a table")
    T.assert_equal(e.data.action_type, "AcceptQuest", "data payload")
end

function M.test_schema_version_is_one()
    T.assert_equal(EventSchema.SCHEMA_VERSION, 1, "phase 1 ships schema_version 1")
end

function M.test_node_id_is_absent_for_profile_scoped_events()
    local e = EventSchema.build({
        event = "load_fresh",
        timestamp = 1.0,
        state = "running",
        seq = 1,
        run_id = "run-a",
    })
    T.assert_nil(e.node_id, "a profile-scoped event has no graph node")
    T.assert_true(EventSchema.validate(e), "a nil node_id is still a valid event")
end

function M.test_data_defaults_to_an_empty_table()
    local e = EventSchema.build({ event = "load_fresh", timestamp = 0, seq = 1, run_id = "r" })
    T.assert_equal(type(e.data), "table", "data is always present, never nil")
    T.assert_nil(next(e.data), "and empty when the producer passed no payload")
end

-- ============================================================================
-- Backward compatibility: the pre-v1 consumers read a FLAT entry
-- ============================================================================

function M.test_payload_stays_flattened_for_pre_v1_consumers()
    -- runner_state.lua reads `e.msg` / `e.action_type` straight off the entry, and the save
    -- file's execution_history is the same table. Nesting the payload without also keeping it
    -- flat would blank the runner cockpit's event list.
    local e = EventSchema.build({
        event = "action_failed",
        timestamp = 5,
        state = "running",
        seq = 7,
        run_id = "r",
        data = { action_type = "Kill", msg = "target gone" },
    })
    T.assert_equal(e.action_type, "Kill", "payload key readable flat")
    T.assert_equal(e.msg, "target gone", "payload key readable flat")
    T.assert_equal(e.data.action_type, "Kill", "and nested")
end

function M.test_legacy_fields_stay_overridable_by_the_payload()
    -- `operation` is pre-v1 and several emit sites deliberately pass their own value for it
    -- (load_with_save, operation_already_done). That override must survive.
    local e = EventSchema.build({
        event = "operation_already_done",
        timestamp = 0,
        seq = 1,
        run_id = "r",
        legacy = { operation = 3 },
        data = { operation = 11 },
    })
    T.assert_equal(e.operation, 11, "payload wins over the legacy default")
end

function M.test_contract_fields_cannot_be_shadowed_by_the_payload()
    local e = EventSchema.build({
        event = "action_success",
        timestamp = 9,
        state = "running",
        seq = 4,
        run_id = "real-run",
        data = {
            schema_version = 99,
            seq = 1,
            run_id = "forged",
            event = "forged",
            timestamp = 0,
            state = "forged",
        },
    })
    T.assert_equal(e.schema_version, 1, "schema_version is not producer-writable")
    T.assert_equal(e.seq, 4, "seq is not producer-writable")
    T.assert_equal(e.run_id, "real-run", "run_id is not producer-writable")
    T.assert_equal(e.event, "action_success", "event is not producer-writable")
    T.assert_equal(e.timestamp, 9, "timestamp is not producer-writable")
    T.assert_equal(e.state, "running", "state is not producer-writable")
end

function M.test_node_id_is_promoted_out_of_the_payload()
    -- The graph executor has no Lua-side node identity yet, so the only way an emit site can
    -- name one is through its payload. Promoting it here is what lets those sites land later
    -- without another pass over _log_event.
    local e = EventSchema.build({
        event = "action_success",
        timestamp = 0,
        seq = 1,
        run_id = "r",
        node_id = nil,
        data = { node_id = "018f-node" },
    })
    T.assert_equal(e.node_id, "018f-node", "payload node_id becomes the contract node_id")
end

function M.test_build_does_not_alias_the_payload_table()
    local payload = { i = 1 }
    local e = EventSchema.build({ event = "x", timestamp = 0, seq = 1, run_id = "r", data = payload })
    payload.i = 2
    T.assert_equal(e.data.i, 1, "the entry owns its own copy; a reused payload cannot rewrite history")
end

-- ============================================================================
-- Validation
-- ============================================================================

function M.test_validate_accepts_a_built_event()
    local ok, err = EventSchema.validate(EventSchema.build({
        event = "nav_started", timestamp = 3, state = "navigating", seq = 2, run_id = "r",
    }))
    T.assert_true(ok, "a built event must validate: " .. tostring(err))
end

function M.test_validate_rejects_a_drifted_event()
    local cases = {
        { name = "not a table", entry = "nope" },
        { name = "wrong schema_version", entry = { schema_version = 2, seq = 1, run_id = "r", event = "e", timestamp = 0, data = {} } },
        { name = "missing run_id", entry = { schema_version = 1, seq = 1, event = "e", timestamp = 0, data = {} } },
        { name = "empty run_id", entry = { schema_version = 1, seq = 1, run_id = "", event = "e", timestamp = 0, data = {} } },
        { name = "seq below one", entry = { schema_version = 1, seq = 0, run_id = "r", event = "e", timestamp = 0, data = {} } },
        { name = "fractional seq", entry = { schema_version = 1, seq = 1.5, run_id = "r", event = "e", timestamp = 0, data = {} } },
        { name = "missing event", entry = { schema_version = 1, seq = 1, run_id = "r", timestamp = 0, data = {} } },
        { name = "non-numeric timestamp", entry = { schema_version = 1, seq = 1, run_id = "r", event = "e", timestamp = "now", data = {} } },
        { name = "numeric node_id", entry = { schema_version = 1, seq = 1, run_id = "r", event = "e", timestamp = 0, node_id = 7, data = {} } },
        { name = "missing data", entry = { schema_version = 1, seq = 1, run_id = "r", event = "e", timestamp = 0 } },
    }
    for _, case in ipairs(cases) do
        local ok, err = EventSchema.validate(case.entry)
        T.assert_false(ok, "validate must reject: " .. case.name)
        T.assert_equal(type(err), "string", "a rejection must say why (" .. case.name .. ")")
    end
end

-- ============================================================================
-- Run identity
-- ============================================================================

function M.test_new_run_id_is_a_non_empty_string()
    local id = EventSchema.new_run_id()
    T.assert_equal(type(id), "string", "run_id is a string")
    T.assert_true(#id > 0, "run_id is non-empty")
end

function M.test_new_run_id_never_repeats_within_a_session()
    -- core.time() has coarse resolution and math.random is unseeded in the sandbox, so time and
    -- randomness alone can collide inside one tick. Uniqueness has to be structural.
    local seen = {}
    for _ = 1, 500 do
        local id = EventSchema.new_run_id()
        T.assert_nil(seen[id], "run ids must not repeat: " .. tostring(id))
        seen[id] = true
    end
end

function M.test_module_requires_without_touching_the_sylvannas_api()
    -- The contract has to be constructible offline (tests, importer tooling), so nothing may be
    -- read off `core` at require time.
    local saved = _G.core
    _G.core = nil
    package.loaded["core/event_schema"] = nil
    local ok, mod = pcall(require, "core/event_schema")
    _G.core = saved
    package.loaded["core/event_schema"] = nil
    require("core/event_schema")
    T.assert_true(ok, "require must survive a missing `core` global: " .. tostring(mod))
    T.assert_equal(type(mod), "table", "module loads")
end

return M
