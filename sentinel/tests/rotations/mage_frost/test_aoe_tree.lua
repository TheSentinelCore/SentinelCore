local T = require("tests/test_util")

local M = {}

function M.run()
    local AoeTree = require("rotations/mage_frost/aoe_tree")

    -- build() returns a non-nil BT node
    local tree = AoeTree.build()
    T.assert_not_nil(tree, "build() should return a non-nil BT node")

    -- node has the correct name
    T.assert_equal(tree.name, "frost_aoe_pull", "root node should be named frost_aoe_pull")

    -- node has children (5 branches: gather, nova_and_blink, blizzard, re_freeze, emergency)
    T.assert_equal(#tree.children, 5, "root selector should have 5 children")

    -- verify child names
    T.assert_equal(tree.children[1].name, "gather_phase", "child 1 should be gather_phase")
    T.assert_equal(tree.children[2].name, "nova_and_blink", "child 2 should be nova_and_blink")
    T.assert_equal(tree.children[3].name, "blizzard_pack", "child 3 should be blizzard_pack")
    T.assert_equal(tree.children[4].name, "re_freeze", "child 4 should be re_freeze")
    T.assert_equal(tree.children[5].name, "emergency_escape", "child 5 should be emergency_escape")

    -- each top-level child has children
    for i = 1, 5 do
        T.assert_true(#tree.children[i].children >= 2, "branch " .. i .. " should have at least 2 children")
    end

    -- re_freeze contains a nested freeze_options selector (after condition children)
    local re_freeze = tree.children[4]
    T.assert_equal(re_freeze.children[3].name, "freeze_options", "re_freeze should contain freeze_options selector")
    T.assert_equal(#re_freeze.children[3].children, 2, "freeze_options should have 2 children (cone_of_cold, frost_nova)")

    -- emergency_escape contains a nested escape_tools selector
    local emergency = tree.children[5]
    T.assert_equal(emergency.children[2].name, "escape_tools", "emergency should contain escape_tools selector")
    T.assert_equal(#emergency.children[2].children, 2, "escape_tools should have 2 children (ice_block, blink)")
end

return M
