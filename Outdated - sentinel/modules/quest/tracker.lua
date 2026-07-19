local Tracker = {}
Tracker.__index = Tracker
local Questie = require("modules/quest/questie_adapter")

function Tracker.new(blackboard)
    return setmetatable({
        _blackboard = blackboard,
        _quests = {},
        _last_refresh_ms = 0,
    }, Tracker)
end

local function safe_call(fn, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    return pcall(fn, ...)
end

function Tracker:refresh(now_ms)
    if not core or not core.quests then
        return false
    end

    local quests = {}
    local ok_count, count = safe_call(core.quests.get_num_quest_log_entries)
    if not ok_count then
        return false
    end

    for index = 1, tonumber(count) or 0 do
        local ok_info, info = safe_call(core.quests.get_quest_log_title, index)
        if ok_info and type(info) == "table" and info.is_header ~= true and info.quest_id then
            local quest = {
                log_index = index,
                quest_id = tonumber(info.quest_id),
                title = info.title,
                level = tonumber(info.level) or 0,
                is_complete = info.is_complete == true,
                objectives = {},
            }

            local ok_objectives, objective_count = safe_call(core.quests.get_num_quest_leader_boards, index)
            if ok_objectives then
                for objective_index = 1, tonumber(objective_count) or 0 do
                    local ok_text, text = safe_call(
                        core.quests.get_quest_log_leader_board,
                        objective_index,
                        index
                    )
                    if ok_text and text then
                        quest.objectives[#quest.objectives + 1] = {
                            index = objective_index,
                            text = text,
                        }
                    end
                end
            end
            if Questie.is_ready() then
                quest.questie = {
                    doable = Questie.is_quest_doable(quest.quest_id),
                    complete = Questie.is_quest_complete(quest.quest_id),
                }
            end
            quests[quest.quest_id] = quest
        end
    end

    self._quests = quests
    self._last_refresh_ms = tonumber(now_ms) or 0
    self._blackboard:set("module.quest.quests", quests)
    self._blackboard:set("module.quest.active_count", self:count())
    return true
end

function Tracker:count()
    local count = 0
    for _ in pairs(self._quests) do
        count = count + 1
    end
    return count
end

function Tracker:get(quest_id)
    return self._quests[tonumber(quest_id)]
end

function Tracker:all()
    return self._quests
end

return Tracker
