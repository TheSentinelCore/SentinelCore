-- tests/ui/test_editor_client.lua
-- The :3031 campaign transport (spec: Campaign Lifecycle Contract for the Lua Client).
--
-- Everything here runs the REAL `EditorClient` over the REAL `QueryClient` over the harness's
-- held-callback `core.http_post`/`core.http_get`. Nothing is stubbed between the method under test
-- and the wire, because the whole class of defect this file guards is "the write was never issued
-- and something answered ok anyway".

local EditorClient = require("shared/editor_client")
local Mock = require("tests/harness/mocks/sylvannas_api")
local JSON = require("core/JSON")
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

--- The body of the nth POST, decoded.
local function post_body(n)
    local entry = Mock.http.posts[n]
    if not entry then return nil end
    return JSON.decode(entry.body)
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

-- ---------------------------------------------------------------------------
-- Create -> list -> open round-trip (the spec's scenario, verbatim)
-- ---------------------------------------------------------------------------

function M.test_create_then_list_then_open_round_trip()
    with_mock_http(function()
        Mock.http.pending_ticks = 0   -- one tick per step keeps the sequence readable
        local ec = EditorClient:new("127.0.0.1", 3031)

        -- GIVEN no campaign "stw": the list is empty and the open is a 404.
        Mock.set_http_response("/editor/campaigns", {})
        T.assert_equal(#ec:list_campaigns(), 0, "nothing exists yet")

        -- WHEN the client creates it.
        Mock.set_http_response("/editor/campaigns", { name = "stw", id = "z", updated_at = "",
                                                      node_count = 0, edge_count = 0 }, 201)
        local summary = ec:create_campaign("stw")
        T.assert_not_nil(summary, "the create must answer, not just leave: the open that follows it "
            .. "would otherwise race the editor and cache the 404")
        T.assert_equal(summary.name, "stw", "and the answer is the new CampaignSummary")
        T.assert_equal(Mock.http.posts[1].url, "http://127.0.0.1:3031/editor/campaigns",
            "POST /editor/campaigns -- the name rides in the BODY, which is the route that exists")
        T.assert_equal(post_body(1).name, "stw", "and the body names the campaign")
        T.assert_nil(ec:take_error(), "a 201 is not an error")

        -- THEN the list contains it and the open returns that exact graph. The create must have
        -- dropped the cached empty list, or this read would serve the pre-write answer forever.
        Mock.set_http_response("/editor/campaigns", {
            { name = "stw", id = "z", updated_at = "", node_count = 1, edge_count = 0 },
        })
        local list = ec:list_campaigns()
        T.assert_equal(#list, 1, "the list is re-read after a write, not served from cache")
        T.assert_equal(list[1].name, "stw", "and it is the campaign that was just created")

        Mock.set_http_response("/editor/campaigns/stw", campaign("stw", GRAPH_ID,
            { { id = "n1", type = "questing.Kill", intent = { creature_entry = 567 } } }))
        local opened = ec:load_campaign("stw")
        T.assert_equal(opened.name, "stw", "the open returns the campaign")
        T.assert_equal(#opened.graphs[1].nodes, 1, "with node_count 1's node in it")
    end)
end

-- ---------------------------------------------------------------------------
-- Writes
-- ---------------------------------------------------------------------------

function M.test_add_nodes_posts_one_node_per_request_into_the_loaded_graph()
    with_mock_http(function()
        Mock.http.pending_ticks = 0
        Mock.set_http_response("/editor/campaigns/stw", campaign("stw", GRAPH_ID, {}))
        local ec = EditorClient:new("127.0.0.1", 3031)
        ec:load_campaign("stw")   -- the graph id comes from the loaded campaign, not from thin air

        local ok, why = ec:add_nodes("stw", {
            { id = "q1234_accept", type = "questing.AcceptQuest", preview = "AcceptQuest 1234",
              intent = { quest_id = 1234, npc_entry = 9, auto_complete_dialog = false } },
            { id = "q1234_turnin", type = "questing.TurnInQuest", preview = "TurnInQuest 1234",
              intent = { quest_id = 1234, npc_entry = 9, choose_reward = 0 } },
        })
        T.assert_true(ok, "both nodes must reach the wire: " .. tostring(why))
        T.assert_equal(#Mock.http.posts, 2, "one POST .../nodes per node")

        local body = post_body(1)
        T.assert_equal(body.graph_id, GRAPH_ID, "addressed to the graph the campaign actually has")
        T.assert_equal(body.node.type, "questing.AcceptQuest", "carrying the node type")
        T.assert_equal(body.node.intent.quest_id, 1234, "and its intent")
        T.assert_equal(#tostring(body.node.id), 36,
            "with a minted UUID -- 'q1234_accept' is not a Uuid and serde would 400")
        T.assert_equal(body.node.context.authoring_id, "q1234_accept",
            "the authoring id is preserved in context, the field the platform model keeps for it")
    end)
end

function M.test_add_nodes_into_a_campaign_with_no_graph_mints_one()
    with_mock_http(function()
        Mock.http.pending_ticks = 0
        -- A freshly CREATED campaign: Campaign::new gives it zero graphs.
        local fresh = campaign("stw", GRAPH_ID, {})
        fresh.graphs = {}
        Mock.set_http_response("/editor/campaigns/stw", fresh)
        local ec = EditorClient:new("127.0.0.1", 3031)
        ec:load_campaign("stw")

        local ok, why = ec:add_nodes("stw", {
            { id = "n1", type = "questing.Kill", intent = { creature_entry = 567, count = 10 } },
        })
        T.assert_true(ok, "the write must still land: " .. tostring(why))
        T.assert_equal(#Mock.http.posts, 1,
            "ONE request -- POST .../nodes against a graphless campaign is a 400 'Graph not found', "
            .. "so the graph and its nodes go up together")
        T.assert_true(Mock.http.posts[1].url:find("/graphs", 1, true) ~= nil,
            "and it is the graphs route, got " .. Mock.http.posts[1].url)
        local body = post_body(1)
        T.assert_equal(#body.graph.nodes, 1, "the minted graph carries the node")
        T.assert_equal(body.graph.entry_node, body.graph.nodes[1].id,
            "and names it as the entry, since entry_node is required")
    end)
end

function M.test_add_nodes_refuses_before_the_wire_when_the_campaign_is_not_readable()
    with_mock_http(function()
        Mock.http.pending_ticks = 0
        local ec = EditorClient:new("127.0.0.1", 3031)   -- nothing routed: the load 404s

        local ok, why = ec:add_nodes("ghost", {
            { id = "n1", type = "questing.Kill", intent = { creature_entry = 1 } },
        })
        T.assert_false(ok, "a write into a campaign the editor does not have is not a write")
        T.assert_true(why:find("could not be read", 1, true) ~= nil,
            "and the reason names it, got " .. tostring(why))
        T.assert_equal(#Mock.http.posts, 0, "nothing was posted")
    end)
end

function M.test_an_empty_intent_is_refused_rather_than_encoded_as_an_array()
    with_mock_http(function()
        Mock.http.pending_ticks = 0
        Mock.set_http_response("/editor/campaigns/stw", campaign("stw", GRAPH_ID, {}))
        local ec = EditorClient:new("127.0.0.1", 3031)
        ec:load_campaign("stw")

        local ok, why = ec:add_nodes("stw", { { id = "n1", type = "questing.Kill", intent = {} } })
        T.assert_false(ok, "an empty Lua table encodes as [], and Intent is a map")
        T.assert_true(why:find("empty intent", 1, true) ~= nil,
            "the reason has to say so here, where it is still in scope; a 400 in-game reads as "
            .. "'the editor is broken'. Got " .. tostring(why))
        T.assert_equal(#Mock.http.posts, 0, "and the request never leaves")
    end)
end

function M.test_update_node_posts_because_the_sdk_has_no_put()
    with_mock_http(function()
        Mock.http.pending_ticks = 0
        Mock.set_http_response("/editor/campaigns/stw", campaign("stw", GRAPH_ID, {}))
        local ec = EditorClient:new("127.0.0.1", 3031)
        ec:load_campaign("stw")

        local node_id = "33333333-3333-4333-8333-333333333333"
        local ok, why = ec:update_node("stw", node_id,
            { type = "questing.Kill", intent = { creature_entry = 567, count = 12 } }, GRAPH_ID)
        T.assert_true(ok, "the edit must reach the wire: " .. tostring(why))
        T.assert_true(Mock.http.posts[1].url:find("/nodes/" .. node_id, 1, true) ~= nil,
            "addressed to the node, got " .. Mock.http.posts[1].url)
        local body = post_body(1)
        T.assert_equal(body.node.id, node_id, "the id in the body is the SERVER's id, not a fresh one")
        T.assert_equal(body.node.intent.count, 12, "carrying the edited field")
        T.assert_equal(body.graph_id, GRAPH_ID, "and the graph it lives in")
    end)
end

-- ---------------------------------------------------------------------------
-- The editor refusing, and the editor being down
-- ---------------------------------------------------------------------------

function M.test_a_refused_write_is_queued_as_an_error_and_never_reported_inline()
    with_mock_http(function()
        Mock.http.pending_ticks = 2
        Mock.set_http_response("/editor/campaigns/stw", campaign("stw", GRAPH_ID, {}))
        local ec = EditorClient:new("127.0.0.1", 3031)
        ec:load_campaign("stw")
        Mock.http_advance(2)
        ec:load_campaign("stw")

        -- The editor answers the node write with a 404. Registered explicitly because routes match
        -- by substring and the campaign route above is a prefix of this one.
        Mock.set_http_response("/editor/campaigns/stw/nodes", "", 404)
        local ok = ec:add_nodes("stw", {
            { id = "n1", type = "questing.Kill", intent = { creature_entry = 567 } },
        })
        T.assert_true(ok, "dispatch succeeded -- that is ALL a dispatch can honestly claim")
        T.assert_nil(ec:take_error(), "and the refusal has not arrived yet")

        Mock.http_advance(2)
        local err = ec:take_error()
        T.assert_not_nil(err, "the refusal lands on a later tick and must be sayable")
        T.assert_true(err:find("404", 1, true) ~= nil, "naming the status, got " .. tostring(err))
        T.assert_nil(ec:take_error(), "drained, not repeated")
    end)
end

function M.test_a_dead_editor_reads_as_a_transport_failure_not_as_a_refusal()
    with_mock_http(function()
        Mock.http.pending_ticks = 0
        Mock.set_http_response("/editor/campaigns/stw", campaign("stw", GRAPH_ID, {}))
        local ec = EditorClient:new("127.0.0.1", 3031)
        ec:load_campaign("stw")
        -- http_code 0 is the only way the SDK distinguishes "not running" from "said no".
        Mock.set_http_response("/editor/campaigns/stw/nodes", "", 0)

        ec:add_nodes("stw", { { id = "n1", type = "questing.Kill", intent = { creature_entry = 1 } } })
        local err = ec:take_error()
        T.assert_not_nil(err, "a dead editor is still an error the operator must see")
        T.assert_true(err:find("did not answer", 1, true) ~= nil,
            "and it names the port rather than a status, got " .. tostring(err))
        T.assert_true(err:find("3031", 1, true) ~= nil, "the port is in the message")
    end)
end

-- ---------------------------------------------------------------------------
-- Validate / compile: POSTs whose answer is the point
-- ---------------------------------------------------------------------------

function M.test_validate_polls_like_a_get_and_yields_diagnostics()
    with_mock_http(function()
        Mock.http.pending_ticks = 2
        Mock.set_http_response("/editor/campaigns/stw/validate", {
            { code = "MISSING_ACCEPT", message = "TurnInQuest(9) has no AcceptQuest(9)",
              node_id = "n_turnin" },
        })
        local ec = EditorClient:new("127.0.0.1", 3031)

        local data, pending = ec:validate("stw")
        T.assert_nil(data, "a POST is async too")
        T.assert_true(pending, "so validate reports pending and an AsyncSlot re-arms the panel")
        T.assert_equal(#Mock.http.posts, 1, "one request")
        T.assert_true(select(2, ec:validate("stw")) == true, "polling again does not re-issue it")
        T.assert_equal(#Mock.http.posts, 1, "still one request")

        Mock.http_advance(2)
        local diags = ec:validate("stw")
        T.assert_equal(#diags, 1, "the diagnostic came back")
        T.assert_equal(diags[1].code, "MISSING_ACCEPT", "with its code")
        T.assert_equal(diags[1].node_id, "n_turnin", "and the node it blames")
    end)
end

function M.test_forget_makes_a_second_validate_actually_ask_again()
    with_mock_http(function()
        Mock.http.pending_ticks = 0
        Mock.set_http_response("/editor/campaigns/stw/validate", {})
        local ec = EditorClient:new("127.0.0.1", 3031)

        ec:validate("stw")
        T.assert_equal(#Mock.http.posts, 1, "asked once")
        ec:validate("stw")
        T.assert_equal(#Mock.http.posts, 1, "and the cached answer is reused")

        ec:forget("validate 'stw'")
        ec:validate("stw")
        T.assert_equal(#Mock.http.posts, 2,
            "validate is an ACTION: after an edit, clicking it again must ask the server again")
    end)
end

function M.test_compile_returns_the_editors_result_object()
    with_mock_http(function()
        Mock.http.pending_ticks = 0
        Mock.set_http_response("/editor/campaigns/stw/compile", {
            campaign_name = "stw", graph_count = 1, node_count = 4, edge_count = 3,
            message = "Campaign compile — full pipeline available in a later phase",
        })
        local ec = EditorClient:new("127.0.0.1", 3031)
        local result = ec:compile("stw")
        T.assert_not_nil(result, "the compile answered")
        T.assert_equal(result.node_count, 4, "carrying the counts the editor computed")
    end)
end

return M
