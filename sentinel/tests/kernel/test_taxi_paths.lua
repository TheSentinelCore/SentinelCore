-- tests/kernel/test_taxi_paths.lua
-- The flight-ROUTE catalog. taxi_nodes.lua answers "does this flight master exist"; without this
-- one nothing answers "are those two flight masters actually connected", so a questing.Flight task
-- could compile a plan that lands the character at a flight master with no route onward.
--
-- Generated from TaxiPath.dbc by sentinel/tools/regen_taxi_paths_catalog.py, alongside the JSON
-- mirror the Rust resolver reads. Both outputs come from one generator run, and
-- test_the_json_mirror_carries_the_same_edges below is what keeps that true.
--
-- WHAT THESE TESTS CANNOT SEE
--  * Whether the live client will actually accept a taxi hop for a given path id -- the injector's
--    taxi API is undocumented (VERIFY-IN-GAME), same caveat as test_taxi_nodes.lua.
--  * Multi-hop routing. TaxiPath is the DIRECT-edge table; chaining hops is the caller's job and
--    is deliberately not baked into the catalog.
--  * DBC-vs-catalog drift: only rerunning the generator sees the DBC. These tests pin the
--    committed catalog's shape and its agreement with taxi_nodes.lua.

local T = require("tests/test_util")
local TaxiPaths = require("kernel/catalogs/taxi_paths")
local TaxiNodes = require("kernel/catalogs/taxi_nodes")

local M = {}

function M.test_a_known_real_route_exists_in_both_directions()
    -- Stormwind <-> Ironforge is the route every Alliance character flies first. Resolving the
    -- endpoints through TaxiNodes rather than hardcoding 2 and 6 pins the two catalogs to each
    -- other: a renumbered node catalog must break here, not silently at runtime.
    local sw = TaxiNodes.resolve("stormwind", "alliance")
    local ironforge = TaxiNodes.resolve("ironforge", "alliance")
    T.assert_true(sw ~= nil and ironforge ~= nil, "the node catalog must know both endpoints")

    local path, cost = TaxiPaths.route(sw, ironforge)
    T.assert_true(path ~= nil, "Stormwind -> Ironforge must be a known flight route")
    T.assert_equal(cost, 50, "the Stormwind -> Ironforge fare from TaxiPath.dbc")

    local back, back_cost = TaxiPaths.route(ironforge, sw)
    T.assert_true(back ~= nil, "Ironforge -> Stormwind must be a known flight route")
    T.assert_equal(back_cost, 50, "the return fare from TaxiPath.dbc")
    T.assert_true(path ~= back, "each direction is its own TaxiPath row, so the ids must differ")
end

function M.test_a_route_that_does_not_exist_returns_nothing_not_an_error()
    -- Node 9 is the HORDE Booty Bay node; Stormwind is Alliance. It looks like a plausible
    -- destination and is not one, which is exactly the shape of request that must fail quietly
    -- rather than blow up inside a nil adjacency table.
    local sw = TaxiNodes.resolve("stormwind", "alliance")
    local horde_booty_bay = TaxiNodes.resolve("booty bay", "horde")
    local path, err = TaxiPaths.route(sw, horde_booty_bay)
    T.assert_true(path == nil and err == "no_route",
        "a missing edge must report no_route, got: " .. tostring(path or err))

    -- A source with no outgoing edges at all: the adjacency table for it does not exist, and
    -- indexing it is where a naive implementation raises instead of answering.
    local unknown_src, unknown_err = TaxiPaths.route(999999, sw)
    T.assert_true(unknown_src == nil and unknown_err == "no_route",
        "an unknown source must report no_route, got: " .. tostring(unknown_src or unknown_err))

    T.assert_true(TaxiPaths.route(nil, sw) == nil, "a nil source must not raise")
    T.assert_true(TaxiPaths.route(sw, nil) == nil, "a nil destination must not raise")
    T.assert_true(TaxiPaths.has_route(sw, horde_booty_bay) == false,
        "has_route must answer false, never nil, so callers can use it directly in a condition")
end

function M.test_every_endpoint_resolves_to_a_node_in_the_node_catalog()
    -- The whole point of the exclusion set: TaxiPath.dbc rows also describe boat/zeppelin
    -- pseudo-nodes, quest-scripted cinematic flights and dev-land targets, whose endpoints
    -- taxi_nodes.lua already dropped as usable by NEITHER faction. An edge pointing at one of
    -- those can never be named by a Flight task -- TaxiNodes.resolve cannot return that id -- so
    -- keeping it would let has_route answer true for a hop no flight master offers.
    local edges = 0
    for from, dests in pairs(TaxiPaths.edges) do
        T.assert_true(TaxiNodes.nodes[from] ~= nil,
            "edge source " .. tostring(from) .. " is absent from taxi_nodes.lua")
        for to, _ in pairs(dests) do
            T.assert_true(TaxiNodes.nodes[to] ~= nil,
                "edge destination " .. tostring(to) .. " is absent from taxi_nodes.lua")
            edges = edges + 1
        end
    end
    T.assert_equal(edges, 488, "the kept-edge count moved -- regenerate and re-read the report")
    T.assert_equal(TaxiPaths.excluded_edge_count, 26,
        "the dropped-edge count moved -- the exclusion rule changed meaning")
end

function M.test_no_edge_crosses_the_faction_line()
    -- A flight master only ever sells routes his own side can fly. An Alliance-only source with a
    -- Horde-only destination would mean the faction slots in taxi_nodes.lua were read wrong, and
    -- the first symptom in-game is a Flight task that silently never boards.
    for from, dests in pairs(TaxiPaths.edges) do
        local a = TaxiNodes.nodes[from]
        for to, _ in pairs(dests) do
            local b = TaxiNodes.nodes[to]
            T.assert_true((a.alliance and b.alliance) or (a.horde and b.horde),
                string.format("%s -> %s is flyable by neither faction", a.name, b.name))
        end
    end
end

function M.test_the_adjacency_is_keyed_by_destination_not_a_scannable_list()
    -- Structural, because the cost claim IS the structure: answering "is there a flight A -> B"
    -- must be two table indexes regardless of catalog size. A flat row list would make every
    -- Flight validation a 514-row scan, and the compiler validates every step of every guide.
    local sw = TaxiNodes.resolve("stormwind", "alliance")
    local ironforge = TaxiNodes.resolve("ironforge", "alliance")
    T.assert_equal(type(TaxiPaths.edges[sw]), "table", "each source must own an adjacency table")
    T.assert_true(rawget(TaxiPaths.edges[sw], ironforge) ~= nil,
        "the destination must be a KEY of the source's table, reachable without iteration")
    for from, dests in pairs(TaxiPaths.edges) do
        T.assert_equal(#dests, 0,
            "source " .. tostring(from) .. " holds a sequence -- that is a list to scan, not an index")
    end
end

function M.test_the_json_mirror_carries_the_same_edges()
    -- The Rust resolver validates Flight tasks against taxi_paths.json and cannot read a Lua
    -- table. One generator writes both files; this is the assertion that nobody hand-patched one
    -- of them, because a resolver that accepts a route the runtime cannot fly strands the bot.
    local f = io.open("sentinel/kernel/catalogs/taxi_paths.json", "r")
    T.assert_true(f ~= nil, "taxi_paths.json missing -- regenerate the catalog")
    local decoded = JSON.parse(f:read("*a"))
    f:close()

    local seen = 0
    for _, e in ipairs(decoded.edges) do
        local lua_edge = TaxiPaths.edges[e.from] and TaxiPaths.edges[e.from][e.to]
        T.assert_true(lua_edge ~= nil,
            string.format("JSON edge %d -> %d is missing from the Lua catalog", e.from, e.to))
        T.assert_equal(lua_edge.path, e.path, "path id disagrees between the two outputs")
        T.assert_equal(lua_edge.cost, e.cost, "cost disagrees between the two outputs")
        seen = seen + 1
    end
    T.assert_equal(seen, 488, "the JSON mirror carries a different number of edges than the Lua")
    T.assert_equal(#decoded.excluded, TaxiPaths.excluded_edge_count,
        "the JSON exclusion list and the Lua exclusion count disagree")
end

return M
