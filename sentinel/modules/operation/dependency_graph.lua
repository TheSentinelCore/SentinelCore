-- sentinel/modules/operation/dependency_graph.lua
-- SENT-5.3: Operation Dependency Graph Construction
-- ADR 007 §10-11

local DependencyGraph = {}
DependencyGraph.__index = DependencyGraph

DependencyGraph.DependencyType = {
    Requires = "Requires",
    SoftPrefers = "SoftPrefers",
    ExcludesWith = "ExcludesWith",
    UnlocksAfter = "UnlocksAfter",
}

function DependencyGraph:new()
    local o = setmetatable({}, DependencyGraph)
    o._nodes = {}
    o._edges = {}
    o._reverse_edges = {}
    return o
end

function DependencyGraph:add_operation(operation)
    if not operation or not operation.id then
        return
    end

    self._nodes[operation.id] = operation

    if operation.dependencies then
        for _, dep in ipairs(operation.dependencies) do
            self:add_edge(operation.id, dep.operation_id, dep.relationship)
        end
    end
end

function DependencyGraph:add_edge(from_op_id, to_op_id, relationship)
    if not self._edges[from_op_id] then
        self._edges[from_op_id] = {}
    end

    table.insert(self._edges[from_op_id], {
        target = to_op_id,
        relationship = relationship or DependencyGraph.DependencyType.Requires
    })

    if not self._reverse_edges[to_op_id] then
        self._reverse_edges[to_op_id] = {}
    end

    table.insert(self._reverse_edges[to_op_id], {
        source = from_op_id,
        relationship = relationship or DependencyGraph.DependencyType.Requires
    })
end

function DependencyGraph:get_operation(id)
    return self._nodes[id]
end

function DependencyGraph:get_all_operations()
    local result = {}
    for _, node in pairs(self._nodes) do
        table.insert(result, node)
    end
    return result
end

function DependencyGraph:get_dependencies(op_id)
    local deps = self._edges[op_id]
    if not deps then
        return {}
    end
    return deps
end

function DependencyGraph:get_dependents(op_id)
    local dependents = self._reverse_edges[op_id]
    if not dependents then
        return {}
    end
    return dependents
end

function DependencyGraph:has_node(id)
    return self._nodes[id] ~= nil
end

function DependencyGraph:get_adjacency_list()
    return self._edges
end

function DependencyGraph:build(operations)
    self._nodes = {}
    self._edges = {}
    self._reverse_edges = {}

    for _, op in ipairs(operations) do
        self:add_operation(op)
    end
end

return DependencyGraph