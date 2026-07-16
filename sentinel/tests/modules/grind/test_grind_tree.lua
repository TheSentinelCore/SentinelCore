local GrindTree = require("modules/grind/grind_tree")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = { get = function(_, _, d) return d end, set = function() end }
    local bus = { publish = function() end, subscribe = function() return 1 end }
    local nav = {
        move_to = function() end,
        stop = function() end,
        is_active = function() return false end,
        get_state = function() return "idle" end,
    }

    local tree = GrindTree.build(bb, bus, nav)
    T.assert_not_nil(tree, "grind tree builds")
    T.assert_equal(tree.name, "grind_root_cooldown", "root is cooldown wrapper")
    T.assert_equal(tree.kind, "cooldown", "root kind is cooldown")

    -- Cooldown stores its child in children[1] (via Node base class)
    local inner = tree.children[1]
    T.assert_not_nil(inner, "cooldown has inner child")
    T.assert_equal(inner.name, "grind_root", "inner selector name")
    T.assert_equal(inner.kind, "priority_selector", "inner node is a priority_selector")

    -- The priority_selector should have exactly 8 phase children
    T.assert_equal(#inner.children, 8, "grind_root has 8 phase children")

    -- Verify phase order by name
    local expected_names = {
        "safety",
        "corpse_run",
        "loot_nearby",
        "rest",
        "vendor_run",
        "combat_active",
        "pull_target",
        "mode_acquire",
    }
    for i, name in ipairs(expected_names) do
        T.assert_equal(inner.children[i].name, name, "phase " .. i .. " is " .. name)
    end
end

return M
