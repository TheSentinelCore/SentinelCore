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
end

return M
