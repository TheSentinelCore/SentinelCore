-- sentinel/modules/quest/quest_registry.lua
-- QuestRegistry: On-demand query cache for Mangos DB via QueryClient

local LRUCache = require("modules/quest/cache/lru_cache")
local JSON = require("lib/JSON")

local QuestRegistry = {}
QuestRegistry.__index = QuestRegistry

function QuestRegistry.new(queryClient, options)
    options = options or {}
    return setmetatable({
        _client = queryClient,
        _questCache = LRUCache.new(options.maxQuestCacheSize or 500, options.ttlMs or 300000),
        _npcCache = LRUCache.new(options.maxNPCCacheSize or 200, options.ttlMs or 300000),
        _searchCache = LRUCache.new(options.maxSearchCacheSize or 50, options.ttlMs or 300000),
    }, QuestRegistry)
end

-- Quest data access
function QuestRegistry:getQuest(questId)
    local cached = self._questCache:get(questId)
    if cached then return cached end
    
    local ok, data = pcall(self._client.fetch_quest, self._client, questId)
    if ok and data then
        self._questCache:set(questId, data)
        return data
    end
    return nil
end

function QuestRegistry:getQuestNPCs(questId, role)
    local cacheKey = questId .. ":" .. role
    local cached = self._npcCache:get(cacheKey)
    if cached then return cached end
    
    local ok, npcs = pcall(self._client.fetch_quest_npcs, self._client, questId, role)
    if ok and npcs then
        self._npcCache:set(cacheKey, npcs)
        return npcs
    end
    return nil
end

function QuestRegistry:getPrerequisites(questId)
    local quest = self:getQuest(questId)
    if not quest then return {} end
    
    local prereqs = {}
    local current = quest.prev_quest_id or 0
    while current > 0 do
        prereqs[#prereqs + 1] = current
        local prevQuest = self:getQuest(current)
        if not prevQuest then break end
        current = prevQuest.prev_quest_id or 0
    end
    return prereqs
end

-- Search (for editor autocomplete)
function QuestRegistry:searchQuests(criteria)
    local key = JSON.encode(criteria)
    local cached = self._searchCache:get(key)
    if cached then return cached end
    
    -- QueryClient doesn't have search endpoint yet - would need to add
    -- For now, return empty (can be extended when search endpoint is added)
    local results = {}
    
    -- If we had a local quest list, we could filter here
    -- For MVP, return empty
    self._searchCache:set(key, results)
    return results
end

-- Validation helpers (for ProfileCompiler)
function QuestRegistry:validateQuestExists(questId)
    local quest = self:getQuest(questId)
    return quest ~= nil, quest
end

function QuestRegistry:validateNPCExists(npcId)
    -- Would need a get_npc endpoint in QueryClient
    return true, nil
end

function QuestRegistry:validatePrerequisitesMet(questId, completedQuestIds)
    local prereqs = self:getPrerequisites(questId)
    local completed = {}
    for _, id in ipairs(completedQuestIds) do
        completed[id] = true
    end
    
    local missing = {}
    for _, prereqId in ipairs(prereqs) do
        if not completed[prereqId] then
            missing[#missing + 1] = prereqId
        end
    end
    
    return #missing == 0, missing
end

-- Cache management
function QuestRegistry:clearCaches()
    self._questCache:clear()
    self._npcCache:clear()
    self._searchCache:clear()
end

function QuestRegistry:cacheStats()
    return {
        quests = self._questCache:stats(),
        npcs = self._npcCache:stats(),
        search = self._searchCache:stats(),
    }
end

return QuestRegistry