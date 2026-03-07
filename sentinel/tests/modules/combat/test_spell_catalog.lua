local SpellCatalog = require("modules/combat/spell_catalog")
local T = require("tests/test_util")

local M = {}

function M.run()
    local catalog = SpellCatalog:new()
    T.assert_equal(catalog:resolve_best_rank("seal_of_command"), 27170)
    T.assert_equal(catalog:resolve_lowest_rank("seal_of_command"), 20375)
    T.assert_true(catalog:is_gcd_spell("crusader_strike"))
    T.assert_true(catalog:is_ogcd_spell("avenging_wrath"))
    T.assert_equal(catalog:get("divine_storm"), nil)

    -- Mage Frost spells
    T.assert_not_nil(catalog:get("frostbolt"), "frostbolt entry exists")
    T.assert_equal(type(catalog:get("frostbolt").ranks), "table", "frostbolt has ranks")
    T.assert_equal(#catalog:get("frostbolt").ranks, 14, "frostbolt has 14 ranks")
    T.assert_equal(catalog:resolve_best_rank("frostbolt"), 38697, "frostbolt best rank")
    T.assert_equal(catalog:resolve_lowest_rank("frostbolt"), 116, "frostbolt lowest rank")

    T.assert_not_nil(catalog:get("frost_nova"), "frost_nova exists")
    T.assert_equal(catalog:resolve_best_rank("frost_nova"), 27088, "frost_nova best rank")

    T.assert_not_nil(catalog:get("blizzard"), "blizzard exists")
    T.assert_equal(catalog:resolve_best_rank("blizzard"), 27085, "blizzard best rank")

    T.assert_equal(catalog:get("ice_lance").id, 30455, "ice_lance id")
    T.assert_equal(catalog:get("counterspell").id, 2139, "counterspell id")
    T.assert_equal(catalog:get("ice_block").id, 45438, "ice_block id")
    T.assert_equal(catalog:get("blink").id, 1953, "blink id")
    T.assert_equal(catalog:get("evocation").id, 12051, "evocation id")
    T.assert_equal(catalog:get("cold_snap").id, 11958, "cold_snap id")
    T.assert_equal(catalog:get("icy_veins").id, 12472, "icy_veins id")

    -- Off-GCD checks
    T.assert_true(catalog:is_ogcd_spell("ice_barrier"), "ice_barrier is off-GCD")
    T.assert_true(catalog:is_ogcd_spell("icy_veins"), "icy_veins is off-GCD")
    T.assert_true(catalog:is_ogcd_spell("cold_snap"), "cold_snap is off-GCD")
    T.assert_false(catalog:is_ogcd_spell("frostbolt"), "frostbolt is not off-GCD")

    -- Maintenance
    T.assert_not_nil(catalog:get("frost_armor"), "frost_armor exists")
    T.assert_not_nil(catalog:get("ice_armor"), "ice_armor exists")
    T.assert_not_nil(catalog:get("arcane_intellect"), "arcane_intellect exists")
    T.assert_not_nil(catalog:get("conjure_food"), "conjure_food exists")
    T.assert_not_nil(catalog:get("conjure_water"), "conjure_water exists")

    -- Reverse lookup
    T.assert_equal(catalog:find_key_by_id(116), "frostbolt", "reverse lookup frostbolt r1")
    T.assert_equal(catalog:find_key_by_id(30455), "ice_lance", "reverse lookup ice_lance")
end

return M
