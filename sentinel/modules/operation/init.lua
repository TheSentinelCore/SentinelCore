-- sentinel/modules/operation/init.lua
-- SENT-5.1 through SENT-5.7: Operation System Logic
-- ADR 007: Operation System

local GoalCoverage = require("modules/operation/goal_coverage")
local ConditionEvaluator = require("modules/operation/condition_evaluator")
local DependencyGraph = require("modules/operation/dependency_graph")
local CycleDetector = require("modules/operation/cycle_detector")
local TopologicalSort = require("modules/operation/topological_sort")
local OperationLifecycle = require("modules/operation/operation_lifecycle")
local SubOperationComposer = require("modules/operation/sub_operation_composer")

local OperationModule = {}
OperationModule.__index = OperationModule

function OperationModule:new(blackboard, event_bus)
    local o = setmetatable({}, OperationModule)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._goal_coverage = GoalCoverage:new()
    o._condition_evaluator = ConditionEvaluator:new(blackboard)
    o._dependency_graph = DependencyGraph:new()
    o._cycle_detector = CycleDetector:new()
    o._topological_sort = TopologicalSort:new()
    o._lifecycle = OperationLifecycle:new(blackboard)
    o._sub_operation_composer = SubOperationComposer:new()
    return o
end

function OperationModule:analyze_goal_coverage(operation)
    return self._goal_coverage.analyze_goal_coverage(operation)
end

function OperationModule:evaluate_conditions(condition, context)
    return self._condition_evaluator.evaluate(condition, context)
end

function OperationModule:evaluate_entry_conditions(operation, context)
    return self._condition_evaluator.evaluate_entry_conditions(operation, context)
end

function OperationModule:evaluate_exit_conditions(operation, context)
    return self._condition_evaluator.evaluate_exit_conditions(operation, context)
end

function OperationModule:build_dependency_graph(operations)
    self._dependency_graph:build(operations)
    return self._dependency_graph
end

function OperationModule:validate_dependencies(operations)
    return CycleDetector.validate(operations)
end

function OperationModule:compute_compile_order(operations)
    return TopologicalSort.compute_compile_order(operations)
end

function OperationModule:set_operation_status(operation_id, status, skip_reason)
    return self._lifecycle:set_status(operation_id, status, skip_reason)
end

function OperationModule:get_operation_status(operation_id)
    return self._lifecycle:get_status(operation_id)
end

function OperationModule:compute_parent_goals(parent_operation)
    return self._sub_operation_composer:compute_parent_goals(parent_operation)
end

return OperationModule