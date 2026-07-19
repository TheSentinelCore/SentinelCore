local T = require("tests/test_util")

local M = {}

function M.run()
    local MaintenanceTree = require("modules/combat/profiles/mage/maintenance_tree")

    -- build() returns a non-nil BT node
    local tree = MaintenanceTree.build()
    T.assert_not_nil(tree, "build() should return a non-nil BT node")

    -- node has the correct name
    T.assert_equal(tree.name, "frost_mage_maintenance", "root node should be named frost_mage_maintenance")

    -- node has children (5 sequences: ice_armor, frost_armor, arcane_intellect, conjure_food, conjure_water)
    T.assert_equal(#tree.children, 5, "root selector should have 5 children")

    -- verify child names
    T.assert_equal(tree.children[1].name, "ensure_ice_armor", "child 1 should be ensure_ice_armor")
    T.assert_equal(tree.children[2].name, "ensure_frost_armor", "child 2 should be ensure_frost_armor")
    T.assert_equal(tree.children[3].name, "ensure_arcane_intellect", "child 3 should be ensure_arcane_intellect")
    T.assert_equal(tree.children[4].name, "conjure_food", "child 4 should be conjure_food")
    T.assert_equal(tree.children[5].name, "conjure_water", "child 5 should be conjure_water")

    -- each sequence has children (conditions + action)
    for i = 1, 5 do
        T.assert_true(#tree.children[i].children >= 2, "sequence " .. i .. " should have at least 2 children")
    end
end

return M
