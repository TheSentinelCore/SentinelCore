-- sentinel/runtime/stage_goal_coverage.lua
-- SENT-6.5: Stage 5 — Goal Coverage Validation
-- ADR 008 §8
-- Validates that declared OperationGoals are covered by actions

local GoalCoverage = require("modules/operation/goal_coverage")
local Diagnostics = require("runtime/diagnostics")

local GoalCoverageStage = {}
GoalCoverageStage.__index = GoalCoverageStage

-- Diagnostic codes for this stage (C-5xxx)
GoalCoverageStage.ErrorCodes = {
    QuestNotCovered = "C-5001",
    QuestChainIncomplete = "C-5002",
    FlightPathNotUnlocked = "C-5003",
    OptionalFlightPathNotCovered = "C-5004",
}

---Create a new GoalCoverageStage
---@return table
function GoalCoverageStage:new()
    return setmetatable({}, GoalCoverageStage)
end

---Run Stage 5: Validate goal coverage for all operations
---@param profile table Profile with operations (actions may be expanded)
---@return table diagnostics with errors (for required) and warnings (for optional)
function GoalCoverageStage:run(profile)
    local errors = {}
    local warnings = {}

    if not profile or not profile.operations then
        return { errors = errors, warnings = warnings }
    end

    for _, op in ipairs(profile.operations) do
        if op.goals then
            for _, goal in ipairs(op.goals) do
                local required = goal.required ~= false
                local is_covered, goal_type = self:_check_goal_coverage(op, goal)

                if not is_covered then
                    if required then
                        table.insert(errors, {
                            code = self:_get_error_code_for_goal(goal_type, required),
                            message = "Required goal '" .. (goal.description or goal.type) .. "' on Operation '" .. (op.name or "?") .. "' not covered by any action",
                            stage = Diagnostics.Stage.GoalCoverage,
                            severity = Diagnostics.Severity.ERROR,
                            suggested_fix = self:_get_fix_suggestion(goal_type),
                            entity = op.name,
                        })
                    else
                        table.insert(warnings, {
                            code = self:_get_error_code_for_goal(goal_type, required),
                            message = "Optional goal '" .. (goal.description or goal.type) .. "' on Operation '" .. (op.name or "?") .. "' not covered by any action",
                            stage = Diagnostics.Stage.GoalCoverage,
                            severity = Diagnostics.Severity.WARNING,
                            suggested_fix = self:_get_fix_suggestion(goal_type),
                            entity = op.name,
                        })
                    end
                end
            end
        end
    end

    return { errors = errors, warnings = warnings }
end

---Check if a goal is covered by the operation's actions
---@param op table Operation
---@param goal table Goal
---@return boolean is_covered, string goal_type
function GoalCoverageStage:_check_goal_coverage(op, goal)
    if not GoalCoverage.is_statically_checkable(goal.type) then
        return true, goal.type
    end

    local actions = op.actions or {}
    for _, action in ipairs(actions) do
        if GoalCoverage.check_action_coverage_for_goal(action, goal) then
            return true, goal.type
        end
    end

    -- Also check sub_operations if present
    if op.sub_operations then
        for _, sub_op_id in ipairs(op.sub_operations) do
            -- In a real implementation, we'd look up the sub-operation
            -- For now, check if any action in the operation covers it
        end
    end

    return false, goal.type
end

---Get the appropriate error code for a goal type
---@param goal_type string
---@param required boolean
---@return string error_code
function GoalCoverageStage:_get_error_code_for_goal(goal_type, required)
    if goal_type == "CompleteQuest" then
        return GoalCoverageStage.ErrorCodes.QuestNotCovered
    elseif goal_type == "CompleteQuestChain" then
        return GoalCoverageStage.ErrorCodes.QuestChainIncomplete
    elseif goal_type == "UnlockFlightPath" then
        if required then
            return GoalCoverageStage.ErrorCodes.FlightPathNotUnlocked
        else
            return GoalCoverageStage.ErrorCodes.OptionalFlightPathNotCovered
        end
    end
    return "C-5999"
end

---Get fix suggestion for a goal type
---@param goal_type string
---@return string suggestion
function GoalCoverageStage:_get_fix_suggestion(goal_type)
    if goal_type == "CompleteQuest" or goal_type == "CompleteQuestChain" then
        return "Add PickupQuest and TurnInQuest actions for the quest"
    elseif goal_type == "UnlockFlightPath" then
        return "Add a FlightPath action or TalkToNpc action for a flight master"
    elseif goal_type == "AcquireItem" then
        return "Add Loot or PickupItem action for the item"
    elseif goal_type == "KillCount" then
        return "Add Kill or GrindArea action for the creature"
    elseif goal_type == "LearnSpell" then
        return "Add TrainSpell or TalkToNpc (trainer) action"
    end
    return "Add an appropriate action to satisfy this goal"
end

---Validate a single operation's goal coverage
---@param operation table Operation to validate
---@return table result { all_covered = boolean, uncovered_required = {}, uncovered_optional = {} }
function GoalCoverageStage.validate_operation(operation)
    return GoalCoverage.analyze_goal_coverage(operation)
end

return GoalCoverageStage