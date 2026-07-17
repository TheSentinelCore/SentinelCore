-- sentinel/modules/quest/quest_data.lua
-- QuestData: Read-only data accessor for quest/NPC information (replaces planning logic with on-demand queries)

local QueryClient = require("modules/quest/query_client")
local Questie = require("modules/quest/questie_adapter")

local QuestData = {}
QuestData.__index = QuestData

local CACHE_TTL_S = 3600 -- 1 hour for graph data

---Create new QuestData instance
---@param blackboard table
---@return QuestData
function QuestData.new(blackboard)
    return setmetatable({
        _blackboard = blackboard,
        _client = QueryClient.new(blackboard),
        _cache = {},
        _questie = Questie,
    }, QuestData)
end

---Get quest data from database
---@param quest_id integer
---@return table|nil quest data
function QuestData:getQuest(quest_id)
    local cached = self._cache[quest_id]
    if cached then return cached end
    
    local ok, data = pcall(self._client.fetch_quest, self._client, quest_id)
    if ok and data then
        self._cache[quest_id] = data
    end
    return data
end

---Get NPC data for quest relation
---@param quest_id integer
---@param relation string "giver" | "turnin"
---@return table[] NPC list
function QuestData:getQuestNPCs(quest_id, relation)
    local cache_key = "npc:" .. quest_id .. ":" .. relation
    local cached = self._cache[cache_key]
    if cached then return cached end
    
    local ok, npcs = pcall(self._client.fetch_quest_npcs, self._client, quest_id, relation)
    if ok and npcs then
        self._cache[cache_key] = npcs
    end
    return npcs
end

---Get quest chain (prerequisites and follow-ups)
---@param quest_id integer
---@return table {backward: integer[], forward: integer[]}
function QuestData:getQuestChain(quest_id)
    local quest = self:getQuest(quest_id)
    if not quest then return {backward = {}, forward = {}} end
    
    local backward = {}
    local forward = {}
    
    -- Walk backward (prerequisites)
    local current = quest_id
    while current and current > 0 do
        local q = self:getQuest(current)
        if q and q.prev_quest_id and q.prev_quest_id > 0 then
            backward[#backward + 1] = q.prev_quest_id
            current = q.prev_quest_id
        else
            break
        end
    end
    
    -- Walk forward (follow-ups)
    current = quest_id
    while current and current > 0 do
        local q = self:getQuest(current)
        if q and q.next_quest_id and q.next_quest_id > 0 then
            forward[#forward + 1] = q.next_quest_id
            current = q.next_quest_id
        else
            break
        end
    end
    
    return {backward = backward, forward = forward}
end

---Get all quests that share objectives with given quest
---@param quest_id integer
---@return table[] overlapping quests
function QuestData:getOverlappingQuests(quest_id)
    -- Would need a full quest graph; simplified for now
    return {}
end

---Check if quest is completed
---@param quest_id integer
---@return boolean
function QuestData:isQuestCompleted(quest_id)
    if self._questie and self._questie.is_ready and self._questie.is_ready() then
        local ok, complete = pcall(self._questie.is_quest_complete, self._questie, quest_id)
        if ok and complete == true then
            return true
        end
    end
    return false
end

---Get active quests from tracker (merged with Questie)
---@return table[]
function QuestData:getActiveQuests()
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

---Get active quest IDs
---@return integer[]
function QuestData:getActiveQuestIds()
    local tracker = self._blackboard:get("module.quest.quests", {})
    local ids = {}
    for quest_id, _ in pairs(tracker) do
        ids[#ids + 1] = quest_id
    end
    return ids
end

---Check if quest is in log
---@param quest_id integer
---@return boolean
function QuestData:isOnQuest(quest_id)
    local tracker = self._blackboard:get("module.quest.quests", {})
    return tracker[tonumber(quest_id)] ~= nil
end

---Check if quest prerequisites are met
---@param quest_id integer
---@param completedQuestIds integer[]
---@return boolean, integer[] missing prereqs
function QuestData:validatePrerequisitesMet(quest_id, completedQuestIds)
    local chain = self:getQuestChain(quest_id)
    local completed = {}
    for _, id in ipairs(completedQuestIds) do
        completed[id] = true
    end
    
    local missing = {}
    for _, prereqId in ipairs(chain.backward) do
        if not completed[prereqId] then
            missing[#missing + 1] = prereqId
        end
    end
    
    return #missing == 0, missing
end

---Clear all cached data
function QuestData:clearCache()
    self._cache = {}
end

return QuestData