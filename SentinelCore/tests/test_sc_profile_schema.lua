local T = require("tests/TestUtil")

local function run()
    T.install_core_stub({})

    local Schema = require("profiles/ProfileSchema")

    -- Test 1: SCHEMA_VERSION is defined
    T.assert_true(type(Schema.SCHEMA_VERSION) == "string", "SCHEMA_VERSION should be a string")

    -- Test 2: defaults() returns a full profile skeleton
    local d = Schema.defaults()
    T.assert_true(type(d) == "table", "defaults() should return a table")
    T.assert_eq(d.version, Schema.SCHEMA_VERSION, "version matches SCHEMA_VERSION")
    T.assert_true(type(d.metadata) == "table", "metadata present")
    T.assert_true(type(d.metadata.name) == "string", "metadata.name is string")
    T.assert_true(type(d.requirements) == "table", "requirements present")
    T.assert_true(type(d.target_defaults) == "table", "target_defaults present")
    T.assert_true(type(d.hotspots) == "table", "hotspots present")
    T.assert_true(type(d.blackspots) == "table", "blackspots present")
    T.assert_true(type(d.vendors) == "table", "vendors present")
    T.assert_true(type(d.rest_spots) == "table", "rest_spots present")
    T.assert_eq(d.loop, true, "loop defaults to true")
    T.assert_eq(d.dry_spell_secs, 15, "dry_spell_secs defaults to 15")
    T.assert_eq(d.travel_engage, true, "travel_engage defaults to true")

    -- Test 3: merge_target_filters merges hotspot overrides onto defaults
    local defaults = { level_min = 67, level_max = 70, creature_types = { "humanoid" }, npc_blacklist = { 100 }, npc_whitelist = {} }
    local overrides = { creature_types = { "humanoid", "demon" }, npc_blacklist = { 100, 200 } }
    local merged = Schema.merge_target_filters(defaults, overrides)
    T.assert_eq(merged.level_min, 67, "level_min inherited from defaults")
    T.assert_eq(merged.level_max, 70, "level_max inherited from defaults")
    T.assert_eq(#merged.creature_types, 2, "creature_types overridden")
    T.assert_eq(merged.creature_types[2], "demon", "creature_types[2] is demon")
    T.assert_eq(#merged.npc_blacklist, 2, "npc_blacklist overridden")

    -- Test 4: merge_target_filters with nil overrides returns copy of defaults
    local merged2 = Schema.merge_target_filters(defaults, nil)
    T.assert_eq(merged2.level_min, 67, "nil override inherits level_min")
    T.assert_eq(#merged2.creature_types, 1, "nil override inherits creature_types")

    return {
        sc_profile_schema_version = true,
        sc_profile_schema_defaults = true,
        sc_profile_schema_merge_filters = true,
        sc_profile_schema_merge_nil = true,
    }
end

return { run = run }
