-- tests/ui/test_editor_client.lua
-- The :3031 campaign transport (spec: Campaign Lifecycle Contract for the Lua Client).
--
-- Everything here runs the REAL `EditorClient` over the REAL `QueryClient` over the harness's
-- held-callback `core.http_post`/`core.http_get`. Nothing is stubbed between the method under test
-- and the wire, because the whole class of defect this file guards is "the write was never issued
-- and something answered ok anyway".

local EditorClient = require("shared/editor_client")
local Mock = require("tests/harness/mocks/sylvannas_api")
local T = require("tests/test_util")

local M = {}

local function with_mock_http(fn)
    local saved = _G.core
    Mock.setup_globals()
    Mock.reset_http()
    local ok, err = pcall(fn)
    Mock.reset_http()
    _G.core = saved
    if not ok then error(err, 0) end
end

--- A campaign as the editor serializes it: one graph holding whatever nodes are passed.
local function campaign(name, graph_id, nodes)
    return {
        schema_version = 1,
        id = "11111111-1111-4111-8111-111111111111",
        name = name,
        imports = {}, variables = {}, conditions = {},
        graphs = { {
            id = graph_id,
            name = "main",
            entry_node = "00000000-0000-0000-0000-000000000000",
            nodes = nodes or {},
            edges = {},
        } },
    }
end

local GRAPH_ID = "22222222-2222-4222-8222-222222222222"

-- ---------------------------------------------------------------------------
-- Ids
-- ---------------------------------------------------------------------------

function M.test_uuid4_has_the_layout_the_rust_side_parses()
    local id = EditorClient.uuid4()
    T.assert_equal(#id, 36, "a UUID string is 36 characters")
    T.assert_true(id:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x") ~= nil,
        "version 4 and variant 10xx, because platform::Node.id is a Uuid and not a string: "
        .. "the Explorer's authoring id would be rejected with a 400, got " .. id)
    T.assert_true(EditorClient.uuid4() ~= id, "and two calls must not collide")
end

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

function M.test_list_campaigns_is_pending_before_it_is_data()
    with_mock_http(function()
        Mock.http.pending_ticks = 2
        Mock.set_http_response("/editor/campaigns", {
            { name = "a", id = "x", updated_at = "", node_count = 0, edge_count = 0 },
            { name = "b", id = "y", updated_at = "", node_count = 3, edge_count = 2 },
        })
        local ec = EditorClient:new("127.0.0.1", 3031)

        local data, pending = ec:list_campaigns()
        T.assert_nil(data, "the live http_get returns before the editor answers")
        T.assert_true(pending, "so the first call reports pending, exactly as in-game")

        Mock.http_advance(2)
        local list = ec:list_campaigns()
        T.assert_equal(#list, 2, "two campaigns came back")
        T.assert_equal(list[2].name, "b", "in the order the editor sent them")
        T.assert_equal(list[2].node_count, 3, "carrying CampaignSummary's node_count")
    end)
end

function M.test_load_campaign_returns_the_graph_the_editor_holds()
    with_mock_http(function()
        Mock.http.pending_ticks = 1
        Mock.set_http_response("/editor/campaigns/stw",
            campaign("stw", GRAPH_ID, { { id = "n1", type = "questing.Kill", intent = { creature_entry = 567 } } }))
        local ec = EditorClient:new("127.0.0.1", 3031)

        T.assert_true(select(2, ec:load_campaign("stw")) == true, "pending first")
        Mock.http_advance(1)
        local loaded = ec:load_campaign("stw")
        T.assert_equal(loaded.name, "stw", "the campaign came back")
        T.assert_equal(loaded.graphs[1].nodes[1].type, "questing.Kill", "with its graph's nodes")
    end)
end

function M.test_an_unknown_campaign_resolves_to_a_miss_not_to_pending_forever()
    with_mock_http(function()
        Mock.http.pending_ticks = 1
        local ec = EditorClient:new("127.0.0.1", 3031)
        T.assert_true(select(2, ec:load_campaign("nope")) == true, "pending while in flight")
        Mock.http_advance(1)
        local data, pending = ec:load_campaign("nope")
        T.assert_nil(data, "a 404 has no campaign")
        T.assert_nil(pending, "and must not read as pending, or the panel spins on a miss")
    end)
end

function M.test_graph_id_for_reads_the_first_graph_of_the_loaded_campaign()
    with_mock_http(function()
        Mock.http.pending_ticks = 1
        Mock.set_http_response("/editor/campaigns/stw", campaign("stw", GRAPH_ID, {}))
        local ec = EditorClient:new("127.0.0.1", 3031)

        local id, blocked = ec:graph_id_for("stw")
        T.assert_nil(id, "the campaign has not arrived yet")
        T.assert_true(blocked:find("still loading", 1, true) ~= nil,
            "and the reason says so rather than claiming the campaign has no graph, got "
            .. tostring(blocked))

        Mock.http_advance(1)
        T.assert_equal(ec:graph_id_for("stw"), GRAPH_ID, "then it is the graph the editor holds")
    end)
end

function M.test_a_campaign_with_no_graph_is_not_the_same_as_a_campaign_that_is_missing()
    with_mock_http(function()
        Mock.http.pending_ticks = 0
        -- `Campaign::new` gives a fresh campaign ZERO graphs, so this is the state right after a
        -- create -- and it must read differently from "the editor does not have that campaign".
        local fresh = campaign("stw", GRAPH_ID, {})
        fresh.graphs = {}
        Mock.set_http_response("/editor/campaigns/stw", fresh)
        local ec = EditorClient:new("127.0.0.1", 3031)

        local id, blocked = ec:graph_id_for("stw")
        T.assert_nil(id, "there is no graph to write into")
        T.assert_nil(blocked, "but nothing is blocking either -- a caller may mint one")

        local missing_id, missing_why = ec:graph_id_for("ghost")
        T.assert_nil(missing_id, "a campaign the editor does not have has no graph either")
        T.assert_true(missing_why:find("could not be read", 1, true) ~= nil,
            "and THAT is a blocker, got " .. tostring(missing_why))
    end)
end

-- ---------------------------------------------------------------------------
-- The cache the writes will have to drop
-- ---------------------------------------------------------------------------

function M.test_invalidate_drops_cached_reads_under_a_prefix_and_keeps_the_rest()
    with_mock_http(function()
        Mock.http.pending_ticks = 0
        Mock.set_http_response("/editor/campaigns/stw", campaign("stw", GRAPH_ID, {}))
        Mock.set_http_response("/npc/567", { entry = 567, name = "Hogger" })
        local ec = EditorClient:new("127.0.0.1", 3031)
        local qc = ec:query_client()

        ec:load_campaign("stw")
        qc:_get("/npc/567")
        T.assert_equal(#Mock.http.requests, 2, "both were fetched once")

        ec:load_campaign("stw")
        T.assert_equal(#Mock.http.requests, 2, "and the second read is served from cache")

        T.assert_equal(qc:invalidate("/editor/campaigns"), 1, "one campaign path was dropped")
        ec:load_campaign("stw")
        T.assert_equal(#Mock.http.requests, 3,
            "so the campaign is re-read -- without this a graph would keep answering its pre-write "
            .. "shape for the life of the session")
        qc:_get("/npc/567")
        T.assert_equal(#Mock.http.requests, 3, "while game data outside the prefix stays cached")
    end)
end

function M.test_invalidate_frees_an_in_flight_path_to_be_asked_again()
    with_mock_http(function()
        Mock.http.pending_ticks = 2
        Mock.set_http_response("/editor/campaigns/stw", campaign("stw", GRAPH_ID, {}))
        local ec = EditorClient:new("127.0.0.1", 3031)

        ec:load_campaign("stw")
        T.assert_equal(#Mock.http.requests, 1, "one request is in the air")
        ec:query_client():invalidate("/editor/campaigns")
        ec:load_campaign("stw")
        T.assert_equal(#Mock.http.requests, 2,
            "a read already in flight when a write landed will resolve with pre-write data, so the "
            .. "next poll has to be free to issue a fresh one rather than wait on it")
    end)
end

return M
