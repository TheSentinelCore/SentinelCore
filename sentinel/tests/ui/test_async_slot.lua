-- tests/ui/test_async_slot.lua
-- The poll-until-resolved primitive (spec: Async Pending Re-Arm) and the harness half that makes it
-- observable offline (spec: Async-Pending Mock Mode in Offline Harness).
--
-- WHY BOTH LIVE IN ONE FILE
-- -------------------------
-- The regression this closes was not a bug in the panels' logic; it was a bug in what the offline
-- suite could SEE. `core.http_get` did not exist in the mock, so every fetch resolved in the same
-- call and the `(nil, true)` branch -- the only branch the injector actually takes first -- was dead
-- code that no test could reach. Testing the slot against a hand-written pending stub alone would
-- rebuild exactly that blind spot, so the second half of this file drives the REAL `QueryClient`
-- over the mock and asserts it answers pending before it answers data.

local AsyncSlot = require("ui/async_slot")
local QueryClient = require("shared/query_client")
local Mock = require("tests/harness/mocks/sylvannas_api")
local T = require("tests/test_util")

local M = {}

--- A panel state, reduced to the three fields a slot is allowed to touch.
local function owner()
    return { _dirty = false, loading = false, error = nil }
end

--- A fetch that answers pending `pending_for` times and then answers `value`.
local function pending_then(pending_for, value)
    local calls = 0
    return function()
        calls = calls + 1
        if calls <= pending_for then return nil, true end
        return value
    end, function() return calls end
end

-- ---------------------------------------------------------------------------
-- Poll until resolved
-- ---------------------------------------------------------------------------

function M.test_a_pending_fetch_re_arms_the_owner_and_leaves_it_loading()
    local state = owner()
    local slot = AsyncSlot.new({ label = "quest detail", owner = state })
    local fetch = pending_then(1, { id = 7 })

    local status = slot:poll(fetch)
    T.assert_equal(status, "pending", "an in-flight fetch is pending, not failed")
    T.assert_true(state._dirty,
        "the owner must be re-armed, or the tick that collects the answer never runs -- this is the "
        .. "whole defect: flags were cleared before the fetch resolved and the panel froze")
    T.assert_true(state.loading, "and the panel says it is waiting")
    T.assert_nil(state.error, "a request still in flight is not a failure")
end

function M.test_the_next_poll_stores_the_data_and_clears()
    local state = owner()
    local slot = AsyncSlot.new({ label = "quest detail", owner = state })
    local fetch = pending_then(1, { id = 7 })

    slot:poll(fetch)
    state._dirty = false            -- the binding's on_tick clears it at the top of the next tick
    local status, data = slot:poll(fetch)

    T.assert_equal(status, "ok", "the second poll resolves")
    T.assert_equal(data.id, 7, "and hands back what the server answered")
    T.assert_equal(slot.data.id, 7, "the slot caches it too")
    T.assert_false(state._dirty, "a resolved fetch must NOT keep re-arming; that is a spin")
    T.assert_false(state.loading, "and the panel stops waiting")
end

function M.test_a_resolution_to_nothing_names_the_lookup_and_clears()
    local state = owner()
    local slot = AsyncSlot.new({ label = "quest detail", owner = state })

    local status = slot:poll(function() return nil end)
    T.assert_equal(status, "failed", "nil with no pending flag is a resolved failure")
    T.assert_equal(state.error, "quest detail failed", "the error must name the lookup that failed")
    T.assert_false(state._dirty, "and the flag clears -- a failed fetch must not poll forever")
    T.assert_false(state.loading, "nor leave the panel spinning")
end

function M.test_a_fetch_that_raises_is_a_failure_and_not_a_throw()
    -- A binding's on_tick that throws skips every other panel refresh in the same shell tick.
    local state = owner()
    local slot = AsyncSlot.new({ label = "quest detail", owner = state })
    local status = slot:poll(function() error("connection reset") end)

    T.assert_equal(status, "failed", "a raise resolves the slot rather than escaping it")
    T.assert_true(state.error:find("quest detail", 1, true) ~= nil, "named")
    T.assert_true(state.error:find("connection reset", 1, true) ~= nil,
        "and the reason survives: 'quest detail failed' alone sends the operator nowhere")
end

function M.test_a_fetch_that_never_answers_expires_instead_of_polling_forever()
    local state = owner()
    local slot = AsyncSlot.new({ label = "quest detail", owner = state, max_ticks = 3 })
    local forever = function() return nil, true end

    for i = 1, 3 do
        T.assert_equal(slot:poll(forever), "pending", "poll " .. i .. " is still waiting")
    end
    state._dirty = false
    T.assert_equal(slot:poll(forever), "timeout", "the fourth poll gives up")
    T.assert_false(state._dirty, "an expired fetch must stop re-arming")
    T.assert_true(state.error:find("quest detail", 1, true) ~= nil,
        "and say which lookup went unanswered, got: " .. tostring(state.error))
end

function M.test_a_success_clears_only_its_own_message()
    -- Two slots on one state fail independently; a detail that lands must not erase the search's
    -- failure from the panel.
    local state = owner()
    local detail = AsyncSlot.new({ label = "quest detail", owner = state })
    local search = AsyncSlot.new({ label = "quest search", owner = state })

    search:poll(function() return nil end)
    T.assert_equal(state.error, "quest search failed", "the search failed")
    detail:poll(function() return { id = 7 } end)
    T.assert_equal(state.error, "quest search failed",
        "an unrelated success must not clear another slot's error")

    search:poll(function() return { 1 } end)
    T.assert_nil(state.error, "but the slot that set the message does clear it")
end

function M.test_reset_abandons_the_request_the_selection_replaced()
    local state = owner()
    local slot = AsyncSlot.new({ label = "quest detail", owner = state, max_ticks = 2 })
    local forever = function() return nil, true end

    slot:poll(forever)
    slot:poll(forever)
    slot:reset()                    -- the operator selected a different quest
    T.assert_equal(slot.ticks, 0, "the abandoned request's tick count must not expire the new one")
    T.assert_equal(slot:poll(forever), "pending", "so the fresh fetch gets its full budget")
end

-- ---------------------------------------------------------------------------
-- The harness mirror: the real QueryClient over the real async signature
-- ---------------------------------------------------------------------------

local function with_mock_http(fn)
    local saved = _G.core
    Mock.setup_globals()
    Mock.reset_http()
    local ok, err = pcall(fn)
    Mock.reset_http()
    _G.core = saved
    if not ok then error(err, 0) end
end

function M.test_the_mock_holds_the_callback_so_the_client_answers_pending_first()
    with_mock_http(function()
        Mock.http.pending_ticks = 2
        Mock.set_http_response("/quest/1234", { id = 1234, title = "The Missing Diplomat" })
        local qc = QueryClient:new("127.0.0.1", 3030)

        local data, pending = qc:get_quest(1234)
        T.assert_nil(data, "the live http_get returns before the server answers")
        T.assert_true(pending, "so the first call must report pending, exactly as in-game")

        T.assert_equal(#Mock.http.requests, 1, "the request was actually issued")
        local again, still_pending = qc:get_quest(1234)
        T.assert_nil(again, "polling again while in flight still has no answer")
        T.assert_true(still_pending, "and still reports pending")
        T.assert_equal(#Mock.http.requests, 1,
            "without re-issuing the request -- the client de-dupes in-flight paths")

        Mock.http_advance(2)
        local resolved = qc:get_quest(1234)
        T.assert_not_nil(resolved, "once the callback fires the data is there")
        T.assert_equal(resolved.title, "The Missing Diplomat", "decoded from the JSON body")
    end)
end

function M.test_an_unrouted_url_resolves_to_a_terminal_miss_rather_than_pending_forever()
    with_mock_http(function()
        Mock.http.pending_ticks = 1
        local qc = QueryClient:new("127.0.0.1", 3030)
        T.assert_true(select(2, qc:get_npc(99999)) == true, "pending while in flight")
        Mock.http_advance(1)
        local data, pending = qc:get_npc(99999)
        T.assert_nil(data, "a 404 has no data")
        T.assert_nil(pending, "and must NOT read as pending, or the panel polls a miss forever")
    end)
end

function M.test_a_slot_driven_by_the_real_client_re_arms_then_resolves()
    with_mock_http(function()
        Mock.http.pending_ticks = 2
        Mock.set_http_response("/npc/567", { entry = 567, name = "Hogger" })
        local qc = QueryClient:new("127.0.0.1", 3030)
        local state = owner()
        local slot = AsyncSlot.new({ label = "inspector detail", owner = state })
        local fetch = function() return qc:get_npc(567) end

        T.assert_equal(slot:poll(fetch), "pending", "tick 1: the request is in flight")
        T.assert_true(state._dirty, "and the owner is re-armed for tick 2")

        state._dirty = false
        Mock.http_advance(2)
        local status, npc = slot:poll(fetch)
        T.assert_equal(status, "ok", "tick 2: the answer landed")
        T.assert_equal(npc.name, "Hogger", "and it is the server's row, not a fixture")
        T.assert_nil(state.error, "no error on a fetch that simply took a tick")
    end)
end

return M
