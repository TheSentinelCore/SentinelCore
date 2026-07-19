-- sentinel/modules/operation/topological_sort.lua
-- SENT-5.5: Topological Sort with Priority Tie-Breaking
-- ADR 007 §10, 008 §7 (steps 4-5)

local TopologicalSort = {}
TopologicalSort.__index = TopologicalSort

local DependencyType = {
    Requires = "Requires",
    SoftPrefers = "SoftPrefers",
    ExcludesWith = "ExcludesWith",
    UnlocksAfter = "UnlocksAfter",
}

function TopologicalSort:new()
    return setmetatable({}, TopologicalSort)
end

function TopologicalSort.sort(operations)
    if not operations or #operations == 0 then
        return {}
    end

    local graph = require("modules/operation/dependency_graph"):new()
    graph:build(operations)

    local in_degree = {}
    local op_by_id = {}

    for _, op in ipairs(operations) do
        op_by_id[op.id] = op
        in_degree[op.id] = 0
    end

    for op_id, op in pairs(graph._nodes) do
        local deps = graph:get_dependencies(op_id)
        for _, dep in ipairs(deps) do
            if dep.relationship == DependencyType.Requires then
                in_degree[op_id] = in_degree[op_id] + 1
            end
        end
    end

    local result = {}
    local queue = {}

    for op_id, degree in pairs(in_degree) do
        if degree == 0 then
            table.insert(queue, op_id)
        end
    end

    table.sort(queue, function(a, b)
        local op_a = op_by_id[a]
        local op_b = op_by_id[b]
        local pri_a = op_a and (op_a.priority or 0) or 0
        local pri_b = op_b and (op_b.priority or 0) or 0
        return pri_a > pri_b
    end)

    while #queue > 0 do
        local current = table.remove(queue, 1)
        table.insert(result, op_by_id[current])

        local dependents = graph:get_dependents(current)
        for _, dep in ipairs(dependents) do
            if dep.relationship == DependencyType.Requires then
                in_degree[dep.source] = in_degree[dep.source] - 1
                if in_degree[dep.source] == 0 then
                    table.insert(queue, dep.source)
                end
            end
        end

        table.sort(queue, function(a, b)
            local op_a = op_by_id[a]
            local op_b = op_by_id[b]
            local pri_a = op_a and (op_a.priority or 0) or 0
            local pri_b = op_b and (op_b.priority or 0) or 0
            if pri_a ~= pri_b then
                return pri_a > pri_b
            end

            local soft_a = TopologicalSort._has_soft_prefers_to(operations, op_a)
            local soft_b = TopologicalSort._has_soft_prefers_to(operations, op_b)
            if soft_a and not soft_b then
                return true
            end
            if soft_b and not soft_a then
                return false
            end

            return op_a.id < op_b.id
        end)
    end

    return result
end

function TopologicalSort._has_soft_prefers_to(operations, op)
    if not op or not op.dependencies then
        return false
    end
    for _, dep in ipairs(op.dependencies) do
        if dep.relationship == DependencyType.SoftPrefers then
            return true
        end
    end
    return false
end

function TopologicalSort.sort_with_soft_prefers_first(operations)
    if not operations or #operations == 0 then
        return {}
    end

    local sorted = TopologicalSort.sort(operations)

    for _, op in ipairs(sorted) do
        if op.dependencies then
            for _, dep in ipairs(op.dependencies) do
                if dep.relationship == DependencyType.SoftPrefers then
                    op.soft_prefers_target = dep.operation_id
                end
            end
        end
    end

    return sorted
end

function TopologicalSort.compute_compile_order(operations)
    local sorted = TopologicalSort.sort(operations)

    for i, op in ipairs(sorted) do
        op.compile_order = i
    end

    return sorted
end

return TopologicalSort