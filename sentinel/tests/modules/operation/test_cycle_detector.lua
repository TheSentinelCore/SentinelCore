-- sentinel/tests/modules/operation/test_cycle_detector.lua
-- Tests for SENT-5.4: Cycle Detection & ExcludesWith Conflict Detection

local T = require("tests/test_util")

local M = {}

function M.test_detect_cycles_no_cycle()
    print("Test: detect_cycles - no cycle")

    local CycleDetector = require("modules/operation/cycle_detector")
    local DependencyGraph = require("modules/operation/dependency_graph")

    local graph = DependencyGraph:new()
    graph:build({
        { id = "a", dependencies = {
            { operation_id = "b", relationship = "Requires" }
        }},
        { id = "b", dependencies = {
            { operation_id = "c", relationship = "Requires" }
        }},
        { id = "c", dependencies = {}}
    })

    local cycles = CycleDetector.detect_cycles(graph)
    T.assert_equal(#cycles, 0, "No cycles detected")

    print("  PASS")
end

function M.test_detect_cycles_with_cycle()
    print("Test: detect_cycles - with cycle")

    local CycleDetector = require("modules/operation/cycle_detector")
    local DependencyGraph = require("modules/operation/dependency_graph")

    local graph = DependencyGraph:new()
    graph:build({
        { id = "a", dependencies = {
            { operation_id = "b", relationship = "Requires" }
        }},
        { id = "b", dependencies = {
            { operation_id = "c", relationship = "Requires" }
        }},
        { id = "c", dependencies = {
            { operation_id = "a", relationship = "Requires" }
        }}
    })

    local cycles = CycleDetector.detect_cycles(graph)
    T.assert_true(#cycles > 0, "Cycle detected")

    print("  PASS")
end

function M.test_detect_excludes_with_conflict()
    print("Test: detect_excludes_with_conflicts - mutual exclusion eligible")

    local CycleDetector = require("modules/operation/cycle_detector")
    local DependencyGraph = require("modules/operation/dependency_graph")

    local graph = DependencyGraph:new()
    graph:build({
        { id = "op-a", entry_conditions = {}, dependencies = {
            { operation_id = "op-b", relationship = "ExcludesWith" }
        }},
        { id = "op-b", entry_conditions = {}, dependencies = {
            { operation_id = "op-a", relationship = "ExcludesWith" }
        }}
    })

    local conflicts = CycleDetector.detect_excludes_with_conflicts(graph, {})
    local has_error = false
    for _, c in ipairs(conflicts) do
        if not c.warning then
            has_error = true
            break
        end
    end
    T.assert_true(has_error, "Conflict detected (both eligible)")

    print("  PASS")
end

function M.test_detect_excludes_with_disjoint_entry()
    print("Test: detect_excludes_with_conflicts - disjoint entry conditions")

    local CycleDetector = require("modules/operation/cycle_detector")
    local DependencyGraph = require("modules/operation/dependency_graph")

    local graph = DependencyGraph:new()
    graph:build({
        { id = "op-a", entry_conditions = {
            { type = "RaceIs", race = 1 }
        }, dependencies = {
            { operation_id = "op-b", relationship = "ExcludesWith" }
        }},
        { id = "op-b", entry_conditions = {
            { type = "RaceIs", race = 2 }
        }, dependencies = {
            { operation_id = "op-a", relationship = "ExcludesWith" }
        }}
    })

    local conflicts = CycleDetector.detect_excludes_with_conflicts(graph, {})
    local has_warning = false
    for _, c in ipairs(conflicts) do
        if c.warning then
            has_warning = true
            break
        end
    end
    T.assert_true(has_warning, "ExcludesWith marked as redundant due to disjoint entry conditions")

    print("  PASS")
end

function M.test_validate_operations()
    print("Test: validate - full validation")

    local CycleDetector = require("modules/operation/cycle_detector")

    local operations = {
        { id = "op-a", dependencies = {
            { operation_id = "op-b", relationship = "Requires" }
        }},
        { id = "op-b", dependencies = {
            { operation_id = "op-c", relationship = "Requires" }
        }},
        { id = "op-c", dependencies = {}}
    }

    local result = CycleDetector.validate(operations)
    T.assert_true(result.valid, "Valid graph")
    T.assert_equal(#result.errors, 0, "No errors")

    print("  PASS")
end

function M.run()
    print("=== Cycle Detector Tests ===")
    M.test_detect_cycles_no_cycle()
    M.test_detect_cycles_with_cycle()
    M.test_detect_excludes_with_conflict()
    M.test_detect_excludes_with_disjoint_entry()
    M.test_validate_operations()
    print("\n=== All Cycle Detector Tests PASSED ===")
end

return M