-- sentinel/tests/modules/operation/test_dependency_graph.lua
-- Tests for SENT-5.3: Operation Dependency Graph Construction

local T = require("tests/test_util")

local M = {}

function M.test_dependency_graph_build()
    print("Test: DependencyGraph build")

    local DependencyGraph = require("modules/operation/dependency_graph")
    local graph = DependencyGraph:new()

    local operations = {
        { id = "northshire", name = "Northshire", priority = 100, dependencies = {} },
        { id = "goldshire", name = "Goldshire", priority = 90, dependencies = {
            { operation_id = "northshire", relationship = "Requires" }
        }},
        { id = "westbrook", name = "Westbrook", priority = 80, dependencies = {
            { operation_id = "goldshire", relationship = "SoftPrefers" }
        }}
    }

    graph:build(operations)

    T.assert_true(graph:has_node("northshire"), "northshire node exists")
    T.assert_true(graph:has_node("goldshire"), "goldshire node exists")
    T.assert_true(graph:has_node("westbrook"), "westbrook node exists")

    print("  PASS")
end

function M.test_dependency_graph_get_dependencies()
    print("Test: DependencyGraph get_dependencies")

    local DependencyGraph = require("modules/operation/dependency_graph")
    local graph = DependencyGraph:new()

    local operations = {
        { id = "op-a", dependencies = {
            { operation_id = "op-b", relationship = "Requires" }
        }},
        { id = "op-b", dependencies = {
            { operation_id = "op-c", relationship = "ExcludesWith" }
        }}
    }

    graph:build(operations)

    local deps_a = graph:get_dependencies("op-a")
    T.assert_equal(#deps_a, 1, "op-a has 1 dependency")
    T.assert_equal(deps_a[1].target, "op-b", "op-a depends on op-b")
    T.assert_equal(deps_a[1].relationship, "Requires", "Relationship is Requires")

    local deps_b = graph:get_dependencies("op-b")
    T.assert_equal(#deps_b, 1, "op-b has 1 dependency")
    T.assert_equal(deps_b[1].relationship, "ExcludesWith", "Relationship is ExcludesWith")

    print("  PASS")
end

function M.test_dependency_graph_get_dependents()
    print("Test: DependencyGraph get_dependents")

    local DependencyGraph = require("modules/operation/dependency_graph")
    local graph = DependencyGraph:new()

    local operations = {
        { id = "op-a", dependencies = {
            { operation_id = "op-b", relationship = "Requires" }
        }},
        { id = "op-c", dependencies = {
            { operation_id = "op-b", relationship = "UnlocksAfter" }
        }}
    }

    graph:build(operations)

    local dependents_b = graph:get_dependents("op-b")
    T.assert_equal(#dependents_b, 2, "op-b has 2 dependents")

    print("  PASS")
end

function M.test_northshire_goldshire_westbrook_example()
    print("Test: Northshire → Goldshire → Westbrook example from ADR 007 §11")

    local DependencyGraph = require("modules/operation/dependency_graph")
    local graph = DependencyGraph:new()

    local operations = {
        { id = "northshire", name = "Northshire", priority = 100, dependencies = {} },
        { id = "goldshire", name = "Goldshire", priority = 90, dependencies = {
            { operation_id = "northshire", relationship = "Requires" }
        }},
        { id = "westbrook", name = "Westbrook", priority = 80, dependencies = {
            { operation_id = "goldshire", relationship = "SoftPrefers" }
        }},
        { id = "eastvale", name = "Eastvale Logging Camp", priority = 70, dependencies = {
            { operation_id = "goldshire", relationship = "Requires" }
        }}
    }

    graph:build(operations)

    T.assert_equal(#graph:get_dependents("northshire"), 1, "northshire has 1 dependent")
    T.assert_equal(#graph:get_dependents("goldshire"), 2, "goldshire has 2 dependents")
    T.assert_equal(#graph:get_dependencies("northshire"), 0, "northshire has no dependencies")

    print("  PASS")
end

function M.run()
    print("=== Dependency Graph Tests ===")
    M.test_dependency_graph_build()
    M.test_dependency_graph_get_dependencies()
    M.test_dependency_graph_get_dependents()
    M.test_northshire_goldshire_westbrook_example()
    print("\n=== All Dependency Graph Tests PASSED ===")
end

return M