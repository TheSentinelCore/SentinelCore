-- tests/kernel/test_taxi_nodes.lua
-- The flight-node catalog: the name->node lookup ADR 07 §9 item 3 said did not exist.
--
-- Generated from TaxiNodes.dbc by sentinel/tools/regen_taxi_nodes_catalog.py. A wrong resolution
-- here is not an error message — it is a character flying across a continent — so the catalog
-- refuses everything it cannot answer uniquely: unknown names, real ambiguities (Feralas has two
-- Alliance nodes), and faction pairs when no faction is supplied.
--
-- WHAT THESE TESTS CANNOT SEE
--  * Whether `core.input.take_taxi` exists, or what node ids the live client actually accepts —
--    the ids here are the DBC's, and the injector's taxi API is undocumented (VERIFY-IN-GAME).
--  * Whether `get_race_id()` really returns ChrRaces ids (shared/race_faction.lua's caveat).
--  * DBC-vs-catalog drift: only the generator's --check mode sees the DBC; these tests pin the
--    committed catalog against the corpus, not against the DBC.

local T = require("tests/test_util")
local TaxiNodes = require("kernel/catalogs/taxi_nodes")
local RaceFaction = require("shared/race_faction")

local M = {}

function M.test_faction_slots_were_not_guessed()
    -- Stormwind is Alliance-only and Orgrimmar Horde-only; if the generator's empirical slot
    -- detection ever inverts, both of these flip and every faction filter in the file lies.
    local sw = TaxiNodes.resolve("stormwind", "alliance")
    T.assert_true(sw ~= nil, "Stormwind must resolve for alliance")
    T.assert_true(TaxiNodes.resolve("stormwind", "horde") == nil, "Stormwind must NOT resolve for horde")
    local og = TaxiNodes.resolve("orgrimmar", "horde")
    T.assert_true(og ~= nil, "Orgrimmar must resolve for horde")
    T.assert_true(TaxiNodes.resolve("orgrimmar", "alliance") == nil, "Orgrimmar must NOT resolve for alliance")
end

function M.test_a_faction_pair_needs_a_faction_and_is_unique_per_side()
    -- "Gadgetzan, Tanaris" exists once per side. Faction-free must refuse with the SPECIFIC
    -- reason; each side must then resolve uniquely — and to DIFFERENT nodes.
    local id, err = TaxiNodes.resolve("tanaris", nil)
    T.assert_true(id == nil and err == "needs_faction",
        "a faction pair without a faction must say needs_faction, got: " .. tostring(err))
    local a = TaxiNodes.resolve("tanaris", "alliance")
    local h = TaxiNodes.resolve("tanaris", "horde")
    T.assert_true(a ~= nil and h ~= nil and a ~= h,
        string.format("each side must resolve uniquely to its own node, got A=%s H=%s",
            tostring(a), tostring(h)))
end

function M.test_a_real_ambiguity_fails_loud_even_with_a_faction()
    -- Feralas has TWO Alliance nodes (Thalanaar and Feathermoon). No rule can pick for the
    -- author; a silent tie-break is a cross-continent flight.
    local id, err = TaxiNodes.resolve("feralas", "alliance")
    T.assert_true(id == nil and err == "ambiguous_destination",
        "two same-faction candidates must be ambiguous, got: " .. tostring(id or err))
end

function M.test_an_unknown_destination_is_refused_not_fuzzy_matched()
    local id, err = TaxiNodes.resolve("gadgetzan bazaar", "alliance")
    T.assert_true(id == nil and err == "unknown_destination",
        "a near-miss must NOT fuzzy-match, got: " .. tostring(id or err))
end

function M.test_the_shatter_point_pin_avoids_the_beach_assault_event_node()
    local id = TaxiNodes.resolve("shatter point", "alliance")
    T.assert_equal(TaxiNodes.nodes[id].name, "Shatter Point, Hellfire Peninsula",
        "the curated pin must select the flight master, not the '(Beach Assault)' event node")
end

function M.test_race_to_faction_never_guesses()
    T.assert_equal(RaceFaction.resolve(1), "alliance", "Human")
    T.assert_equal(RaceFaction.resolve(6), "horde", "Tauren")
    T.assert_equal(RaceFaction.resolve(11), "alliance", "Draenei")
    T.assert_equal(RaceFaction.resolve(9), nil, "9 is unused in 2.4.3 and must be nil, not a side")
    T.assert_equal(RaceFaction.resolve(nil), nil, "no race id means no faction, never a default")
end

--- The corpus census, pinned. 738 `.fly` uses across the 7 guides: 615 resolve with no faction,
--- 98 name a faction-paired town (all resolvable once a faction is known), 25 are genuinely
--- ambiguous (Booty Bay's duplicate Horde DBC node, Feralas/Felwood/Ashenvale), and — the number
--- this catalog exists for — ZERO are unknown. Regenerating the catalog or editing the curated
--- alias table must not silently change any of these buckets.
function M.test_the_corpus_census_buckets_hold()
    local counts = { resolved = 0, needs_faction = 0, ambiguous = 0, unknown = 0 }
    local f = io.open("sentinel/tests/fixtures/fly_destinations_census.txt", "r")
    T.assert_true(f ~= nil, "census fixture missing — regenerate from the corpus")
    for line in f:lines() do
        local count, dest = line:match("^%s*(%d+)%s+(.+)$")
        if dest then
            dest = dest:gsub("%s*<<.*$", ""):gsub("%s*%-%-.*$", ""):gsub("%s+$", "")
            local id, err = TaxiNodes.resolve(dest, nil)
            local bucket = id and "resolved" or err
            if bucket == "needs_faction" then
                -- The stronger claim: every pair resolves uniquely under BOTH factions.
                local a = TaxiNodes.resolve(dest, "alliance")
                local h = TaxiNodes.resolve(dest, "horde")
                T.assert_true(a ~= nil and h ~= nil,
                    dest .. " must resolve under each faction, got A=" .. tostring(a) .. " H=" .. tostring(h))
            end
            counts[bucket == "resolved" and "resolved"
                or bucket == "needs_faction" and "needs_faction"
                or bucket == "ambiguous_destination" and "ambiguous"
                or "unknown"] = (counts[bucket == "resolved" and "resolved"
                or bucket == "needs_faction" and "needs_faction"
                or bucket == "ambiguous_destination" and "ambiguous"
                or "unknown"] or 0) + tonumber(count)
        end
    end
    f:close()
    T.assert_equal(counts.resolved, 615, "resolved bucket moved")
    T.assert_equal(counts.needs_faction, 98, "needs_faction bucket moved")
    T.assert_equal(counts.ambiguous, 25, "ambiguous bucket moved")
    T.assert_equal(counts.unknown, 0,
        "an UNKNOWN flight destination appeared — the catalog exists so this is always zero")
end

return M
