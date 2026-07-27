-- tests/kernel/test_zone_catalog.lua
-- The zone catalog and the spawn->zone index, generated together by
-- sentinel/tools/regen_zone_catalog.py from AreaTable.dbc, Map.dbc and the maps/*.map area grids.
--
-- WHY A CATALOG AT ALL. `creature` carries map + position and no zone, and `creature_zone` has
-- zero rows, so "what lives in this zone" has no answer in SQL. It has one in the client data, and
-- the derivation is deterministic, so it is done once by the generator and committed -- the same
-- bargain taxi_nodes.lua and taxi_paths.lua strike with their DBCs.
--
-- Three outputs come out of ONE generator run: zones.lua (this file's subject), zones.json (the
-- Rust QueryServer, which cannot read a Lua table) and spawn_zones.json (the index
-- GET /zone/{id}/spawns aggregates). test_the_json_mirror_carries_the_same_areas below is what
-- keeps the first two from being patched apart.
--
-- WHAT THESE TESTS CANNOT SEE
--  * DBC/terrain-vs-catalog drift: only rerunning the generator opens the client files. These
--    tests pin the committed catalogs' shape and their agreement with each other.
--  * Whether a zone id is the one the live client reports for a position. The derivation is
--    restated from the mangos source in the generator's header; agreement with the running server
--    is VERIFY-IN-GAME, same caveat as the taxi catalogs.

local T = require("tests/test_util")
local Zones = require("kernel/catalogs/zones")

local M = {}

local function read_json(path)
    local f = io.open(path, "r")
    T.assert_true(f ~= nil, path .. " missing -- regenerate the catalog")
    local body = f:read("*a")
    f:close()
    return JSON.parse(body)
end

function M.test_an_area_and_its_zone_both_resolve()
    -- Northshire Valley is the case the whole "areas, not just zones" decision exists for: quest
    -- and spawn data name it constantly, it is NOT a top-level zone, and a zones-only table would
    -- answer "" for it. Elwynn Forest is its parent and is its own zone.
    T.assert_equal(Zones.name(9), "Northshire Valley")
    T.assert_equal(Zones.name(12), "Elwynn Forest")
    T.assert_equal(Zones.zone_of(9), 12, "a sub-area collapses to its parent zone")
    T.assert_equal(Zones.zone_of(12), 12, "a top-level zone collapses to itself")
    T.assert_equal(Zones.name(3483), "Hellfire Peninsula", "the catalog covers Outland, not just 1.12")
end

function M.test_an_unknown_id_answers_empty_rather_than_raising()
    -- `quest_template.ZoneOrSort` is overloaded -- a non-positive value is a sort bucket with no
    -- area behind it -- so asking about an id that is not a zone is an ordinary request, not a
    -- defect. A nil return would make every panel concatenation a guarded one.
    T.assert_equal(Zones.name(99999999), "", "an unknown id must name nothing, not raise")
    T.assert_equal(Zones.name(nil), "", "a nil id must not raise")
    T.assert_equal(Zones.name(-263), "", "a negative sort bucket is not a zone")
    T.assert_true(Zones.zone_of(99999999) == nil, "an unknown id has no zone")
    T.assert_true(Zones.zone_of(nil) == nil, "a nil id must not raise")
    T.assert_true(Zones.resolve(nil) == nil, "a nil name must not raise")
end

function M.test_a_name_resolves_case_insensitively_and_prefers_the_zone()
    T.assert_equal(Zones.resolve("Elwynn Forest"), 12)
    T.assert_equal(Zones.resolve("elwynn forest"), 12, "lookup is case-insensitive")
    T.assert_equal(Zones.resolve("ELWYNN FOREST"), 12)
    T.assert_true(Zones.resolve("not a real place") == nil)

    -- Names are not unique: 4095 and 4131 are both "Magisters' Terrace", the outdoor area and the
    -- instance. 4131 is the top-level zone, so it wins -- deterministically, not by whichever row
    -- the hash walk reached first.
    T.assert_equal(Zones.resolve("magisters' terrace"), 4131,
        "a name shared by an area and a zone must resolve to the zone")
end

function M.test_the_hierarchy_is_closed_and_the_zone_list_agrees_with_it()
    -- A parent pointing at an id the catalog does not carry means zone_of hands callers a zone
    -- that cannot be named, and GET /zone/{id}/spawns 404s on data the index says exists.
    local areas, tops = 0, 0
    for id, area in pairs(Zones.areas) do
        areas = areas + 1
        T.assert_equal(type(area.name), "string", "area " .. tostring(id) .. " has no name")
        if area.parent ~= 0 then
            T.assert_true(Zones.areas[area.parent] ~= nil,
                string.format("area %d names parent %d, which is absent", id, area.parent))
        else
            tops = tops + 1
        end
    end
    T.assert_equal(areas, 1643, "the AreaTable row count moved -- regenerated against another client")
    T.assert_equal(tops, #Zones.zone_ids(), "_zone_ids and the parent == 0 rows disagree")

    for _, id in ipairs(Zones.zone_ids()) do
        T.assert_equal(Zones.areas[id].parent, 0, "zone " .. id .. " is not top level")
    end
end

function M.test_the_json_mirror_carries_the_same_areas()
    -- The Rust QueryServer names zones from zones.json and cannot read a Lua table. One generator
    -- writes both; this is the assertion that nobody hand-patched one of them, because a server
    -- naming a zone the runtime cannot is a mismatch no request will ever report.
    local decoded = read_json("sentinel/kernel/catalogs/zones.json")
    local seen = 0
    for _, area in ipairs(decoded.areas) do
        local lua_area = Zones.areas[area.id]
        T.assert_true(lua_area ~= nil,
            string.format("JSON area %d (%s) is missing from zones.lua", area.id, area.name))
        T.assert_equal(lua_area.name, area.name, "name disagrees for area " .. area.id)
        T.assert_equal(lua_area.parent, area.parent, "parent disagrees for area " .. area.id)
        T.assert_equal(lua_area.map, area.map, "map disagrees for area " .. area.id)
        seen = seen + 1
    end
    T.assert_equal(seen, 1643, "the JSON mirror carries a different number of areas than the Lua")
end

function M.test_the_spawn_index_is_keyed_by_real_zones_and_totals_add_up()
    local index = read_json("sentinel/kernel/catalogs/spawn_zones.json")
    T.assert_true(index.creatures ~= nil and index.objects ~= nil,
        "the index must carry both spawn tables")

    for _, section in ipairs({ "creatures", "objects" }) do
        local counted, zones = 0, 0
        for zone_key, entries in pairs(index[section]) do
            local zone = tonumber(zone_key)
            zones = zones + 1
            -- A zone key with no catalog row means the endpoint would answer with spawns for a
            -- zone it cannot name, which is exactly the 404-vs-empty confusion the endpoint exists
            -- to avoid.
            T.assert_true(zone ~= nil and Zones.areas[zone] ~= nil,
                section .. " index names zone " .. tostring(zone_key) .. ", absent from the catalog")
            T.assert_equal(Zones.zone_of(zone), zone,
                "the index must be keyed by ZONES, but " .. tostring(zone) .. " is a sub-area")
            for entry_key, count in pairs(entries) do
                T.assert_true(tonumber(entry_key) ~= nil, "entry key is not a number: " .. entry_key)
                T.assert_true(count > 0, "a zero spawn count is an absent row, not a row")
                counted = counted + count
            end
        end
        T.assert_true(zones > 0, section .. " index is empty")
        local total = index.totals[section == "creatures" and "creature_spawns" or "gameobject_spawns"]
        local bad = index.totals[section == "creatures" and "creature_unresolved" or "gameobject_unresolved"]
        T.assert_equal(counted + bad, total,
            section .. ": indexed + unresolved must equal the snapshot's spawn count")
        -- 8% unresolved was the symptom of the missing instance-map fallback (instances ship no
        -- terrain tiles at all). Anything past a rounding error means the derivation regressed.
        T.assert_true(bad * 1000 <= total,
            string.format("%s: %d of %d spawns resolved to no zone", section, bad, total))
    end
end

function M.test_a_known_zone_carries_the_spawns_it_should()
    local index = read_json("sentinel/kernel/catalogs/spawn_zones.json")
    local elwynn = index.creatures["12"]
    T.assert_true(elwynn ~= nil, "Elwynn Forest must carry creature spawns")
    -- Hogger (448) is the canonical Elwynn elite, and 299 Defias Smuggler the canonical trash.
    -- Pinning named entries rather than a count keeps this test meaningful after a DB refresh.
    T.assert_true(elwynn["448"] ~= nil and elwynn["448"] > 0,
        "Hogger is spawned in Elwynn Forest")
    T.assert_true(elwynn["299"] ~= nil and elwynn["299"] > 0,
        "Defias Smugglers are spawned in Elwynn Forest")
end

return M
