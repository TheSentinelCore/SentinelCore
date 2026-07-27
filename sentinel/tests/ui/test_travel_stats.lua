-- tests/ui/test_travel_stats.lua
-- The Travel Editor's waypoint capture and route estimate, and the Stats dashboard's counts
-- (spec: "Travel Editor and Stats Wiring", completing F12-R1/R2 and F20-R1/R2).
--
-- WHAT WAS BROKEN, AND WHY THE OLD SUITE WAS GREEN ANYWAY
-- ------------------------------------------------------
-- `travel_add_waypoint` answered `true, "(not yet implemented — requires player position)"`. Nothing
-- was captured, and the operator was told the capture had succeeded. `StatsDashboard:compute` was
-- never called by `IdePanels.install` at all, so the dashboard reported a campaign of zero nodes no
-- matter what was loaded. `TravelEditorState:load_from_campaign` had the same problem: real code with
-- no caller.
--
-- The old suite exercised both view-models DIRECTLY, so every case passed while the installed panels
-- reached neither. Every test here therefore drives the INSTALLED shell wherever the defect lived in
-- the wiring, and the view-model directly only where the defect lived in the decision.

local TravelEditorState = require("ui/panels/travel_editor_state")
local StatsDashboard = require("ui/panels/stats_dashboard")
local FakeWindow = require("tests/harness/fake_window")
local Mock = require("tests/harness/mocks/sylvannas_api")
local T = require("tests/test_util")

local M = {}

local BOUNDS = { x = 0, y = 0, w = 900, h = 600 }

-- ============================================================================
-- Fixtures and harness
-- ============================================================================

---A state holding one selected route with `n` map-tagged waypoints, ready to estimate.
local function route_with_waypoints(n, map)
    local te = TravelEditorState.new()
    te.activated = true
    te.campaign_name = "c"
    local waypoints = {}
    for i = 1, n do
        waypoints[i] = { x = i * 100, y = 0, z = 0, map = map or 0, movement = "walk" }
    end
    te.routes = { { id = "r1", from_node_id = "a", to_node_id = "b",
                    from_label = "Travel", to_label = "Travel", waypoints = waypoints } }
    te.selected_route = "r1"
    te.editing_waypoints = true
    return te
end

---Swap `core.get_map_id` for the duration of one call.
local function with_map_id(map_id, fn)
    local previous = _G.core.get_map_id
    _G.core.get_map_id = (map_id ~= nil) and function() return map_id end or nil
    local ok, err = pcall(fn)
    _G.core.get_map_id = previous
    if not ok then error(err, 0) end
end

---Swap the object manager for the duration of one call.
local function with_player_at(position, fn)
    local previous = _G.core.object_manager
    _G.core.object_manager = {
        get_local_player = function()
            if position == nil then return nil end
            return { get_position = function() return position end }
        end,
    }
    local ok, err = pcall(fn)
    _G.core.object_manager = previous
    if not ok then error(err, 0) end
end

local function installed_shell(deps)
    local Shell = require("ui/shell")
    local IdePanels = require("ui/ide_panels")
    local window = FakeWindow.new()
    local shell = Shell.new({ window = window, elements = nil })
    local bindings, reason = IdePanels.install(shell, deps or { questing = function() return nil end })
    T.assert_not_nil(bindings, "install must succeed: " .. tostring(reason))
    shell:show()
    return shell, bindings, window
end

-- ============================================================================
-- 1. Waypoint capture (F12-R1)
-- ============================================================================

function M.test_capture_records_the_position_it_was_handed()
    local te = route_with_waypoints(1)
    local ok, reason = te:add_waypoint({ x = -8940.5, y = -140.25, z = 84.75 }, 0)
    T.assert_true(ok, "a live position must be captured: " .. tostring(reason))

    local wps = te.routes[1].waypoints
    T.assert_equal(#wps, 2, "the capture appends to the selected route")
    T.assert_near(wps[2].x, -8940.5, 0.001, "x is stored verbatim, not rounded into the label")
    T.assert_near(wps[2].y, -140.25, 0.001)
    T.assert_near(wps[2].z, 84.75, 0.001)
    T.assert_equal(wps[2].map, 0, "and the map it was standing on")
    T.assert_true(wps[2].captured, "a captured waypoint is distinguishable from an imported one")
    T.assert_nil(te.error, "a successful capture leaves no error behind")
end

function M.test_capture_with_no_position_is_refused_and_says_so()
    -- Out of world: loading screen, between injections, dead object manager. The old code answered
    -- `true` here; a capture that substituted the origin would drop a waypoint in the middle of the
    -- map and report success.
    local te = route_with_waypoints(1)
    local ok, reason = te:add_waypoint(nil, 0)
    T.assert_false(ok, "no position is no waypoint")
    T.assert_not_nil(reason, "and the refusal must name the reason")
    T.assert_true(reason:find("not in world", 1, true) ~= nil, "reason: " .. tostring(reason))
    T.assert_equal(te.error, reason, "the panel says it on screen, not only to the caller")
    T.assert_equal(#te.routes[1].waypoints, 1, "and nothing was appended")
end

function M.test_capture_with_an_incomplete_position_is_refused()
    local te = route_with_waypoints(1)
    local ok, reason = te:add_waypoint({ x = 1, y = 2 }, 0)
    T.assert_false(ok, "a position missing z is not a position")
    T.assert_true(reason:find("incomplete", 1, true) ~= nil, "reason: " .. tostring(reason))
    T.assert_equal(#te.routes[1].waypoints, 1)
end

function M.test_capture_with_no_route_selected_is_refused()
    local te = route_with_waypoints(1)
    te.selected_route = nil
    local ok, reason = te:add_waypoint({ x = 1, y = 2, z = 3 }, 0)
    T.assert_false(ok, "there is nowhere to put it")
    T.assert_true(reason:find("no route selected", 1, true) ~= nil, "reason: " .. tostring(reason))
end

function M.test_a_missing_map_id_is_recorded_as_absent_not_as_map_zero()
    -- Map 0 is Eastern Kingdoms. Defaulting to it would price a leg in Outland as if it were in
    -- Elwynn, and the number would look computed.
    local te = route_with_waypoints(1)
    T.assert_true(te:add_waypoint({ x = 1, y = 2, z = 3 }, nil))
    T.assert_nil(te.routes[1].waypoints[2].map, "an unknown map reads as nil")
end

function M.test_capturing_drops_the_estimate_that_described_the_shorter_route()
    local te = route_with_waypoints(2)
    te.estimate = { route_id = "r1", segments = { { type = "walk", estimated_s = 10 } }, total_s = 10 }
    te.estimate_requested = true
    T.assert_true(te:add_waypoint({ x = 999, y = 0, z = 0 }, 0))
    T.assert_nil(te.estimate, "an estimate for two waypoints must not survive a third")
    T.assert_false(te.estimate_requested, "and the request is not silently re-run")
end

-- ============================================================================
-- 2. Waypoint capture through the INSTALLED shell (the wiring, not the model)
-- ============================================================================

function M.test_the_installed_capture_button_reaches_the_live_position()
    local shell, bindings = installed_shell()
    local travel = bindings.travel
    travel:toggle()
    travel.campaign_name = "c"
    travel.routes = { { id = "r1", from_label = "Travel", to_label = "Travel", waypoints = {} } }
    travel:select_route("r1")

    with_player_at({ x = -8940, y = -140, z = 84 }, function()
        with_map_id(0, function()
            shell:_queue_command("explorer", { kind = "travel_add_waypoint" })
            shell:on_tick()
        end)
    end)

    local wps = travel.routes[1].waypoints
    T.assert_equal(#wps, 1, "the dispatched command must have captured exactly one waypoint")
    T.assert_equal(wps[1].x, -8940, "at the position the object manager answered")
    T.assert_equal(wps[1].map, 0, "on the map core.get_map_id answered")
end

function M.test_the_installed_capture_reports_failure_rather_than_a_phantom_success()
    local shell, bindings = installed_shell()
    local travel = bindings.travel
    travel:toggle()
    travel.campaign_name = "c"
    travel.routes = { { id = "r1", from_label = "Travel", to_label = "Travel", waypoints = {} } }
    travel:select_route("r1")

    with_player_at(nil, function()
        with_map_id(0, function()
            shell:_queue_command("explorer", { kind = "travel_add_waypoint" })
            shell:on_tick()
        end)
    end)

    T.assert_equal(#travel.routes[1].waypoints, 0, "nothing may be captured out of world")
    T.assert_not_nil(travel.error, "and the panel must carry the reason")
    local record = shell:last_dispatch()
    T.assert_not_nil(record, "the shell must have recorded the dispatch")
    T.assert_false(record.ok,
        "the dispatch must report the failure, not a phantom success: " .. tostring(record.reason))
end

function M.test_no_source_claims_the_capture_is_unimplemented()
    -- The literal string that shipped. An audit, because the defect was a string that read as an
    -- answer.
    local handle = assert(io.open("sentinel/ui/ide_panels.lua", "r"))
    local source = handle:read("*a")
    handle:close()
    T.assert_nil(source:find("travel_add_waypoint (not yet implemented", 1, true),
        "the travel capture must not still announce itself as unimplemented")
end

-- ============================================================================
-- 3. Campaign-derived routes carry what the campaign carries, and no more
-- ============================================================================

---Two Travel nodes joined by one edge — the smallest campaign that yields a route.
local function two_node_campaign()
    return {
        name = "elwynn_1_12",
        nodes = {
            { id = "n1", type = "questing.Travel",
              intent = { x = -8940, y = -140, z = 84, destination = "Northshire" } },
            { id = "n2", type = "questing.Travel",
              intent = { x = -8900, y = -100, z = 82, destination = "Abbey" } },
        },
        edges = { { id = "e1", from = "n1", to = "n2" } },
    }
end

function M.test_a_campaign_travel_node_with_no_map_yields_a_waypoint_with_no_map()
    local te = TravelEditorState.new()
    local plan = two_node_campaign()
    T.assert_equal(te:load_from_campaign(plan.name, plan.nodes, plan.edges), 1,
        "one edge between two Travel nodes is one route")
    local wps = te.routes[1].waypoints
    T.assert_equal(#wps, 2, "both ends of the edge are Travel nodes")
    T.assert_nil(wps[1].map,
        "`questing.Travel`'s intent has no map field, and the waypoint must not invent one")
    T.assert_equal(wps[1].x, -8940, "the coordinates it does carry are read verbatim")
end

function M.test_a_travel_node_that_does_carry_a_map_has_it_read()
    local te = TravelEditorState.new()
    local plan = two_node_campaign()
    plan.nodes[1].intent.map = 530
    plan.nodes[2].intent.map = 530
    te:load_from_campaign(plan.name, plan.nodes, plan.edges)
    T.assert_equal(te.routes[1].waypoints[1].map, 530,
        "read, not fabricated: the field is honoured the moment the graph carries it")
end

function M.test_allow_flight_is_not_a_taxi_hop()
    -- `allow_flight` says the runtime may use its own flight form for a leg it would otherwise walk.
    -- Reporting it as a flight master's hop would price it at taxi speed against a route no flight
    -- master serves.
    local te = TravelEditorState.new()
    local plan = two_node_campaign()
    plan.nodes[2].intent.allow_flight = true
    te:load_from_campaign(plan.name, plan.nodes, plan.edges)
    T.assert_equal(te.routes[1].waypoints[2].movement, "flight",
        "the node's own flag is reported as flight")
    T.assert_nil(te.routes[1].waypoints[2].taxi_node, "and it resolves to no taxi node")
end

function M.test_a_flight_node_becomes_a_taxi_leg_named_by_its_destination()
    local te = TravelEditorState.new()
    local plan = two_node_campaign()
    plan.nodes[2] = { id = "n2", type = "questing.Flight",
                      intent = { npc_entry = 352, destination = "Ironforge, Dun Morogh" } }
    te:load_from_campaign(plan.name, plan.nodes, plan.edges)
    local wp = te.routes[1].waypoints[2]
    T.assert_equal(wp.movement, "taxi", "a Flight node IS a flight master's hop")
    T.assert_equal(wp.destination, "Ironforge, Dun Morogh")
    T.assert_equal(wp.x, 0, "a Flight node carries no coordinates of its own")
end

-- ============================================================================
-- 4. The `/travel/route` request (F12-R2)
-- ============================================================================

function M.test_a_route_of_one_waypoint_has_nothing_to_measure()
    local te = route_with_waypoints(1)
    local segments, reason = TravelEditorState.build_segments(te.routes[1])
    T.assert_nil(segments, "one point is not a leg")
    T.assert_true(reason:find("at least two waypoints", 1, true) ~= nil, tostring(reason))
end

function M.test_consecutive_waypoints_become_consecutive_walk_segments()
    local te = route_with_waypoints(3, 0)
    local segments = TravelEditorState.build_segments(te.routes[1])
    T.assert_not_nil(segments, "three waypoints are two legs")
    T.assert_equal(#segments, 2)
    T.assert_nil(segments[1].type, "a ground leg carries no type; the server defaults it to walk")
    T.assert_equal(segments[1].from.x, 100, "leg 1 runs from waypoint 1")
    T.assert_equal(segments[1].to.x, 200, "to waypoint 2")
    T.assert_equal(segments[2].from.x, 200, "and leg 2 continues from there")
    T.assert_equal(segments[1].from.map, 0, "each end names the map it is on")
end

function M.test_nothing_local_computes_a_distance_or_a_time()
    -- The whole point of POSTing the route: a number produced here and rendered next to the
    -- server's would be indistinguishable from one the server returned.
    local te = route_with_waypoints(3, 0)
    local segments = TravelEditorState.build_segments(te.routes[1])
    for i, seg in ipairs(segments) do
        T.assert_nil(seg.distance_m, "segment " .. i .. " must not carry a locally measured distance")
        T.assert_nil(seg.estimated_s, "segment " .. i .. " must not carry a locally computed time")
    end
end

function M.test_a_waypoint_with_no_map_is_refused_rather_than_filed_on_map_zero()
    local te = route_with_waypoints(2, 0)
    te.routes[1].waypoints[2].map = nil
    local segments, reason = TravelEditorState.build_segments(te.routes[1])
    T.assert_nil(segments, "map 0 is Eastern Kingdoms, not 'unknown'")
    T.assert_true(reason:find("waypoint 2 carries no map id", 1, true) ~= nil, tostring(reason))
end

function M.test_a_resolved_flight_destination_becomes_a_taxi_segment_at_the_nodes_position()
    local TaxiNodes = require("kernel/catalogs/taxi_nodes")
    local te = route_with_waypoints(1, 0)
    table.insert(te.routes[1].waypoints,
        { movement = "taxi", destination = "Ironforge, Dun Morogh", x = 0, y = 0, z = 0 })

    local segments, reason = TravelEditorState.build_segments(te.routes[1])
    T.assert_not_nil(segments, "a resolvable destination is a measurable hop: " .. tostring(reason))
    T.assert_equal(segments[1].type, "taxi", "and it is labelled as one")

    local expected = TaxiNodes.nodes[TaxiNodes.resolve("Ironforge, Dun Morogh")]
    T.assert_equal(segments[1].to.map, expected.map,
        "the taxi node's own position is what the server is given")
    T.assert_near(segments[1].to.x, expected.x, 0.01)
    T.assert_equal(segments[1].to_node, TaxiNodes.resolve("Ironforge, Dun Morogh"),
        "the node id travels with it so the server's refusal can name it")
end

function M.test_an_unresolvable_flight_destination_is_reported_not_guessed()
    -- The server has NO taxi tables: `/travel/route` refuses a taxi segment that arrives without
    -- positions rather than inventing a per-hop constant. Supplying a made-up position here would
    -- move that invention one layer up and hide it.
    local te = route_with_waypoints(1, 0)
    table.insert(te.routes[1].waypoints,
        { movement = "taxi", destination = "Nowhere In Particular", x = 0, y = 0, z = 0 })

    local segments, reason = TravelEditorState.build_segments(te.routes[1])
    T.assert_nil(segments, "an unknown flight master is not a hop we may price")
    T.assert_true(reason:find("Nowhere In Particular", 1, true) ~= nil,
        "the refusal must name the destination: " .. tostring(reason))
    T.assert_true(reason:find("unknown_destination", 1, true) ~= nil, tostring(reason))
end

function M.test_a_faction_ambiguous_destination_is_refused_until_a_faction_is_given()
    -- "arathi" is Refuge Pointe (Alliance) or Hammerfall (Horde). Silently picking one flies the
    -- character across a continent on a guess.
    local te = route_with_waypoints(1, 0)
    table.insert(te.routes[1].waypoints,
        { movement = "taxi", destination = "arathi", x = 0, y = 0, z = 0 })

    local segments, reason = TravelEditorState.build_segments(te.routes[1])
    T.assert_nil(segments, "a faction-complement pair is not a resolution")
    T.assert_true(reason:find("needs_faction", 1, true) ~= nil, tostring(reason))

    local resolved = TravelEditorState.build_segments(te.routes[1], "Alliance")
    T.assert_not_nil(resolved, "and the same route resolves once the faction is known")
    T.assert_equal(resolved[1].type, "taxi")
end

function M.test_the_request_key_changes_with_the_route_and_not_otherwise()
    local te = route_with_waypoints(3, 0)
    local first = TravelEditorState.request_key(TravelEditorState.build_segments(te.routes[1]))
    local again = TravelEditorState.request_key(TravelEditorState.build_segments(te.routes[1]))
    T.assert_equal(first, again, "an unchanged route must not be re-requested every tick")

    te.routes[1].waypoints[3].x = 999
    local moved = TravelEditorState.request_key(TravelEditorState.build_segments(te.routes[1]))
    T.assert_true(moved ~= first, "a moved waypoint must not be answered from the old cache")
end

-- ============================================================================
-- 5. Asking the server, and living with its answer
-- ============================================================================

local QueryClient = require("shared/query_client")

---A route estimate answered exactly as `/travel/route` answers it.
local ROUTE_OK = {
    segments = {
        { type = "walk", distance_m = 140.0, estimated_s = 20 },
        { type = "taxi", distance_m = 3200.0, estimated_s = 100 },
    },
    total_s = 120,
}

---Run `fn` against the harness's async `core.http_get`/`core.http_post`, exactly as the injector
---presents them: the callback lands `pending_ticks` harness ticks after the call, never inside it.
local function with_http(fn)
    local saved = _G.core
    Mock.setup_globals()
    Mock.reset_http()
    local ok, err = pcall(fn)
    Mock.reset_http()
    _G.core = saved
    if not ok then error(err, 0) end
end

function M.test_a_pending_estimate_re_arms_the_panel_and_the_next_tick_collects_it()
    with_http(function()
        Mock.set_http_response("/travel/route", ROUTE_OK)
        local te = route_with_waypoints(3, 0)
        te:request_estimate()
        local client = QueryClient:new()

        te._dirty = false
        T.assert_equal(te:poll_estimate(client), "pending",
            "the first poll fires the request and has nothing yet")
        T.assert_true(te._dirty,
            "a pending answer must re-arm the panel or the tick that collects it never runs")
        T.assert_true(te.loading, "and the operator must be told something is in flight")
        T.assert_nil(te.estimate, "with no number on screen until there is one")

        Mock.http_advance(2)
        T.assert_equal(te:poll_estimate(client), "ok", "the answer lands and is collected")
        T.assert_equal(te.estimate.total_s, 120, "the server's total, verbatim")
        T.assert_equal(#te.estimate.segments, 2)
        T.assert_equal(te.estimate.segments[2].type, "taxi")
        T.assert_false(te.estimate_requested, "and the request is not repeated")
    end)
end

function M.test_the_posted_body_is_the_route_the_operator_can_see()
    with_http(function()
        Mock.set_http_response("/travel/route", ROUTE_OK)
        local te = route_with_waypoints(3, 0)
        te:request_estimate()
        te:poll_estimate(QueryClient:new())

        local body = Mock.last_post_body()
        T.assert_not_nil(body, "the estimate must actually POST")
        T.assert_equal(#body.segments, 2, "three waypoints are two legs")
        T.assert_equal(body.segments[1].from.x, 100, "and the legs are the ones on screen")
        T.assert_equal(body.segments[1].to.x, 200)
        T.assert_equal(Mock.http.posts[1].url, "http://127.0.0.1:3030/travel/route",
            "posted to the endpoint the spec names")
    end)
end

function M.test_a_server_refusal_is_reported_in_the_servers_own_words()
    -- The taxi gap: `/travel/route` refuses a segment it cannot place and names it. Replacing that
    -- with "estimate failed" would make a documented refusal read as a network glitch.
    with_http(function()
        Mock.set_http_response("/travel/route",
            '{"error":"segment 1: a taxi segment needs from/to positions for its nodes"}', 400)
        local te = route_with_waypoints(2, 0)
        te:request_estimate()
        local client = QueryClient:new()
        te:poll_estimate(client)
        Mock.http_advance(2)
        T.assert_equal(te:poll_estimate(client), "failed")

        T.assert_nil(te.estimate, "a refused route has no total")
        T.assert_true(te.error:find("segment 1", 1, true) ~= nil,
            "the server's own words must reach the panel: " .. tostring(te.error))
        T.assert_true(te.error:find("400", 1, true) ~= nil, tostring(te.error))
    end)
end

function M.test_an_unroutable_url_fails_rather_than_hanging()
    with_http(function()
        -- No route registered: the harness resolves 404, as a dead endpoint does.
        local te = route_with_waypoints(2, 0)
        te:request_estimate()
        local client = QueryClient:new()
        te:poll_estimate(client)
        Mock.http_advance(2)
        T.assert_equal(te:poll_estimate(client), "failed")
        T.assert_true(te.error:find("404", 1, true) ~= nil, tostring(te.error))
    end)
end

function M.test_no_query_server_is_said_out_loud_rather_than_estimated_anyway()
    local te = route_with_waypoints(2, 0)
    te:request_estimate()
    T.assert_equal(te:poll_estimate(nil), "failed")
    T.assert_nil(te.estimate)
    T.assert_true(te.error:find("no query server", 1, true) ~= nil, tostring(te.error))
end

function M.test_an_unmeasurable_route_never_reaches_the_wire()
    with_http(function()
        Mock.set_http_response("/travel/route", ROUTE_OK)
        local te = route_with_waypoints(2, 0)
        te.routes[1].waypoints[2].map = nil
        te:request_estimate()
        T.assert_equal(te:poll_estimate(QueryClient:new()), "failed")
        T.assert_equal(#Mock.http.posts, 0,
            "a request we know the server must refuse is not worth sending")
        T.assert_true(te.error:find("no map id", 1, true) ~= nil, tostring(te.error))
    end)
end

function M.test_an_unchanged_route_is_not_re_requested_every_tick()
    with_http(function()
        Mock.set_http_response("/travel/route", ROUTE_OK)
        local te = route_with_waypoints(3, 0)
        te:request_estimate()
        local client = QueryClient:new()
        te:poll_estimate(client)
        te:poll_estimate(client)
        te:poll_estimate(client)
        T.assert_equal(#Mock.http.posts, 1, "one route, one request")
    end)
end

-- ============================================================================
-- 6. The estimate on screen
-- ============================================================================

function M.test_the_plan_shows_one_row_per_server_segment_and_their_total()
    local te = route_with_waypoints(3, 0)
    te.estimate = { route_id = "r1", segments = ROUTE_OK.segments, total_s = ROUTE_OK.total_s }
    local plan = TravelEditorState.build_plan(te:build(), BOUNDS)

    local text = {}
    for _, item in ipairs(plan.items) do
        if item.kind == "text" then text[#text + 1] = item.text end
    end
    local joined = table.concat(text, "\n")
    T.assert_true(joined:find("20s", 1, true) ~= nil, "the walk leg's time: " .. joined)
    T.assert_true(joined:find("1m 40s", 1, true) ~= nil, "the taxi leg's time: " .. joined)
    T.assert_true(joined:find("Total  2m 00s", 1, true) ~= nil, "and their total: " .. joined)
    T.assert_true(joined:find("taxi", 1, true) ~= nil, "each row names its own kind")
end

function M.test_no_estimate_paints_no_numbers_at_all()
    local te = route_with_waypoints(3, 0)
    local plan = TravelEditorState.build_plan(te:build(), BOUNDS)
    for _, item in ipairs(plan.items) do
        if item.kind == "text" then
            T.assert_nil(item.text:find("Total", 1, true),
                "a total with nothing behind it is the defect this change removes")
        end
    end
end

function M.test_a_refusal_is_painted_not_only_stored()
    local te = route_with_waypoints(2, 0)
    te.activated = true
    te.error = "travel estimate unavailable: no query server"
    local plan = TravelEditorState.build_plan(te:build(), BOUNDS)
    local found = false
    for _, item in ipairs(plan.items) do
        if item.kind == "text" and item.text:find("no query server", 1, true) then found = true end
    end
    T.assert_true(found, "the panel must show what it refused")
end

function M.test_every_control_the_plan_emits_reduces_to_a_command()
    -- Two Properties controls shipped unreachable by construction: `reduce` understood ids that
    -- `build_plan` never pushed. Asserting `#items > 0` would not have caught either.
    local te = route_with_waypoints(3, 0)
    te.activated = true
    te.editing_waypoints = true
    te.estimate = { route_id = "r1", segments = ROUTE_OK.segments, total_s = 120 }
    local plan = TravelEditorState.build_plan(te:build(), BOUNDS)

    local ids = 0
    for _, item in ipairs(plan.items) do
        if item.id then
            ids = ids + 1
            T.assert_not_nil(TravelEditorState.reduce(item.id),
                "control '" .. item.id .. "' is painted and reduces to nothing")
        end
    end
    T.assert_true(ids >= 5, "the editor must actually paint its controls, saw " .. ids)
end

function M.test_the_estimate_button_is_one_of_them()
    local te = route_with_waypoints(3, 0)
    te.activated = true
    te.editing_waypoints = true
    local plan = TravelEditorState.build_plan(te:build(), BOUNDS)
    local seen = false
    for _, item in ipairs(plan.items) do
        if item.id == "travel_estimate" then seen = true end
    end
    T.assert_true(seen, "there must be a control that asks for the estimate")
    T.assert_equal(TravelEditorState.reduce("travel_estimate").kind, "travel_estimate")
end

-- ============================================================================
-- 7. The estimate through the INSTALLED shell
-- ============================================================================

function M.test_the_installed_estimate_button_reaches_the_query_server()
    with_http(function()
        Mock.set_http_response("/travel/route", ROUTE_OK)
        local shell, bindings = installed_shell({
            questing = function() return nil end,
            query_client = QueryClient:new(),
        })
        local travel = bindings.travel
        travel:toggle()
        travel.campaign_name = "c"
        travel.routes = { { id = "r1", from_label = "Travel", to_label = "Travel", waypoints = {
            { x = 0, y = 0, z = 0, map = 0, movement = "walk" },
            { x = 140, y = 0, z = 0, map = 0, movement = "walk" },
        } } }
        travel:select_route("r1")

        shell:activate("explorer")
        shell:_queue_command("explorer", { kind = "travel_estimate" })
        shell:on_tick()
        T.assert_equal(#Mock.http.posts, 1, "the tick after the click must post the route")

        Mock.http_advance(2)
        shell:on_tick()
        T.assert_not_nil(travel.estimate, "and the tick after that must collect the answer")
        T.assert_equal(travel.estimate.total_s, 120)
    end)
end

-- ============================================================================
-- 8. The stats badges (F20-R1/R2)
-- ============================================================================

---A campaign holding one of each thing a badge counts, plus a duplicate of each.
local function badge_campaign()
    return {
        name = "elwynn_full",
        nodes = {
            { id = "n1", type = "questing.AcceptQuest", intent = { quest_id = 33, npc_entry = 197 } },
            { id = "n2", type = "questing.TurnInQuest", intent = { quest_id = 33, npc_entry = 197 } },
            { id = "n3", type = "questing.AcceptQuest", intent = { quest_id = 76, npc_entry = 240 } },
            { id = "n4", type = "questing.Travel",      intent = { x = 1, y = 2, z = 3 } },
            { id = "n5", type = "questing.Travel",      intent = { x = 4, y = 5, z = 6 } },
            { id = "n6", type = "questing.Vendor",      intent = { npc_entry = 1263 } },
            { id = "n7", type = "questing.Flight",      intent = { npc_entry = 352, destination = "Ironforge, Dun Morogh" } },
            { id = "n8", type = "questing.UseItem",     intent = { item = 5, target_entry = 3000 } },
            { id = "n9", type = "questing.Loot",        intent = { object_entry = 3000, item_id = 5 } },
            { id = "n10", type = "questing.Kill",       intent = { creature_entry = 299, count = 12 } },
            { id = "n11", type = "questing.LearnFlightPath", intent = { npc_entry = 352 } },
        },
        edges = { { id = "e1", from = "n1", to = "n2" } },
    }
end

function M.test_the_badges_count_what_the_graph_holds()
    local sd = StatsDashboard.new()
    sd:compute(badge_campaign())
    local s = sd.stats
    T.assert_equal(s.quest_count, 2,
        "quest 33 has an Accept AND a TurnIn; counting nodes would report it twice")
    T.assert_equal(s.waypoint_count, 2, "two Travel nodes with coordinates")
    T.assert_equal(s.npc_count, 4,
        "197, 240, 1263 and 352 — 352 appears twice and is one NPC")
    T.assert_equal(s.object_count, 1,
        "UseItem's target and Loot's object are the same game object")
    T.assert_equal(s.vendor_count, 1, "only the Vendor node's npc_entry is a vendor")
    T.assert_equal(s.flight_count, 1,
        "LearnFlightPath buys a node and takes no flight, so it is not a flight")
end

function M.test_a_kill_target_is_not_counted_as_an_npc_to_visit()
    -- A grind of forty wolves is not forty NPCs. `creature_entry` and `npc_entry` are different
    -- axes and folding them together makes the badge useless for planning.
    local sd = StatsDashboard.new()
    sd:compute({ name = "grind", nodes = {
        { id = "k1", type = "questing.Kill", intent = { creature_entry = 299, count = 40 } },
    }, edges = {} })
    T.assert_equal(sd.stats.npc_count, 0, "a kill target is not someone the route talks to")
    T.assert_equal(sd.stats.total_kills, 40, "the kill count itself is unaffected")
end

function M.test_an_unfilled_intent_field_is_not_an_entity()
    -- `default_intent` seeds every entry field to 0. A freshly added node is an unfilled form and
    -- counting it would report a campaign that visits an NPC nobody chose.
    local sd = StatsDashboard.new()
    sd:compute({ name = "fresh", nodes = {
        { id = "n1", type = "questing.Vendor", intent = { npc_entry = 0 } },
        { id = "n2", type = "questing.AcceptQuest", intent = { quest_id = 0, npc_entry = 0 } },
    }, edges = {} })
    T.assert_equal(sd.stats.npc_count, 0)
    T.assert_equal(sd.stats.quest_count, 0)
    T.assert_equal(sd.stats.vendor_count, 0)
    T.assert_equal(sd.stats.total_nodes, 2, "the nodes themselves are still counted")
end

function M.test_a_zero_badge_is_shown_rather_than_dropped()
    local badges = StatsDashboard.badges({})
    T.assert_equal(#badges, 6, "all six counts are always present")
    for _, badge in ipairs(badges) do
        T.assert_equal(badge.count, 0, badge.label .. " defaults to zero")
    end
end

function M.test_the_badges_are_painted_as_chips_carrying_their_counts()
    local sd = StatsDashboard.new()
    sd:compute(badge_campaign())
    sd.visible = true
    local plan = StatsDashboard.build_plan(sd:build(), BOUNDS)

    local chips = {}
    for _, item in ipairs(plan.items) do
        if item.kind == "chip" then chips[item.id] = item.label end
    end
    T.assert_equal(chips["stats_badge_quests"], "Quests 2", "the chip carries the number")
    T.assert_equal(chips["stats_badge_npcs"], "NPCs 4")
    T.assert_equal(chips["stats_badge_vendors"], "Vendors 1")
    T.assert_equal(chips["stats_badge_flights"], "Flights 1")

    local window = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(StatsDashboard.render, window, plan)
    T.assert_true(ok, "the chips must paint through the type-checking fake window: " .. tostring(err))
end

-- ============================================================================
-- 9. The campaign reaching both extensions through the INSTALLED shell
-- ============================================================================

function M.test_editing_the_graph_recomputes_the_badges()
    -- Neither `compute` nor `load_from_campaign` had a caller. The dashboard reported a campaign of
    -- zero nodes whatever was loaded, and every test that proved otherwise called it directly.
    local shell, bindings = installed_shell()
    local graph = bindings.graph:state()
    local plan = badge_campaign()
    graph.campaign_name = plan.name
    graph.nodes = plan.nodes
    graph.edges = plan.edges
    graph._dirty = true

    shell:activate("graph")
    shell:on_tick()

    T.assert_equal(bindings.stats.stats.quest_count, 2,
        "the installed dashboard must see the loaded campaign")
    T.assert_equal(bindings.stats.campaign_name, plan.name)
end

function M.test_editing_the_graph_reloads_the_travel_routes()
    local shell, bindings = installed_shell()
    local graph = bindings.graph:state()
    graph.campaign_name = "c"
    graph.nodes = {
        { id = "n1", type = "questing.Travel", intent = { x = 1, y = 2, z = 3, map = 0 } },
        { id = "n2", type = "questing.Travel", intent = { x = 4, y = 5, z = 6, map = 0 } },
    }
    graph.edges = { { id = "e1", from = "n1", to = "n2" } }
    graph._dirty = true

    shell:activate("graph")
    shell:on_tick()

    T.assert_equal(#bindings.travel.routes, 1,
        "the installed travel editor must see the campaign's Travel nodes")
    T.assert_equal(bindings.travel.campaign_name, "c")
end

function M.test_an_unchanged_graph_does_not_recompute()
    local shell, bindings = installed_shell()
    local graph = bindings.graph:state()
    graph.campaign_name = "c"
    graph.nodes = { { id = "n1", type = "questing.Vendor", intent = { npc_entry = 1263 } } }
    graph.edges = {}
    graph._dirty = false

    shell:activate("graph")
    shell:on_tick()
    T.assert_equal(bindings.stats.stats.vendor_count, 0,
        "a tick with nothing to do must not walk the whole graph")
end

-- ============================================================================
-- 10. Structural guards
-- ============================================================================

function M.test_the_capture_never_reads_the_object_manager_from_the_state()
    -- The state is handed a position; it must not go looking for one. An object-manager read from a
    -- view-model would be reachable from a render frame, which ADR 09b §2.4 forbids.
    local handle = assert(io.open("sentinel/ui/panels/travel_editor_state.lua", "r"))
    local source = handle:read("*a")
    handle:close()
    source = source:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\n]*", " ")
    for _, forbidden in ipairs({ "object_manager", "get_local_player", "get_map_id" }) do
        T.assert_nil(source:find(forbidden, 1, true),
            "travel_editor_state reaches for " .. forbidden .. "; the host must hand it over")
    end
end

function M.test_the_state_loads_with_no_sdk_at_all()
    local names = { "ui/panels/travel_editor_state", "ui/panels/stats_dashboard" }
    local saved_core, saved_loaded = _G.core, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    _G.core = nil
    local errs = {}
    for _, name in ipairs(names) do
        local ok, err = pcall(require, name)
        if not ok then errs[#errs + 1] = name .. ": " .. tostring(err) end
    end
    _G.core = saved_core
    for _, name in ipairs(names) do package.loaded[name] = saved_loaded[name] end
    T.assert_equal(#errs, 0, "loaded with no SDK: " .. table.concat(errs, "; "))
end

function M.test_the_fake_window_still_paints_the_editor()
    local te = route_with_waypoints(2)
    local TravelEditor = require("ui/panels/travel_editor")
    local window = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(TravelEditor.render, window, BOUNDS, te:build())
    T.assert_true(ok, "the editor must paint through the type-checking fake window: " .. tostring(err))
    T.assert_not_nil(Mock, "the harness mock is loaded so http routes can be registered")
end

return M
