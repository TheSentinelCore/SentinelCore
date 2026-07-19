-- sentinel/modules/operation/cycle_detector.lua
-- SENT-5.4: Cycle Detection & ExcludesWith Conflict Detection
-- ADR 007 §10, 008 §7 (steps 2-3)

local CycleDetector = {}
CycleDetector.__index = CycleDetector

function CycleDetector:new()
    return setmetatable({}, CycleDetector)
end

function CycleDetector.detect_cycles(graph)
    local visited = {}
    local rec_stack = {}
    local cycles = {}

    local function dfs(node_id, path)
        if rec_stack[node_id] then
            local cycle_start = 1
            for i, n in ipairs(path) do
                if n == node_id then
                    cycle_start = i
                    break
                end
            end
            local cycle = {}
            for i = cycle_start, #path do
                table.insert(cycle, path[i])
            end
            table.insert(cycles, cycle)
            return true
        end

        if visited[node_id] then
            return false
        end

        visited[node_id] = true
        rec_stack[node_id] = true
        table.insert(path, node_id)

        local deps = graph:get_dependencies(node_id)
        for _, dep in ipairs(deps) do
            if dep.relationship == "Requires" or dep.relationship == "UnlocksAfter" then
                if dfs(dep.target, path) then
                    return true
                end
            end
        end

        table.remove(path)
        rec_stack[node_id] = nil
        return false
    end

    for node_id, _ in pairs(graph._nodes) do
        visited = {}
        rec_stack = {}
        if dfs(node_id, {}) then
        end
    end

    return cycles
end

function CycleDetector.detect_excludes_with_conflicts(graph, all_operations)
    local conflicts = {}

    for op_id, op in pairs(graph._nodes) do
        local deps = graph:get_dependencies(op_id)

        for _, dep in ipairs(deps) do
            if dep.relationship == "ExcludesWith" then
                local target_op = graph:get_operation(dep.target)
                if target_op then
                    local target_deps = graph:get_dependencies(dep.target)

                    local is_mutual = false
                    for _, target_dep in ipairs(target_deps) do
                        if target_dep.target == op_id
                            and target_dep.relationship == "ExcludesWith" then
                            is_mutual = true
                            break
                        end
                    end

                    if is_mutual then
                        local entry_a = op.entry_conditions or {}
                        local entry_b = target_op.entry_conditions or {}

                        local disjoint = CycleDetector._are_entry_conditions_disjoint(entry_a, entry_b)

                        if not disjoint then
                            table.insert(conflicts, {
                                op_a = op_id,
                                op_b = dep.target,
                                reason = "ExcludesWith declared but both operations eligible for same character"
                            })
                        else
                            table.insert(conflicts, {
                                op_a = op_id,
                                op_b = dep.target,
                                reason = "ExcludesWith redundant (entry conditions already mutually exclusive)",
                                warning = true
                            })
                        end
                    else
                        table.insert(conflicts, {
                            op_a = op_id,
                            op_b = dep.target,
                            reason = "Unilateral ExcludesWith declaration",
                            warning = true
                        })
                    end
                end
            end
        end
    end

    return conflicts
end

function CycleDetector._are_entry_conditions_disjoint(entry_a, entry_b)
    if not entry_a or #entry_a == 0 or not entry_b or #entry_b == 0 then
        return false
    end

    for _, cond_a in ipairs(entry_a) do
        for _, cond_b in ipairs(entry_b) do
            if not CycleDetector._conditions_overlap(cond_a, cond_b) then
                return true
            end
        end
    end

    return false
end

function CycleDetector._conditions_overlap(cond_a, cond_b)
    if cond_a.type == "RaceIs" and cond_b.type == "RaceIs" then
        return cond_a.race == cond_b.race  -- Same race = overlap
    end

    if cond_a.type == "ClassIs" and cond_b.type == "ClassIs" then
        return cond_a.class == cond_b.class  -- Same class = overlap
    end

    if cond_a.type == "FactionIs" and cond_b.type == "FactionIs" then
        return cond_a.faction == cond_b.faction  -- Same faction = overlap
    end

    return false
end

function CycleDetector.validate(operations)
    local graph = require("modules/operation/dependency_graph"):new()
    graph:build(operations)

    local errors = {}
    local warnings = {}

    local cycles = CycleDetector.detect_cycles(graph)
    for _, cycle in ipairs(cycles) do
        table.insert(errors, {
            type = "cycle_detected",
            cycle = cycle,
            message = "Operation dependency cycle detected: " .. table.concat(cycle, " -> ")
        })
    end

    local conflicts = CycleDetector.detect_excludes_with_conflicts(graph, operations)
    for _, conflict in ipairs(conflicts) do
        if conflict.warning then
            table.insert(warnings, {
                type = "excludes_with_redundant",
                op_a = conflict.op_a,
                op_b = conflict.op_b,
                message = conflict.reason
            })
        else
            table.insert(errors, {
                type = "excludes_with_conflict",
                op_a = conflict.op_a,
                op_b = conflict.op_b,
                message = conflict.reason
            })
        end
    end

    return {
        valid = (#errors == 0),
        errors = errors,
        warnings = warnings
    }
end

return CycleDetector