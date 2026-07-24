--- Quest-log-full recovery: pick a sacrificial quest to abandon.
---
--- Pure selection logic, separated from the module's ui_error handler so it is
--- testable offline. A candidate must be IN the log and referenced by NO operation
--- from the current one forward (AcceptQuest/TurnInQuest payloads, Condition
--- payloads, and per-action guards all count as references); incomplete quests
--- (is_complete flag 0) are preferred over complete ones — a complete non-route
--- quest still holds an earned reward the player may want.

local QuestLogSpace = {}

--- Quest-log flags are NUMERIC in the live client (is_complete = 1, not true), and
--- 0 is truthy in Lua — both a bare truthiness check and `== true` are wrong.
local function quest_flag(v)
    return v == true or v == 1
end
QuestLogSpace.quest_flag = quest_flag

--- Accumulate every quest id a RuntimeCondition can reference into `out` (a set
--- keyed by tostring(id)). Struct variants only; unit-string conditions carry no id.
local function collect_condition_quests(cond, out)
    if type(cond) ~= "table" then return end
    local t, p = cond.type, cond.payload
    if t == "QuestAccepted" or t == "QuestCompleted" or t == "QuestRewarded" then
        if p ~= nil then out[tostring(p)] = true end
    elseif t == "ObjectiveComplete" then
        if type(p) == "table" and p[1] ~= nil then out[tostring(p[1])] = true end
    elseif t == "Not" then
        collect_condition_quests(p, out)
    elseif t == "All" or t == "Any" then
        if type(p) == "table" then
            for _, sub in ipairs(p) do
                collect_condition_quests(sub, out)
            end
        end
    end
end

--- Set of quest ids (tostring-keyed) the route still needs from `from_idx` forward.
function QuestLogSpace.route_quest_ids(operations, from_idx)
    local out = {}
    if type(operations) ~= "table" then return out end
    for i = math.max(tonumber(from_idx) or 1, 1), #operations do
        local op = operations[i]
        for _, action in ipairs((op and op.actions) or {}) do
            local p = action.payload
            if (action.type == "AcceptQuest" or action.type == "TurnInQuest")
                and type(p) == "table" and p.quest_id ~= nil then
                out[tostring(p.quest_id)] = true
            elseif action.type == "Condition" and type(p) == "table" then
                collect_condition_quests(p.condition, out)
            end
            if action.guard then
                collect_condition_quests(action.guard, out)
            end
        end
    end
    return out
end

--- Pick the quest to abandon when the log is full.
--- `entries`: array of { index, quest_id, is_complete[, is_header] } in log order.
--- Returns the chosen ENTRY (index preserved for select_quest_log_entry), or nil
--- when every log quest is route-relevant — the caller must then do nothing and
--- let the accept's retry budget handle advancement.
function QuestLogSpace.select_sacrificial_quest(entries, operations, current_op_idx)
    local route = QuestLogSpace.route_quest_ids(operations, current_op_idx)
    local complete_fallback = nil
    for _, e in ipairs(entries or {}) do
        if not e.is_header and e.quest_id ~= nil and not route[tostring(e.quest_id)] then
            if not quest_flag(e.is_complete) then
                return e
            end
            complete_fallback = complete_fallback or e
        end
    end
    return complete_fallback
end

return QuestLogSpace
