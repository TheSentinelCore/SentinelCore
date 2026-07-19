-- sentinel/runtime/stage_dependency_resolution.lua
-- SENT-6.4: Stage 4 — Operation Dependency Resolution
-- ADR 008 §7
-- Build dependency graph, detect cycles, detect ExcludesWith conflicts, topological sort

local DependencyGraph = require("modules/operation/dependency_graph")
local Diagnostics = require("runtime/diagnostics")

local DependencyResolutionStage = {}
DependencyResolutionStage.__index = DependencyResolutionStage

-- Diagnostic codes for this stage (C-4xxx)
DependencyResolutionStage.ErrorCodes = {
    CycleDetected = "C-4001",
    ExcludesWithConflict = "C-4002",
    UnreachableDependency = "C-4003",
}

---Create a new DependencyResolutionStage
---@return table
function DependencyResolutionStage:new()
    return setmetatable({}, DependencyResolutionStage)
end

---Run Stage 4: Build dependency graph and produce ordered operations
---@param profile table Profile with operations
---@return table|nil ordered_ops (table of operation ids in order), table diagnostics
function DependencyResolutionStage:run(profile)
    local errors = {}
    local warnings = {}

    if not profile or not profile.operations then
        table.insert(errors, {
            code = "V-1003",
            message = "profile missing operations",
            stage = Diagnostics.Stage.DependencyResolution,
            severity = Diagnostics.Severity.ERROR,
        })
        return nil, { errors = errors, warnings = warnings }
    end

    -- Build dependency graph
    local graph = DependencyGraph:new()
    graph:build(profile.operations)

    -- Check that all dependency targets exist (C-4003)
    for _, op in ipairs(profile.operations) do
        if op.dependencies then
            for _, dep in ipairs(op.dependencies) do
                if not graph:has_node(dep.operation_id) then
                    table.insert(errors, {
                        code = DependencyResolutionStage.ErrorCodes.UnreachableDependency,
                        message = "Operation '" .. (op.name or "?") .. "' depends on nonexistent Operation ID: " .. tostring(dep.operation_id),
                        stage = Diagnostics.Stage.DependencyResolution,
                        severity = Diagnostics.Severity.ERROR,
                        entity = op.name,
                        suggested_fix = "Add the missing operation or fix the dependency reference",
                    })
                end
            end
        end
    end

    if #errors > 0 then
        return nil, { errors = errors, warnings = warnings }
    end

    -- Detect cycles (C-4001)
    local cycle = self:_detect_cycle(graph, profile.operations)
    if cycle then
        local cycle_names = {}
        for _, op_id in ipairs(cycle) do
            local op = graph:get_operation(op_id)
            table.insert(cycle_names, op and ("'" .. op.name .. "'") or tostring(op_id))
        end
        table.insert(errors, {
            code = DependencyResolutionStage.ErrorCodes.CycleDetected,
            message = "Cycle detected in dependency graph: " .. table.concat(cycle_names, " → "),
            stage = Diagnostics.Stage.DependencyResolution,
            severity = Diagnostics.Severity.ERROR,
            suggested_fix = "Remove or change one of the circular dependency edges",
        })
        return nil, { errors = errors, warnings = warnings }
    end

    -- Detect ExcludesWith conflicts (C-4002)
    local exclude_errors = self:_detect_excludes_with_conflicts(profile.operations)
    for _, err in ipairs(exclude_errors) do
        table.insert(errors, err)
    end

    if #errors > 0 then
        return nil, { errors = errors, warnings = warnings }
    end

    -- Topological sort with tie-breaking
    local ordered_ids = self:_topological_sort(profile.operations, graph)

    return ordered_ids, { errors = errors, warnings = warnings }
end

---Detect cycles using DFS with white/gray/black coloring
---@param graph table DependencyGraph instance
---@param operations table Array of operations
---@return table|nil cycle path or nil if no cycle
function DependencyResolutionStage:_detect_cycle(graph, operations)
    local WHITE, GRAY, BLACK = 0, 1, 2
    local colour = {}
    local stack = {}
    local cycle = {}

    -- Initialize all nodes as white
    for _, op in ipairs(operations) do
        colour[op.id] = WHITE
    end

    local function dfs(node_id)
        colour[node_id] = GRAY
        table.insert(stack, node_id)

        local deps = graph:get_dependencies(node_id)
        for _, dep in ipairs(deps) do
            local dep_id = dep.target
            if dep.relationship == DependencyGraph.DependencyType.Requires or
               dep.relationship == DependencyGraph.DependencyType.UnlocksAfter then
                if colour[dep_id] == GRAY then
                    -- Found cycle - extract path
                    local start_idx = 0
                    for i, id in ipairs(stack) do
                        if id == dep_id then
                            start_idx = i
                            break
                        end
                    end
                    if start_idx > 0 then
                        for i = start_idx, #stack do
                            table.insert(cycle, stack[i])
                        end
                        table.insert(cycle, dep_id) -- close the cycle
                    end
                    return true
                elseif colour[dep_id] == WHITE then
                    if dfs(dep_id) then
                        return true
                    end
                end
            end
        end

        table.remove(stack)
        colour[node_id] = BLACK
        return false
    end

    -- Sort nodes by id for deterministic order
    table.sort(operations, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)

    for _, op in ipairs(operations) do
        if colour[op.id] == WHITE then
            if dfs(op.id) then
                return cycle
            end
        end
    end

    return nil
end

---Detect ExcludesWith conflicts where both sides are eligible for the same character
---@param operations table Array of operations
---@return table errors
function DependencyResolutionStage:_detect_excludes_with_conflicts(operations)
    local errors = {}
    local seen_pairs = {}

    for _, op_a in ipairs(operations) do
        if op_a.dependencies then
            for _, dep in ipairs(op_a.dependencies) do
                if dep.relationship == DependencyGraph.DependencyType.ExcludesWith then
                    local op_b = nil
                    for _, o in ipairs(operations) do
                        if o.id == dep.operation_id then
                            op_b = o
                            break
                        end
                    end

                    if op_b then
                        -- Create canonical pair key
                        local pair_key
                        if tostring(op_a.id) < tostring(op_b.id) then
                            pair_key = op_a.id .. ":" .. op_b.id
                        else
                            pair_key = op_b.id .. ":" .. op_a.id
                        end

                        if not seen_pairs[pair_key] then
                            seen_pairs[pair_key] = true

                            if not self:_are_mutually_exclusive(op_a.entry_conditions, op_b.entry_conditions) then
                                table.insert(errors, {
                                    code = DependencyResolutionStage.ErrorCodes.ExcludesWithConflict,
                                    message = "ExcludesWith conflict between Operations '" .. (op_a.name or "?") .. "' and '" .. (op_b.name or "?") .. "' — both are eligible for the same character",
                                    stage = Diagnostics.Stage.DependencyResolution,
                                    severity = Diagnostics.Severity.ERROR,
                                    entity = op_a.name,
                                    suggested_fix = "Add entry_conditions (RaceIs/ClassIs/FactionIs) that make them mutually exclusive",
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return errors
end

---Check if two entry_conditions sets are mutually exclusive
---@param conds_a table Entry conditions for operation A
---@param conds_b table Entry conditions for operation B
---@return boolean True if mutually exclusive
function DependencyResolutionStage:_are_mutually_exclusive(conds_a, conds_b)
    conds_a = conds_a or {}
    conds_b = conds_b or {}

    -- Check RaceIs conflict
    local a_races = self:_extract_races(conds_a)
    local b_races = self:_extract_races(conds_b)
    if #a_races > 0 and #b_races > 0 then
        if self:_have_conflicting_races(a_races, b_races) then
            return true
        end
    end

    -- Check FactionIs conflict
    local a_factions = self:_extract_factions(conds_a)
    local b_factions = self:_extract_factions(conds_b)
    if #a_factions > 0 and #b_factions > 0 then
        if self:_have_conflicting_factions(a_factions, b_factions) then
            return true
        end
    end

    -- Check ClassIs conflict
    local a_classes = self:_extract_classes(conds_a)
    local b_classes = self:_extract_classes(conds_b)
    if #a_classes > 0 and #b_classes > 0 then
        if self:_have_conflicting_classes(a_classes, b_classes) then
            return true
        end
    end

    return false
end

---Extract Race values from conditions
---@param conds table Conditions array
---@return table races
function DependencyResolutionStage:_extract_races(conds)
    local races = {}
    for _, cond in ipairs(conds) do
        if cond.type == "RaceIs" or cond.type == "race_is" then
            table.insert(races, cond.value)
        end
    end
    return races
end

---Extract Faction values from conditions
---@param conds table Conditions array
---@return table factions
function DependencyResolutionStage:_extract_factions(conds)
    local factions = {}
    for _, cond in ipairs(conds) do
        if cond.type == "FactionIs" or cond.type == "faction_is" then
            table.insert(factions, cond.value)
        end
    end
    return factions
end

---Extract Class values from conditions
---@param conds table Conditions array
---@return table classes
function DependencyResolutionStage:_extract_classes(conds)
    local classes = {}
    for _, cond in ipairs(conds) do
        if cond.type == "ClassIs" or cond.type == "class_is" then
            table.insert(classes, cond.value)
        end
    end
    return classes
end

---Check if there's any overlap in races
---@param a_races table Races for A
---@param b_races table Races for B
---@return boolean True if all races conflict (no overlap)
function DependencyResolutionStage:_have_conflicting_races(a_races, b_races)
    for _, ar in ipairs(a_races) do
        local has_overlap = false
        for _, br in ipairs(b_races) do
            if ar == br then
                has_overlap = true
                break
            end
        end
        if not has_overlap then
            return true
        end
    end
    return false
end

---Check if there's any overlap in factions
---@param a_factions table Factions for A
---@param b_factions table Factions for B
---@return boolean True if all factions conflict (no overlap)
function DependencyResolutionStage:_have_conflicting_factions(a_factions, b_factions)
    for _, af in ipairs(a_factions) do
        local has_overlap = false
        for _, bf in ipairs(b_factions) do
            if af == bf then
                has_overlap = true
                break
            end
        end
        if not has_overlap then
            return true
        end
    end
    return false
end

---Check if there's any overlap in classes
---@param a_classes table Classes for A
---@param b_classes table Classes for B
---@return boolean True if all classes conflict (no overlap)
function DependencyResolutionStage:_have_conflicting_classes(a_classes, b_classes)
    for _, ac in ipairs(a_classes) do
        local has_overlap = false
        for _, bc in ipairs(b_classes) do
            if ac == bc then
                has_overlap = true
                break
            end
        end
        if not has_overlap then
            return true
        end
    end
    return false
end

---Topological sort with tie-breaking via Kahn's algorithm
---@param operations table Array of operations
---@param graph table DependencyGraph instance
---@return table Ordered operation ids
function DependencyResolutionStage:_topological_sort(operations, graph)
    local in_degree = {}
    local adj = {}

    -- Initialize
    for _, op in ipairs(operations) do
        in_degree[op.id] = 0
        adj[op.id] = {}
    end

    -- Build adjacency list for Requires/UnlocksAfter
    for _, op in ipairs(operations) do
        if op.dependencies then
            for _, dep in ipairs(op.dependencies) do
                if dep.relationship == DependencyGraph.DependencyType.Requires or
                   dep.relationship == DependencyGraph.DependencyType.UnlocksAfter then
                    table.insert(adj[dep.operation_id], op.id)
                    in_degree[op.id] = (in_degree[op.id] or 0) + 1
                end
            end
        end
    end

    -- Build priority map
    local priority_map = {}
    for _, op in ipairs(operations) do
        priority_map[op.id] = op.priority or 100
    end

    -- Build soft-prefers map
    local soft_prefers_to = {}
    for _, op in ipairs(operations) do
        if op.dependencies then
            for _, dep in ipairs(op.dependencies) do
                if dep.relationship == DependencyGraph.DependencyType.SoftPrefers then
                    if not soft_prefers_to[dep.operation_id] then
                        soft_prefers_to[dep.operation_id] = {}
                    end
                    table.insert(soft_prefers_to[dep.operation_id], op.id)
                end
            end
        end
    end

    -- Build declaration order map
    local decl_order = {}
    for i, op in ipairs(operations) do
        decl_order[op.id] = i
    end

    -- Find initial ready nodes (in-degree 0)
    local ready = {}
    for _, op in ipairs(operations) do
        if in_degree[op.id] == 0 then
            table.insert(ready, op.id)
        end
    end

    -- Sort ready list
    self:_sort_candidates(ready, soft_prefers_to, priority_map, decl_order)

    local result = {}

    while #ready > 0 do
        local node = table.remove(ready, 1)
        table.insert(result, node)

        -- Process neighbors
        for _, neighbor in ipairs(adj[node] or {}) do
            in_degree[neighbor] = in_degree[neighbor] - 1
            if in_degree[neighbor] == 0 then
                table.insert(ready, neighbor)
            end
        end

        -- Re-sort ready list
        self:_sort_candidates(ready, soft_prefers_to, priority_map, decl_order)
    end

    return result
end

---Sort candidates by tie-breaking rules
---@param candidates table List of candidate ids to sort in-place
---@param soft_prefers_to table Map of node -> nodes that soft-prefer it
---@param priority_map table Map of operation id -> priority
---@param decl_order table Map of operation id -> declaration order
function DependencyResolutionStage:_sort_candidates(candidates, soft_prefers_to, priority_map, decl_order)
    ---
    soft_preferred_by = {}
    for _, from in ipairs(candidates) do
        if soft_prefers_to[from] then
            for _, to in ipairs(soft_prefers_to[from]) do
                if self:_in_list(candidates, to) then
                    soft_preferred_by[to] = (soft_preferred_by[to] or 0) + 1
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        -- Lower soft_preferred_by → earlier
        local sa = soft_preferred_by[a] or 0
        local sb = soft_preferred_by[b] or 0
        if sa ~= sb then
            return sa < sb
        end
        -- Higher priority → earlier
        local pa = priority_map[a] or 100
        local pb = priority_map[b] or 100
        if pa ~= pb then
            return pb < pa
        end
        -- Earlier declaration order → earlier
        local da = decl_order[a] or math.huge
        local db = decl_order[b] or math.huge
        return da < db
    end)
end

---Check if value is in list
---@param list table
---@param value any
---@return boolean
function DependencyResolutionStage:_in_list(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

return DependencyResolutionStage