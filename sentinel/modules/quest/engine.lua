local Questie = require("modules/quest/questie_adapter")
local QueryClient = require("modules/quest/query_client")

local Engine = {}
Engine.__index = Engine

function Engine.new(blackboard)
    return setmetatable({
        _blackboard = blackboard,
        _client = QueryClient.new(blackboard),
        _route_cache = {},
    }, Engine)
end

--- Get quest giver NPCs for a quest from database
function Engine:get_quest_givers(quest_id, map_id)
    local cached = self._route_cache["givers_" .. quest_id]
    if cached then
        return cached
    end

    local npcs = self._client:fetch_quest_npcs(quest_id, "giver")
    if not npcs then
        return {}
    end

    if map_id then
        local filtered = {}
        for _, npc in ipairs(npcs) do
            if npc.map_id == tonumber(map_id) then
                filtered[#filtered + 1] = npc
            end
        end
        self._route_cache["givers_" .. quest_id] = filtered
        return filtered
    end

    self._route_cache["givers_" .. quest_id] = npcs
    return npcs
end

--- Get quest turn-in NPCs for a quest from database
function Engine:get_quest_turnins(quest_id, map_id)
    local cached = self._route_cache["turnins_" .. quest_id]
    if cached then
        return cached
    end

    local npcs = self._client:fetch_quest_npcs(quest_id, "turnin")
    if not npcs then
        return {}
    end

    if map_id then
        local filtered = {}
        for _, npc in ipairs(npcs) do
            if npc.map_id == tonumber(map_id) then
                filtered[#filtered + 1] = npc
            end
        end
        self._route_cache["turnins_" .. quest_id] = filtered
        return filtered
    end

    self._route_cache["turnins_" .. quest_id] = npcs
    return npcs
end

--- Get cached quest data from database
function Engine:get_quest_data(quest_id)
    return self._client:fetch_quest(quest_id)
end

--- Determine if a quest can be turned in, checking both Questie and tracker
function Engine:can_turn_in(quest_id)
    if Questie.is_ready() then
        local complete = Questie.is_quest_complete(quest_id)
        if complete == true then
            return true
        end
    end
    local tracker = self._blackboard:get("module.quest.quests", {})
    local quest = tracker[tonumber(quest_id)]
    return quest and quest.is_complete == true
end

--- Get all active quest objectives, merged with Questie state
function Engine:get_active_quests()
    local tracker = self._blackboard:get("module.quest.quests", {})
    local result = {}
    for quest_id, quest in pairs(tracker) do
        result[#result + 1] = {
            quest_id = quest_id,
            title = quest.title,
            level = quest.level,
            is_complete = quest.is_complete,
            doable = quest.questie and quest.questie.doable,
            complete = quest.questie and quest.questie.complete,
        }
    end
    return result
end

return Engine