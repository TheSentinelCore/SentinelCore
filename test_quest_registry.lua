-- test_quest_registry.lua
package.path = "./sentinel/?.lua;./sentinel/modules/?.lua;./sentinel/modules/quest/?.lua;" .. package.path

local LRUCache = require("modules/quest/cache/lru_cache")
local QuestRegistry = require("modules/quest/quest_registry")

local core = {log = print, logError = print}
_G.core = core

local JSON = require("lib/JSON")

-- Mock QueryClient
local MockQueryClient = {}
MockQueryClient.__index = MockQueryClient

function MockQueryClient.new()
    return setmetatable({
        _quests = {
            [783] = {id = 783, title = "A Threat Within", level = 1, prev_quest_id = 0, next_quest_id = 7},
            [7] = {id = 7, title = "The Latent Memory", level = 1, prev_quest_id = 783, next_quest_id = 15},
            [15] = {id = 15, title = "Investigate Echo Ridge", level = 2, prev_quest_id = 7, next_quest_id = 0},
        },
        _npcs = {
            [783] = {giver = {{npc_id = 197, name = "Marshal McBride", x = -8900, y = -100, z = 80, map_id = 0}},
                     turnin = {{npc_id = 197, name = "Marshal McBride", x = -8900, y = -100, z = 80, map_id = 0}}},
        },
    }, MockQueryClient)
end

function MockQueryClient:fetch_quest(id)
    return self._quests[id]
end

function MockQueryClient:fetch_quest_npcs(id, role)
    if self._npcs[id] then return self._npcs[id][role] end
    return {}
end

function MockQueryClient:search_quests(criteria)
    return {}
end

print("=== Testing LRUCache ===")
local cache = LRUCache.new(3, 1000) -- 3 items, 1s TTL

cache:set("a", "value_a")
cache:set("b", "value_b")
cache:set("c", "value_c")

assert(cache:get("a") == "value_a", "Basic get")
assert(cache:get("b") == "value_b", "Basic get")
assert(cache:get("c") == "value_c", "Basic get")

-- Test LRU eviction
cache:set("d", "value_d") -- should evict 'a' (LRU)
assert(cache:get("d") == "value_d", "New item added")
assert(cache:get("a") == nil, "LRU item evicted")

-- Test TTL expiration
cache:set("e", "value_e")
os.execute("sleep 1.1") -- wait for TTL
assert(cache:get("e") == nil, "TTL expired")

print("LRUCache tests passed!")

print("\n=== Testing QuestRegistry ===")
local queryClient = MockQueryClient.new()
local registry = QuestRegistry.new(queryClient, {maxQuestCacheSize = 10, ttlMs = 5000})

-- Test getQuest
local q1 = registry:getQuest(783)
assert(q1 and q1.id == 783, "getQuest works")
assert(q1.title == "A Threat Within", "Quest data correct")

-- Test caching
local q2 = registry:getQuest(783)
assert(q2 == q1, "Quest cached")

-- Test NPC lookup
local npcs = registry:getQuestNPCs(783, "giver")
assert(npcs and #npcs > 0, "NPC lookup works")
assert(npcs[1].npc_id == 197, "NPC data correct")

-- Test NPC caching
local npcs2 = registry:getQuestNPCs(783, "giver")
assert(npcs2 == npcs, "NPC cached")

-- Test prerequisites
local prereqs = registry:getPrerequisites(15)
assert(#prereqs == 2, "Prerequisites: " .. #prereqs)
assert(prereqs[1] == 7 and prereqs[2] == 783, "Prereq chain correct")

-- Test validation
local valid, quest = registry:validateQuestExists(783)
assert(valid and quest, "validateQuestExists works")

local invalid, _ = registry:validateQuestExists(99999)
assert(not invalid, "validateQuestExists rejects invalid")

-- Test prerequisites validation
local ok, missing = registry:validatePrerequisitesMet(15, {783, 7})
assert(ok, "Prereqs met: " .. JSON.encode(missing))

local ok2, missing2 = registry:validatePrerequisitesMet(15, {783})
assert(not ok2, "Prereqs not met")
assert(#missing2 == 1 and missing2[1] == 7, "Missing prereq: " .. JSON.encode(missing2))

print("All QuestRegistry tests passed!")

-- Test cache stats
local stats = registry:cacheStats()
print("Cache stats: " .. JSON.encode(stats))

print("\n=== All tests passed! ===")