-- sentinel/modules/quest/goal_checker.lua
-- Goal checking implementation for quest operations
-- Checks goal satisfaction against player state

local GoalChecker = {}
GoalChecker.__index = GoalChecker

---Create a new GoalChecker
---@param blackboard table The SentinelCore blackboard
---@return table GoalChecker instance
function GoalChecker:new(blackboard)
    local o = setmetatable({}, GoalChecker)
    o._blackboard = blackboard
    return o
end

---Check if CompleteQuest goal is satisfied
---@param goal table Goal with quest_id field
---@return boolean satisfied
function GoalChecker:check_complete_quest(goal)
    local quest_id = goal.quest_id
    if not quest_id then
        return false
    end

    -- Check blackboard first (for testing and state tracking)
    local completed = self._blackboard:get("player.completed_quests") or {}
    for _, qid in ipairs(completed) do
        if qid == quest_id then
            return true
        end
    end

    -- Also check via Sylvannas core.quests API if available (live check)
    if core and core.quests and core.quests.is_quest_flagged_completed then
        local ok, is_completed = pcall(core.quests.is_quest_flagged_completed, quest_id)
        if ok and is_completed then
            return true
        end
    end

    return false
end

---Check if CompleteQuestChain goal is satisfied (all quests completed)
---@param goal table Goal with quest_ids field (array)
---@return boolean satisfied
function GoalChecker:check_complete_quest_chain(goal)
    local quest_ids = goal.quest_ids
    if not quest_ids or #quest_ids == 0 then
        return true  -- No quests means satisfied
    end

    for _, quest_id in ipairs(quest_ids) do
        if not self:check_complete_quest({ quest_id = quest_id }) then
            return false
        end
    end
    return true
end

---Check if ReachLevel goal is satisfied (informational)
---@param goal table Goal with level field
---@return boolean satisfied
function GoalChecker:check_reach_level(goal)
    local target_level = goal.level
    if not target_level then
        return true  -- No level specified = satisfied
    end

    -- Check blackboard first
    local player_level = self._blackboard:get("player.level") or 0

    -- Also check via Sylvannas API if available (live check)
    if core and core.player and core.player.get_level then
        local ok, level = pcall(core.player.get_level)
        if ok and level and level > player_level then
            player_level = level
        end
    end

    return player_level >= target_level
end

---Check if UnlockFlightPath goal is satisfied
---@param goal table Goal with node_id field
---@return boolean satisfied
function GoalChecker:check_unlock_flight_path(goal)
    local node_id = goal.node_id
    if not node_id then
        return false
    end

    -- Check blackboard first
    local flight_paths = self._blackboard:get("player.flight_paths") or {}
    for _, fp_id in ipairs(flight_paths) do
        if fp_id == node_id then
            return true
        end
    end

    -- Also check via core if available (live check)
    if core and core.flight_paths and core.flight_paths.is_known then
        local ok, known = pcall(core.flight_paths.is_known, node_id)
        if ok and known then
            return true
        end
    end

    return false
end

---Check if AcquireItem goal is satisfied
---@param goal table Goal with entry and count fields
---@return boolean satisfied
function GoalChecker:check_acquire_item(goal)
    local entry = goal.entry
    local required_count = goal.count or 1

    if not entry then
        return false
    end

    local inventory = self._blackboard:get("player.inventory") or {}
    local total_count = 0

    for _, item in ipairs(inventory) do
        if item.entry == entry or item.id == entry then
            total_count = total_count + (item.count or 1)
        end
    end

    return total_count >= required_count
end

---Check all goals for an operation
---@param goals table Array of goal tables
---@return table Result: { all_met = bool, uncovered = [] }
function GoalChecker:check_all_goals(goals)
    local uncovered = {}

    if not goals or #goals == 0 then
        return { all_met = true, uncovered = {} }
    end

    for _, goal in ipairs(goals) do
        local satisfied = false

        if goal.type == "CompleteQuest" then
            satisfied = self:check_complete_quest(goal)
        elseif goal.type == "CompleteQuestChain" then
            satisfied = self:check_complete_quest_chain(goal)
        elseif goal.type == "ReachLevel" then
            satisfied = self:check_reach_level(goal)
        elseif goal.type == "UnlockFlightPath" then
            satisfied = self:check_unlock_flight_path(goal)
        elseif goal.type == "AcquireItem" then
            satisfied = self:check_acquire_item(goal)
        else
            -- Unknown goal types are considered satisfied (fail open)
            satisfied = true
        end

        if not satisfied then
            table.insert(uncovered, goal)
        end
    end

    return {
        all_met = (#uncovered == 0),
        uncovered = uncovered
    }
end

return GoalChecker