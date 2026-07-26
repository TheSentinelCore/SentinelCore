-- tests/modules/questing/test_resolve_control.lua
-- ADR 09a W13: recording -> resolve -> run, closed inside the client.
--
-- Recording Mode already wrote a Campaign and QueryServer already lowered one into an ExecutionPlan;
-- nothing joined them. An author had to leave the game, curl the file by hand and drop the answer
-- into the profile directory before the route they had just walked could be run. This suite pins the
-- missing link, and in particular the three things that go wrong quietly:
--
--   1. `core.http_post` is ASYNCHRONOUS. A verb that answers as if it were synchronous reports
--      success for a plan that does not exist yet -- and blocking a tick on the network stalls the
--      client, which is why waiting is not an option either.
--   2. Diagnostics ARE the product. A 200 carrying diagnostics means the plan lowered but the route
--      has holes only the author can fix; swallowing them makes the round trip pointless.
--   3. The endpoint has three distinct failures -- dead server, malformed campaign, broken database.
--      sentinel-resolver went to real trouble to keep them apart; collapsing them into "failed"
--      sends the operator to restart a server that is fine, or to edit a campaign that is correct.

local EventBus = require("core/event_bus")
local Blackboard = require("core/blackboard")
local QuestingModule = require("modules/questing/module")
local ExecutionPlan = require("modules/questing/execution_plan")
local JSON = require("core/JSON")
local T = require("tests/test_util")

local M = {}

local RECORDING_PATH = "sentinel/data/recordings/northshire.json"
local PROFILE_DIR = "sentinel/data/profiles/quests"

local CAMPAIGN = {
    schema_version = 3,
    id = "campaign-1",
    name = "Northshire",
    imports = {},
    variables = {},
    conditions = {},
    graphs = {
        {
            id = "graph-1",
            name = "Northshire",
            entry_node = "n1",
            nodes = {
                {
                    id = "n1",
                    type = "questing.AcceptQuest",
                    intent = { quest = { ref = "quest:33" }, from = { ref = "npc:823" } },
                },
            },
            edges = {},
        },
    },
}

--- Shaped like resolver output: `node_id` plus a `next` table on the first operation are exactly the
--- two fields execution_plan.lua discriminates a plan by.
local PLAN = {
    schema_version = 3,
    content_hash = "0123456789abcdef",
    db_fingerprint = "tbcmangos",
    operations = {
        {
            node_id = "n1",
            next = { { to_index = 1 } },
            actions = { { type = "AcceptQuest", payload = { quest_id = 33 } } },
        },
        {
            node_id = "n2",
            next = {},
            actions = { { type = "TurnInQuest", payload = { quest_id = 33 } } },
        },
    },
}

local function resolve_body(diagnostics)
    return JSON.encode({ plan = PLAN, diagnostics = diagnostics or {} })
end

local SANDBOX_KEYS = {
    "read_data_file", "write_data_file", "create_data_file", "read_dir", "http_post",
}

--- Stand up the sandbox file/HTTP surface the verb runs against, hand the fixture to `fn`, restore.
---
--- `opts.respond(url, body) -> http_code, response` is the QueryServer stand-in. `opts.defer` holds
--- the callback instead of running it, which is what the LIVE client does -- that is the only way to
--- tell a pending answer from a finished one.
local function with_sandbox(opts, fn)
    opts = opts or {}
    local saved = {}
    for _, key in ipairs(SANDBOX_KEYS) do saved[key] = _G.core[key] end

    local env = { posts = {}, writes = {}, deliver = nil }

    _G.core.read_data_file = function(path)
        local content = (opts.files or {})[path]
        if content == nil then return nil, "Mock: file not found" end
        return content
    end
    _G.core.write_data_file = function(path, content)
        env.writes[#env.writes + 1] = { path = path, content = content }
        return true
    end
    _G.core.create_data_file = function() return nil end
    _G.core.read_dir = function(dir)
        local names = {}
        for _, write in ipairs(env.writes) do
            local parent, base = write.path:match("^(.*)/([^/]+)$")
            if parent == dir then names[#names + 1] = base end
        end
        return names
    end
    _G.core.http_post = function(a, b, c, d)
        local url, headers, body, callback
        if type(b) == "table" then
            url, headers, body, callback = a, b, c, d
        else
            url, headers, body, callback = a, nil, b, c
        end
        -- The live signature is the thing query_client.lua already got burned by once (http_get's
        -- one-argument form raises in the injector). A transport that refuses the headers form must
        -- still be usable, so this mode reproduces that refusal.
        if opts.reject_headers_form and headers ~= nil then
            error("bad argument #2 to 'http_post' (string expected, got table)", 0)
        end
        env.posts[#env.posts + 1] = { url = url, headers = headers, body = body }
        if opts.defer then
            env.deliver = function(code, response)
                callback(code, "application/json", response, "")
            end
            return nil
        end
        local respond = opts.respond or function() return 200, resolve_body() end
        local code, response = respond(url, body)
        callback(code, "application/json", response, "")
        return nil
    end

    local questing = QuestingModule:new(Blackboard:new(), EventBus:new())
    local ok, err = pcall(fn, questing, env)

    for _, key in ipairs(SANDBOX_KEYS) do _G.core[key] = saved[key] end
    if not ok then error(err, 0) end
end

local function saved_recording()
    return { [RECORDING_PATH] = JSON.encode(CAMPAIGN) }
end

-- ---------------------------------------------------------------------------
-- The request
-- ---------------------------------------------------------------------------

function M.test_the_saved_recording_is_read_and_posted_as_the_campaign_body()
    with_sandbox({ files = saved_recording() }, function(questing, env)
        questing:resolve_recording("Northshire")

        T.assert_equal(#env.posts, 1, "exactly one request per operator action")
        T.assert_equal(env.posts[1].url, "http://127.0.0.1:3030/resolve",
            "the campaign goes to QueryServer's resolve endpoint")

        local posted = JSON.decode(env.posts[1].body)
        T.assert_not_nil(posted, "the body must be the recording, verbatim JSON")
        T.assert_equal(posted.name, "Northshire", "and it must be the campaign that was recorded")
        T.assert_equal(posted.schema_version, 3, "the resolver dispatches on the schema version")
        T.assert_equal(#posted.graphs[1].nodes, 1, "with the recorded tasks intact")
    end)
end

--- The name is optional: the operator who just recorded and saved should not have to retype where it
--- landed. Naming one explicitly must still win.
function M.test_the_recording_of_the_current_session_is_the_default_source()
    with_sandbox({ files = saved_recording() }, function(questing, env)
        questing:start_recording("Northshire")
        questing:stop_recording()

        local result = questing:resolve_recording()

        T.assert_true(result.ok, "the session's own recording must be the default: "
            .. tostring(result.reason))
        T.assert_equal(#env.posts, 1, "and it must reach the wire")
    end)
end

--- Resolution is an explicit operator action, once. The tick runs 60 times a second; an HTTP call on
--- that path would hammer QueryServer for the whole session.
function M.test_no_tick_ever_reaches_the_network()
    with_sandbox({ files = saved_recording() }, function(questing, env)
        questing:start_recording("Northshire")
        for _ = 1, 200 do questing:tick(0.016) end

        T.assert_equal(#env.posts, 0,
            "resolution must never ride a per-frame path; " .. tostring(#env.posts) .. " requests left")
    end)
end

--- query_client.lua carries a hard-won note about `core.http_get`'s live signature. The POST path
--- must not re-learn that lesson: a transport that refuses the headers form still has to work.
function M.test_a_transport_that_refuses_the_headers_form_is_still_used()
    with_sandbox({ files = saved_recording(), reject_headers_form = true }, function(questing, env)
        local result = questing:resolve_recording("Northshire")

        T.assert_equal(#env.posts, 1, "the request must fall back to the three-argument form")
        T.assert_true(result.ok, "and still succeed: " .. tostring(result.reason))
    end)
end

-- ---------------------------------------------------------------------------
-- The clean path
-- ---------------------------------------------------------------------------

function M.test_a_clean_resolve_leaves_a_runnable_plan_where_the_runner_looks()
    with_sandbox({ files = saved_recording() }, function(questing, env)
        local result = questing:resolve_recording("Northshire")

        T.assert_true(result.ok, "a resolvable campaign must resolve: " .. tostring(result.reason))
        T.assert_equal(result.status, "resolved", "with nothing for the author to fix")
        T.assert_equal(#env.writes, 1, "exactly one file is written")

        local written = env.writes[1]
        T.assert_true(written.path:find("profiles", 1, true) ~= nil,
            "the PLAN lands in the profile directory, not beside the recording: " .. written.path)
        T.assert_true(written.path:find("recordings", 1, true) == nil,
            "a half-authored recording must never be offered to the runner as a route")
        T.assert_equal(written.path, result.plan_path, "and the reported path is the one written")

        local decoded = JSON.decode(written.content)
        T.assert_not_nil(decoded, "what was written must parse as JSON")
        T.assert_true(ExecutionPlan.is_plan(decoded),
            "and must be an ExecutionPlan the runtime recognises, not the response envelope")

        T.assert_true(#questing:list_profiles(PROFILE_DIR) > 0,
            "the runner discovers routes through list_profiles; a plan it cannot see is not runnable")
    end)
end

--- The whole point of the round trip. A 200 with diagnostics is a plan that lowered AND a route with
--- holes; reporting only "ok" hides the half the author is the only one who can fix.
function M.test_diagnostics_are_surfaced_and_the_plan_is_still_written()
    local diagnostics = {
        { severity = "Error", code = "resolver.spawn.unknown", message = "no spawn for npc:823" },
        { severity = "Warning", code = "resolver.quest.unknown", message = "quest 33 not in database" },
    }
    with_sandbox({
        files = saved_recording(),
        respond = function() return 200, resolve_body(diagnostics) end,
    }, function(questing, env)
        local result = questing:resolve_recording("Northshire")

        T.assert_equal(#env.writes, 1, "a campaign that resolved with problems still produced a plan")
        T.assert_equal(result.diagnostics.count, 2, "and every diagnostic is counted")
        T.assert_equal(result.diagnostics.errors, 1, "errors kept apart from warnings")
        T.assert_equal(result.diagnostics.warnings, 1, "and warnings from errors")
        T.assert_true(#result.diagnostics.messages > 0,
            "the operator sees the first messages, not just a number")
        T.assert_true(tostring(result.diagnostics.messages[1]):find("resolver.spawn.unknown", 1, true) ~= nil,
            "carrying the stable code the author can act on")
        T.assert_true(result.status ~= "resolved",
            "a resolve with diagnostics must not read exactly like a clean one")
    end)
end

-- ---------------------------------------------------------------------------
-- The three failures, kept apart
-- ---------------------------------------------------------------------------

--- Transport failure surfaces as code 0 (docs/SylvannasAPI/dev/api/core.md).
function M.test_an_unreachable_query_server_says_the_server_is_not_answering()
    with_sandbox({
        files = saved_recording(),
        respond = function() return 0, nil end,
    }, function(questing, env)
        local result = questing:resolve_recording("Northshire")

        T.assert_false(result.ok, "nothing resolved")
        T.assert_equal(result.status, "unreachable", "and the operator is pointed at the server")
        T.assert_true(tostring(result.reason):find("QueryServer", 1, true) ~= nil,
            "naming what to start: " .. tostring(result.reason))
        T.assert_equal(#env.writes, 0, "no plan may be written from a failed resolve")
    end)
end

function M.test_a_malformed_campaign_is_reported_as_a_rejected_campaign()
    with_sandbox({
        files = saved_recording(),
        respond = function() return 400, '{"error":"expected value at line 1 column 8"}' end,
    }, function(questing, env)
        local result = questing:resolve_recording("Northshire")

        T.assert_false(result.ok, "a 400 is not a success")
        T.assert_equal(result.status, "rejected",
            "400 is the CAMPAIGN's problem -- reporting it as a dead server sends the operator to "
            .. "restart a process that is running fine")
        T.assert_true(tostring(result.reason):find("expected value", 1, true) ~= nil,
            "and the server's own explanation survives: " .. tostring(result.reason))
        T.assert_equal(#env.writes, 0, "nothing is written")
    end)
end

function M.test_a_backend_failure_is_distinguishable_from_a_rejected_campaign()
    with_sandbox({
        files = saved_recording(),
        respond = function() return 500, '{"error":"database is locked"}' end,
    }, function(questing, env)
        local result = questing:resolve_recording("Northshire")

        T.assert_false(result.ok, "a 500 is not a success")
        T.assert_equal(result.status, "backend_error",
            "500 is the SERVER's problem -- the resolver crate made a broken database "
            .. "distinguishable from a missing entry, and this is where that is thrown away")
        T.assert_true(tostring(result.reason):find("database is locked", 1, true) ~= nil,
            "carrying the backend's own cause: " .. tostring(result.reason))
        T.assert_equal(#env.writes, 0, "nothing is written")
    end)
end

--- Three failures, three answers. Pinned together because the regression that matters is not any one
--- status being wrong, it is two of them becoming the same string.
function M.test_the_three_failure_modes_never_collapse_into_one_answer()
    local statuses = {}
    local cases = {
        { code = 0, body = nil },
        { code = 400, body = '{"error":"bad"}' },
        { code = 500, body = '{"error":"worse"}' },
    }
    for _, case in ipairs(cases) do
        with_sandbox({
            files = saved_recording(),
            respond = function() return case.code, case.body end,
        }, function(questing)
            local result = questing:resolve_recording("Northshire")
            T.assert_true(statuses[result.status] == nil,
                "HTTP " .. tostring(case.code) .. " must not reuse the status of another failure: "
                .. tostring(result.status))
            statuses[result.status] = true
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Answers, never throws
-- ---------------------------------------------------------------------------

function M.test_a_missing_recording_is_answered_rather_than_raised()
    with_sandbox({ files = {} }, function(questing, env)
        local ok, result = pcall(function() return questing:resolve_recording("Nowhere") end)

        T.assert_true(ok, "an absent file must not raise: a debug-bridge eval that throws returns "
            .. "NOTHING to the operator")
        T.assert_false(result.ok, "and it did not resolve")
        T.assert_equal(result.status, "missing_recording", "naming the actual problem")
        T.assert_equal(#env.posts, 0, "no request is made for a file that is not there")
    end)
end

function M.test_a_200_carrying_no_plan_is_not_reported_as_success()
    with_sandbox({
        files = saved_recording(),
        respond = function() return 200, '{"diagnostics":[]}' end,
    }, function(questing, env)
        local result = questing:resolve_recording("Northshire")

        T.assert_false(result.ok, "a body with no plan resolved nothing")
        T.assert_equal(#env.writes, 0, "and must not create a profile out of an empty answer")
    end)
end

function M.test_running_without_a_plan_is_answered_rather_than_raised()
    with_sandbox({ files = {} }, function(questing)
        local ok, result = pcall(function() return questing:run_plan() end)

        T.assert_true(ok, "run_plan must answer, never throw")
        T.assert_false(result.ok, "there is no plan to run")
        T.assert_true(type(result.reason) == "string" and result.reason ~= "",
            "and the operator is told why")
    end)
end

-- ---------------------------------------------------------------------------
-- Asynchrony
-- ---------------------------------------------------------------------------

--- `core.http_post` returns before the server has answered. Reporting the plan as written at that
--- point is a lie the operator only discovers when the runner cannot find the profile.
function M.test_a_dispatched_request_reports_pending_instead_of_pretending_to_be_done()
    with_sandbox({ files = saved_recording(), defer = true }, function(questing, env)
        local result = questing:resolve_recording("Northshire")

        T.assert_equal(result.status, "pending", "the answer has not arrived yet")
        T.assert_equal(#env.writes, 0, "so no plan can exist yet")
        T.assert_equal(questing:resolve_status().status, "pending",
            "and the pollable status agrees")

        env.deliver(200, resolve_body())

        local final = questing:resolve_status()
        T.assert_true(final.ok, "once the server answers, the plan is stored")
        T.assert_equal(final.status, "resolved", "and the status the operator polls changes")
        T.assert_equal(#env.writes, 1, "exactly one plan reaches the disk")
    end)
end

function M.test_the_completed_resolution_is_announced_on_the_bus()
    with_sandbox({ files = saved_recording() }, function(questing)
        local seen = nil
        questing._event_bus:subscribe("questing:recording_resolved", function(payload)
            seen = payload
        end)

        questing:resolve_recording("Northshire")

        T.assert_not_nil(seen, "the cockpit and the log need the completion without polling")
        T.assert_equal(seen.status, "resolved", "carrying the outcome")
    end)
end

-- ---------------------------------------------------------------------------
-- Running what was resolved
-- ---------------------------------------------------------------------------

--- Loading is NOT reimplemented next to the resolve path. `start()` owns the executor, the session
--- counters and the `questing:started` event; a second loader is a second set of them to drift.
function M.test_running_a_resolved_plan_goes_through_the_existing_start_path()
    with_sandbox({ files = saved_recording() }, function(questing, env)
        local resolved = questing:resolve_recording("Northshire")
        T.assert_true(resolved.ok, "the plan must exist before it can be run")

        local started_with = nil
        questing.start = function(_, path)
            started_with = path
            return true
        end

        local result = questing:run_plan()

        T.assert_true(result.ok, "the resolved plan must be runnable without naming it again")
        T.assert_equal(started_with, resolved.plan_path,
            "and it must go through start(), with the path the resolve wrote")
        T.assert_equal(#env.posts, 1, "running must not re-resolve")
    end)
end

function M.test_a_named_plan_is_looked_up_in_the_profile_directory()
    with_sandbox({ files = saved_recording() }, function(questing)
        local started_with = nil
        questing.start = function(_, path)
            started_with = path
            return true
        end

        questing:run_plan("northshire")

        T.assert_equal(started_with, PROFILE_DIR .. "/northshire.json",
            "a bare name resolves against the profile directory the runner reads")
    end)
end

function M.test_a_plan_that_fails_to_load_reports_the_failure_rather_than_claiming_a_run()
    with_sandbox({ files = saved_recording() }, function(questing)
        questing.start = function() return false end

        local result = questing:run_plan("northshire")

        T.assert_false(result.ok, "a profile that did not load is not running")
        T.assert_true(type(result.reason) == "string" and result.reason ~= "",
            "and the operator is told which plan and why")
    end)
end

return M
