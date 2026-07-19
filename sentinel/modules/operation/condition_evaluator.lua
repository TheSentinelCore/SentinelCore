-- sentinel/modules/operation/condition_evaluator.lua
-- SENT-5.2: Entry/Exit Condition Evaluation Engine
-- ADR 007 §6-7
-- Evaluates conditions against runtime context

local ConditionEvaluator = {}
ConditionEvaluator.__index = ConditionEvaluator

local ConditionType = {
    PlayerLevel = "PlayerLevel",
    LevelAbove = "LevelAbove",
    LevelBelow = "LevelBelow",
    HasQuest = "HasQuest",
    QuestCompleted = "QuestCompleted",
    QuestTurnedIn = "QuestTurnedIn",
    InZone = "InZone",
    HasItem = "HasItem",
    HasSpell = "HasSpell",
    RaceIs = "RaceIs",
    ClassIs = "ClassIs",
    FactionIs = "FactionIs",
    OperationCompleted = "OperationCompleted",
    OperationSkipped = "OperationSkipped",
    OperationFailed = "OperationFailed",
    And = "And",
    Or = "Or",
    Not = "Not",
}

function ConditionEvaluator:new(blackboard)
    local o = setmetatable({}, ConditionEvaluator)
    o._blackboard = blackboard
    return o
end

function ConditionEvaluator:evaluate(condition, context)
    context = context or {}

    if not condition then
        return true
    end

    if condition.type == nil then
        return true
    end

    local blackboard = self._blackboard
    local handlers = {
        [ConditionType.PlayerLevel] = function(c)
            local level = context.player_level or blackboard:get("player.level") or 0
            return level == c.level
        end,

        [ConditionType.LevelAbove] = function(c)
            local level = context.player_level or blackboard:get("player.level") or 0
            return level > c.level
        end,

        [ConditionType.LevelBelow] = function(c)
            local level = context.player_level or blackboard:get("player.level") or 0
            return level < c.level
        end,

        [ConditionType.HasQuest] = function(c)
            local quests = context.player_quests or blackboard:get("player.quests") or {}
            for _, qid in ipairs(quests) do
                if qid == c.quest_id then
                    return true
                end
            end
            return false
        end,

        [ConditionType.QuestCompleted] = function(c)
            local completed = context.completed_quests or blackboard:get("player.completed_quests") or {}
            for _, qid in ipairs(completed) do
                if qid == c.quest_id then
                    return true
                end
            end
            if core and core.quests and core.quests.is_quest_flagged_completed then
                local ok, is_completed = pcall(core.quests.is_quest_flagged_completed, c.quest_id)
                if ok and is_completed then
                    return true
                end
            end
            return false
        end,

        [ConditionType.QuestTurnedIn] = function(c)
            return self:evaluate({ type = ConditionType.QuestCompleted, quest_id = c.quest_id }, context)
        end,

        [ConditionType.InZone] = function(c)
            local zone = context.zone or blackboard:get("player.zone") or ""
            return zone == c.zone_name
        end,

        [ConditionType.HasItem] = function(c)
            local inventory = context.inventory or blackboard:get("player.inventory") or {}
            local required = c.count or 1
            for _, item in ipairs(inventory) do
                if item.entry == c.entry or item.id == c.entry then
                    local count = item.count or 1
                    if count >= required then
                        return true
                    end
                end
            end
            return false
        end,

        [ConditionType.HasSpell] = function(c)
            local spells = context.spells or blackboard:get("player.spells") or {}
            for _, spell_id in ipairs(spells) do
                if spell_id == c.spell_id then
                    return true
                end
            end
            return false
        end,

        [ConditionType.RaceIs] = function(c)
            local race = context.race or blackboard:get("player.race")
            if race == nil and core and core.player and core.player.get_race then
                local ok, r = pcall(core.player.get_race)
                if ok then race = r end
            end
            return race == c.race
        end,

        [ConditionType.ClassIs] = function(c)
            local class = context.class or blackboard:get("player.class")
            return class == c.class
        end,

        [ConditionType.FactionIs] = function(c)
            local faction = context.faction or blackboard:get("player.faction")
            return faction == c.faction
        end,

        [ConditionType.OperationCompleted] = function(c)
            local op_status = blackboard:get("operation." .. c.operation_id .. ".status")
            return op_status == "Completed"
        end,

        [ConditionType.OperationSkipped] = function(c)
            local op_status = blackboard:get("operation." .. c.operation_id .. ".status")
            return op_status == "Skipped"
        end,

        [ConditionType.OperationFailed] = function(c)
            local op_status = blackboard:get("operation." .. c.operation_id .. ".status")
            return op_status == "Failed"
        end,

        [ConditionType.And] = function(c)
            if not c.conditions or #c.conditions == 0 then
                return true
            end
            for _, sub_cond in ipairs(c.conditions) do
                if not ConditionEvaluator.evaluate(self, sub_cond, context) then
                    return false
                end
            end
            return true
        end,

        [ConditionType.Or] = function(c)
            if not c.conditions or #c.conditions == 0 then
                return true
            end
            for _, sub_cond in ipairs(c.conditions) do
                if ConditionEvaluator.evaluate(self, sub_cond, context) then
                    return true
                end
            end
            return false
        end,

        [ConditionType.Not] = function(c)
            if not c.condition then
                return true
            end
            return not ConditionEvaluator.evaluate(self, c.condition, context)
        end,
    }

    local handler = handlers[condition.type]
    if handler then
        return handler(condition)
    end

    return true
end

function ConditionEvaluator:evaluate_exit_conditions(operation, context)
    context = context or {}

    local exit = operation.exit_conditions
    if not exit then
        return { status = nil }
    end

    local result = {
        status = nil,
        abort = false,
        failure = false,
        success = false
    }

    if exit.abort and #exit.abort > 0 then
        for _, cond in ipairs(exit.abort) do
            if self:evaluate(cond, context) then
                result.abort = true
                result.status = "Aborted"
                return result
            end
        end
    end

    if exit.failure and #exit.failure > 0 then
        for _, cond in ipairs(exit.failure) do
            if self:evaluate(cond, context) then
                result.failure = true
                result.status = "Failed"
                return result
            end
        end
    end

    if exit.success and #exit.success > 0 then
        for _, cond in ipairs(exit.success) do
            if self:evaluate(cond, context) then
                result.success = true
                result.status = "Completed"
                return result
            end
        end
    end

    return result
end

function ConditionEvaluator:evaluate_entry_conditions(operation, context)
    context = context or {}

    local entry = operation.entry_conditions
    if not entry or #entry == 0 then
        return { eligible = true, blocking_conditions = {} }
    end

    local blocking = {}
    for _, cond in ipairs(entry) do
        if not self:evaluate(cond, context) then
            table.insert(blocking, cond)
        end
    end

    return {
        eligible = (#blocking == 0),
        blocking_conditions = blocking
    }
end

function ConditionEvaluator:all_conditions_met(condition_list, context)
    if not condition_list or #condition_list == 0 then
        return true
    end

    for _, cond in ipairs(condition_list) do
        if not self:evaluate(cond, context) then
            return false
        end
    end

    return true
end

return ConditionEvaluator