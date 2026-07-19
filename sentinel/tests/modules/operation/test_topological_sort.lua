-- sentinel/tests/modules/operation/test_topological_sort.lua
-- Tests for SENT-5.5: Topological Sort with Priority Tie-Breaking

local T = require("tests/test_util")

local M = {}

function M.test_topological_sort_basic()
    print("Test: topological_sort - basic ordering")

    local TopologicalSort = require("modules/operation/topological_sort")

    local operations = {
        { id = "op-c", name = "C", priority = 70, dependencies = {
            { operation_id = "op-a", relationship = "Requires" }
        }},
        { id = "op-a", name = "A", priority = 90, dependencies = {} },
        { id = "op-b", name = "B", priority = 80, dependencies = {
            { operation_id = "op-a", relationship = "Requires" }
        }}
    }

    local sorted = TopologicalSort.sort(operations)

    T.assert_equal(#sorted, 3, "All operations sorted")

    local order = {}
    for i, op in ipairs(sorted) do
        order[op.id] = i
    end

    T.assert_true(order["op-a"] < order["op-b"], "op-a before op-b")
    T.assert_true(order["op-a"] < order["op-c"], "op-a before op-c")
    T.assert_true(order["op-b"] < order["op-c"], "op-b before op-c")

    print("  PASS")
end

function M.test_topological_sort_priority_tie_breaking()
    print("Test: topological_sort - priority tie-breaking")

    local TopologicalSort = require("modules/operation/topological_sort")

    local operations = {
        { id = "op-low", name = "Low Priority", priority = 10, dependencies = {} },
        { id = "op-high", name = "High Priority", priority = 100, dependencies = {} }
    }

    local sorted = TopologicalSort.sort(operations)

    T.assert_equal(sorted[1].id, "op-high", "High priority first")
    T.assert_equal(sorted[2].id, "op-low", "Low priority second")

    print("  PASS")
end

function M.test_topological_sort_deterministic()
    print("Test: topological_sort - deterministic ordering")

    local TopologicalSort = require("modules/operation/topological_sort")

    local operations = {
        { id = "x", priority = 50, dependencies = {} },
        { id = "y", priority = 50, dependencies = {} },
        { id = "z", priority = 50, dependencies = {} }
    }

    local sorted1 = TopologicalSort.sort(operations)
    local sorted2 = TopologicalSort.sort(operations)

    T.assert_equal(sorted1[1].id, sorted2[1].id, "Deterministic: first same")
    T.assert_equal(sorted1[2].id, sorted2[2].id, "Deterministic: second same")
    T.assert_equal(sorted1[3].id, sorted2[3].id, "Deterministic: third same")

    print("  PASS")
end

function M.test_compute_compile_order()
    print("Test: compute_compile_order - sets compile_order field")

    local TopologicalSort = require("modules/operation/topological_sort")

    local operations = {
        { id = "second", priority = 10, dependencies = {} },
        { id = "first", priority = 100, dependencies = {} }
    }

    local sorted = TopologicalSort.compute_compile_order(operations)

    T.assert_equal(sorted[1].compile_order, 1, "First has compile_order 1")
    T.assert_equal(sorted[2].compile_order, 2, "Second has compile_order 2")

    print("  PASS")
end

function M.run()
    print("=== Topological Sort Tests ===")
    M.test_topological_sort_basic()
    M.test_topological_sort_priority_tie_breaking()
    M.test_topological_sort_deterministic()
    M.test_compute_compile_order()
    print("\n=== All Topological Sort Tests PASSED ===")
end

return M