-- sentinel/modules/operation/sub_operation_composer.lua
-- SENT-5.7: Sub-Operation Composition
-- ADR 007 §17

local SubOperationComposer = {}
SubOperationComposer.__index = SubOperationComposer

function SubOperationComposer:new(operation_registry)
    local o = setmetatable({}, SubOperationComposer)
    o._operations = {}
    o._operation_registry = operation_registry or {}
    return o
end

function SubOperationComposer:register_operation(operation)
    if operation and operation.id then
        self._operations[operation.id] = operation
    end
end

function SubOperationComposer:get_operation(id)
    return self._operations[id]
end

function SubOperationComposer:compute_parent_goals(parent_operation)
    if not parent_operation or not parent_operation.sub_operations then
        return (parent_operation and parent_operation.goals) or {}
    end

    local goal_set = {}
    local parent_goals = parent_operation.goals or {}

    for _, goal in ipairs(parent_goals) do
        goal_set[goal.type .. "_" .. self:_goal_key(goal)] = goal
    end

    for _, sub_id in ipairs(parent_operation.sub_operations) do
        local sub_op = self:get_operation(sub_id)
        if sub_op then
            local sub_goals = self:_get_required_goals(sub_op)
            for _, goal in ipairs(sub_goals) do
                local key = goal.type .. "_" .. self:_goal_key(goal)
                if not goal_set[key] then
                    goal_set[key] = goal
                else
                    local existing = goal_set[key]
                    if goal.weight and existing.weight then
                        existing.weight = math.max(existing.weight, goal.weight)
                    end
                end
            end
        end
    end

    local result = {}
    for _, goal in pairs(goal_set) do
        table.insert(result, goal)
    end

    return result
end

function SubOperationComposer:_get_required_goals(operation)
    local goals = {}
    if not operation.goals then
        return goals
    end
    for _, goal in ipairs(operation.goals) do
        if goal.required ~= false then
            table.insert(goals, goal)
        end
    end
    return goals
end

function SubOperationComposer:_goal_key(goal)
    local key_parts = {}

    if goal.quest_id then
        table.insert(key_parts, tostring(goal.quest_id))
    end
    if goal.entry then
        table.insert(key_parts, tostring(goal.entry))
    end
    if goal.node_id then
        table.insert(key_parts, tostring(goal.node_id))
    end
    if goal.spell_id then
        table.insert(key_parts, tostring(goal.spell_id))
    end
    if goal.name then
        table.insert(key_parts, goal.name)
    end

    return table.concat(key_parts, "_")
end

function SubOperationComposer:compute_all_required_goals(operations)
    local required_goals_map = {}

    for _, op in ipairs(operations) do
        if op.sub_operations and #op.sub_operations > 0 then
            local goals = self:compute_parent_goals(op)
            for _, goal in ipairs(goals) do
                if goal.required ~= false then
                    local key = goal.type .. "_" .. self:_goal_key(goal)
                    required_goals_map[op.id .. "_" .. key] = goal
                end
            end
        else
            for _, goal in ipairs(op.goals or {}) do
                if goal.required ~= false then
                    local key = goal.type .. "_" .. self:_goal_key(goal)
                    required_goals_map[op.id .. "_" .. key] = goal
                end
            end
        end
    end

    local result = {}
    for _, goal in pairs(required_goals_map) do
        table.insert(result, goal)
    end

    return result
end

function SubOperationComposer:validate_sub_operation_coverage(parent_operation, actions)
    if not parent_operation then
        return { covered = true, missing_goals = {} }
    end

    local required_goals = self:compute_parent_goals(parent_operation)
    local missing = {}

    for _, goal in ipairs(required_goals) do
        local covered = false
        for _, action in ipairs(actions or {}) do
            if self:_action_covers_goal(action, goal) then
                covered = true
                break
            end
        end
        if not covered then
            table.insert(missing, goal)
        end
    end

    return {
        covered = (#missing == 0),
        missing_goals = missing,
        required_goals = required_goals
    }
end

function SubOperationComposer:_action_covers_goal(action, goal)
    local GoalCoverage = require("modules/operation/goal_coverage")
    return GoalCoverage.check_action_coverage_for_goal(action, goal)
end

function SubOperationComposer:flatten_operations(operations)
    local flattened = {}
    local processed = {}

    for _, op in ipairs(operations) do
        self:_flatten_operation(op, flattened, processed)
    end

    return flattened
end

function SubOperationComposer:_flatten_operation(operation, flattened, processed)
    if not operation or processed[operation.id] then
        return
    end

    processed[operation.id] = true

    if operation.sub_operations and #operation.sub_operations > 0 then
        for _, sub_id in ipairs(operation.sub_operations) do
            local sub_op = self:get_operation(sub_id)
            if sub_op then
                self:_flatten_operation(sub_op, flattened, processed)
            end
        end
    else
        table.insert(flattened, operation)
    end
end

return SubOperationComposer