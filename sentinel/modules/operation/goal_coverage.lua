-- sentinel/modules/operation/goal_coverage.lua
-- SENT-5.1: Goal Coverage Checking (static)
-- ADR 007 §4-5, §15
-- Statically checks if Operation goals are satisfied by actions

local GoalCoverage = {}
GoalCoverage.__index = GoalCoverage

local GoalType = {
    CompleteQuest = "CompleteQuest",
    CompleteQuestChain = "CompleteQuestChain",
    ReachLevel = "ReachLevel",
    GainXp = "GainXp",
    ReachZone = "ReachZone",
    ReachWaypoint = "ReachWaypoint",
    AcquireItem = "AcquireItem",
    KillCount = "KillCount",
    UnlockFlightPath = "UnlockFlightPath",
    LearnSpell = "LearnSpell",
    Custom = "Custom",
}

function GoalCoverage:new()
    return setmetatable({}, GoalCoverage)
end

function GoalCoverage.check_action_coverage_for_goal(action, goal)
    if not action or not goal then
        return false
    end

    local action_type = action.action_type or action.type

    -- The runtime canonically emits snake_case action types (pickup_quest,
    -- turn_in_quest, quest_hub), while the ADR-008 spec names the canonical
    -- payloads PickupQuestAction/TurnInQuestAction. Accept both spellings so
    -- coverage matches whatever the emitter actually produces.
    local is_turnin = action_type == "turn_in_quest" or action_type == "TurnInQuest" or action_type == "CompleteQuest"
    local is_pickup = action_type == "pickup_quest" or action_type == "PickupQuest"
    local is_questhub = action_type == "quest_hub" or action_type == "QuestHub"

    -- quest_id is either top-level (executor/ADR convention) or nested under
    -- params (blueprint_registry emission). Resolve the union.
    local function action_quest_id(a)
        return a.quest_id or (a.params and a.params.quest_id)
    end

    if goal.type == GoalType.CompleteQuest then
        if is_turnin then return true end
        if is_pickup and action_quest_id(action) == goal.quest_id then return true end
        return false
    end

    if goal.type == GoalType.CompleteQuestChain then
        local quest_ids = goal.quest_ids or {}
        if is_turnin or is_pickup then
            local aid = action_quest_id(action)
            for _, qid in ipairs(quest_ids) do
                if aid == qid then
                    return true
                end
            end
        end
        if is_questhub and action.quest_ids then
            for _, gqid in ipairs(quest_ids) do
                for _, aqid in ipairs(action.quest_ids) do
                    if gqid == aqid then
                        return true
                    end
                end
            end
        end
        return false
    end

    if goal.type == GoalType.ReachLevel or goal.type == GoalType.GainXp then
        return false
    end

    if goal.type == GoalType.ReachZone then
        return action_type == "TravelToZone" or action_type == "MoveTo"
            or action_type == "GoToAction"
    end

    if goal.type == GoalType.ReachWaypoint then
        return action_type == "MoveTo" or action_type == "Travel"
    end

    if goal.type == GoalType.AcquireItem then
        local entry = goal.entry
        if action_type == "Loot" or action_type == "PickupItem" then
            return action.entry == entry or action.item_id == entry
        end
        if action_type == "Vendor" and action.action == "buy" then
            return action.entry == entry
        end
        return false
    end

    if goal.type == GoalType.KillCount then
        local entry = goal.entry
        local count = goal.count or 1
        if action_type == "Kill" or action_type == "KillByName" then
            return action.entry == entry or (goal.name and action.name == goal.name)
        end
        if action_type == "GrindArea" or action_type == "KillAndLoot" then
            return action.creature_entry == entry or action.creature_id == entry
        end
        return false
    end

    if goal.type == GoalType.UnlockFlightPath then
        -- The flight node id may be top-level (node_id) or nested under a
        -- route (to.id / from.id), depending on which action shape emitted it.
        local function flight_node_id(a)
            return a.node_id or (a.to and a.to.id) or (a.from and a.from.id)
        end
        if action_type == "flight_path" or action_type == "FlightPath"
            or action_type == "FlightMaster" or action_type == "UnlockFlightPath" then
            return flight_node_id(action) == goal.node_id
        end
        if action_type == "talk_to_npc" or action_type == "TalkToNpc" then
            return action.gossip_action == "fly" or action.gossip_id == "flight"
        end
        return false
    end

    if goal.type == GoalType.LearnSpell then
        return action_type == "learn_spell" or action_type == "LearnSpell"
            or action_type == "train" or action_type == "TrainSpell"
            or ((action_type == "talk_to_npc" or action_type == "TalkToNpc") and action.gossip_action == "train")
    end

    if goal.type == GoalType.Custom then
        return action_type == "Custom" or action.custom_id == goal.id
    end

    return true
end

function GoalCoverage.is_statically_checkable(goal_type)
    local checkable = {
        [GoalType.CompleteQuest] = true,
        [GoalType.CompleteQuestChain] = true,
        [GoalType.AcquireItem] = true,
        [GoalType.KillCount] = true,
        [GoalType.UnlockFlightPath] = true,
        [GoalType.LearnSpell] = true,
        [GoalType.Custom] = true,
    }
    return checkable[goal_type] == true
end

function GoalCoverage.analyze_goal_coverage(operation)
    if not operation then
        return {
            all_covered = true,
            uncovered_required = {},
            uncovered_optional = {},
            informational = {}
        }
    end

    local goals = operation.goals or {}
    local actions = operation.actions or {}

    local result = {
        all_covered = true,
        uncovered_required = {},
        uncovered_optional = {},
        informational = {}
    }

    for _, goal in ipairs(goals) do
        local is_covered = false
        local is_required = goal.required ~= false

        if GoalCoverage.is_statically_checkable(goal.type) then
            for _, action in ipairs(actions) do
                if GoalCoverage.check_action_coverage_for_goal(action, goal) then
                    is_covered = true
                    break
                end
            end

            if not is_covered then
                if is_required then
                    table.insert(result.uncovered_required, goal)
                    result.all_covered = false
                else
                    table.insert(result.uncovered_optional, goal)
                end
            end
        else
            table.insert(result.informational, goal)
        end
    end

    return result
end

function GoalCoverage.check_all_goals_satisfied(operation, blackboard)
    if not operation then
        return { all_met = true, uncovered = {} }
    end

    local goals = operation.goals or {}
    local uncovered = {}

    for _, goal in ipairs(goals) do
        local satisfied = false

        if goal.type == GoalType.CompleteQuest then
            local completed = blackboard:get("player.completed_quests") or {}
            for _, qid in ipairs(completed) do
                if qid == goal.quest_id then
                    satisfied = true
                    break
                end
            end

        elseif goal.type == GoalType.CompleteQuestChain then
            satisfied = true
            local quest_ids = goal.quest_ids or {}
            for _, quest_id in ipairs(quest_ids) do
                local completed = blackboard:get("player.completed_quests") or {}
                local found = false
                for _, qid in ipairs(completed) do
                    if qid == quest_id then
                        found = true
                        break
                    end
                end
                if not found then
                    satisfied = false
                    break
                end
            end

        elseif goal.type == GoalType.ReachLevel then
            local player_level = blackboard:get("player.level") or 0
            satisfied = player_level >= (goal.level or 0)

        elseif goal.type == GoalType.GainXp then
            local xp_gained = blackboard:get("player.xp_gained") or 0
            satisfied = xp_gained >= (goal.xp_amount or 0)

        elseif goal.type == GoalType.ReachZone then
            local current_zone = blackboard:get("player.zone") or ""
            satisfied = current_zone == goal.zone_name

        elseif goal.type == GoalType.ReachWaypoint then
            satisfied = false

        elseif goal.type == GoalType.AcquireItem then
            local required_count = goal.count or 1
            local inventory = blackboard:get("player.inventory") or {}
            local total_count = 0
            for _, item in ipairs(inventory) do
                if item.entry == goal.entry or item.id == goal.entry then
                    total_count = total_count + (item.count or 1)
                end
            end
            satisfied = total_count >= required_count

        elseif goal.type == GoalType.KillCount then
            local required_count = goal.count or 1
            local kills = blackboard:get("combat.kill_counts") or {}
            local actual_count = 0
            for _, kill in ipairs(kills) do
                if kill.entry == goal.entry or kill.name == goal.name then
                    actual_count = actual_count + (kill.count or 1)
                end
            end
            satisfied = actual_count >= required_count

        elseif goal.type == GoalType.UnlockFlightPath then
            local flight_paths = blackboard:get("player.flight_paths") or {}
            for _, fp_id in ipairs(flight_paths) do
                if fp_id == goal.node_id then
                    satisfied = true
                    break
                end
            end

        elseif goal.type == GoalType.LearnSpell then
                    local spells = blackboard:get("player.spells") or {}
            for _, spell_id in ipairs(spells) do
                if spell_id == goal.spell_id then
                    satisfied = true
                    break
                end
            end

        elseif goal.type == GoalType.Custom then
            local custom_state = blackboard:get("module.custom_state") or {}
            satisfied = custom_state[goal.id] == true
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

return GoalCoverage