-- sentinel/modules/quest/phase_runner.lua
-- PhaseRunner: Executes low-level steps (replaces Engine's planning logic)

local QueryClient = require("modules/quest/query_client")
local QuestData = require("modules/quest/quest_data")
local Events = require("modules/quest/events")
local RoutingPolicyLoader = require("modules/quest/routing_policy_loader")

local PhaseRunner = {}
PhaseRunner.__index = PhaseRunner

function PhaseRunner.new(blackboard, eventBus)
    local self = setmetatable({
        _blackboard = blackboard,
        _eventBus = eventBus,
        _client = QueryClient.new(blackboard),
        _route_cache = {},
        _graph = QuestData.new(blackboard),
        _last_graph_build = 0,
        _graph_build_interval = 30000, -- 30 seconds
        _eventDetector = Events.Detector.new(eventBus, blackboard, nil),
        _policyLoader = RoutingPolicyLoader.new(),
    }, PhaseRunner)
    
    -- Set self-reference for event detector
    self._eventDetector._phaseRunner = self
    return self
end

function PhaseRunner:shutdown()
    if self._eventDetector then
        self._eventDetector:shutdown()
    end
end

function PhaseRunner:updateEvents()
    if self._eventDetector then
        self._eventDetector:update()
    end
end

--- Get quest data for current zone/level
---@param zone string|nil
---@param level_range table|nil {min, max}
---@param faction string|nil
---@return QuestData
function PhaseRunner:getQuestData(zone, level_range, faction)
    local now = self._blackboard:get("system.now_ms", 0)
    if now - self._last_graph_build > self._graph_build_interval or not self._questDataLoaded then
        local player_level = self._blackboard:get("player.level", 1)
        level_range = level_range or {min = math.max(1, player_level - 5), max = player_level + 5}
        faction = faction or self._blackboard:get("player.faction", "Both")
        self._graph:buildFromDB(zone, level_range, faction)
        self._last_graph_build = now
        self._questDataLoaded = true
    end
    return self._graph
end

--- Get available quests from graph
---@return table[]
function PhaseRunner:getAvailableQuests()
    local graph = self._graph
    local available = {}
    for qid, node in pairs(graph.nodes) do
        if graph.available[qid] then
            available[#available + 1] = node
        end
    end
    return available
end

--- Get quest data accessor
---@return QuestData
function PhaseRunner:getQuestDataAccessor()
    return self._graph
end


---
function PhaseRunner:getQuestGivers(quest_id, map_id)
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
function PhaseRunner:getQuestTurnins(quest_id, map_id)
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
function PhaseRunner:getQuestData(quest_id)
    return self._client:fetch_quest(quest_id)
end

--- Determine if a quest can be turned in, checking both Questie and tracker
function PhaseRunner:canTurnIn(quest_id)
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
function PhaseRunner:getActiveQuests()
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

--- Get active quest IDs
---@return integer[]
function PhaseRunner:getActiveQuestIds()
    local tracker = self._blackboard:get("module.quest.quests", {})
    local ids = {}
    for quest_id, _ in pairs(tracker) do
        ids[#ids + 1] = quest_id
    end
    return ids
end

--- Check if quest is in log
---@param quest_id integer
---@return boolean
function PhaseRunner:isOnQuest(quest_id)
    local tracker = self._blackboard:get("module.quest.quests", {})
    return tracker[tonumber(quest_id)] ~= nil
end

--- Get quest chain for a quest
---@param quest_id integer
---@return table {backward: integer[], forward: integer[]}
function PhaseRunner:getQuestChain(quest_id)
    local graph = self._graph
    local backward = {}
    local forward = {}
    
    local current = quest_id
    while current and current > 0 do
        local edges = graph.edges[current]
        if edges and #edges.requires > 0 then
            for _, req in ipairs(edges.requires) do
                backward[#backward + 1] = req
            end
            current = edges.requires[1]
        else
            break
        end
    end
    
    current = quest_id
    while current and current > 0 do
        local edges = graph.edges[current]
        if edges and #edges.follows > 0 then
            for _, foll in ipairs(edges.follows) do
                forward[#forward + 1] = foll
            end
            current = edges.follows[1]
        else
            break
        end
    end
    
    return {backward = backward, forward = forward}
end

--- Follow a routing policy to a goal
---@param policyName string Name of routing policy
---@param goal table {x, y, z, map_id} Goal position
---@return boolean Success
function PhaseRunner:followPolicy(policyName, goal)
    local policy = self._policyLoader:load(policyName)
    if not policy then
        return false, "Policy not found: " .. policyName
    end

    local start = self._blackboard:get("player.position")
    if not start then
        return false, "No player position"
    end

    local startPos = {x = start.x, y = start.y, z = start.z, map_id = self._blackboard:get("system.map_id", 0)}
    local goalPos = {x = goal.x, y = goal.y, z = goal.z, map_id = goal.map_id or startPos.map_id}

    local path = self._client:plan_path(startPos, goalPos, policy)
    if not path then
        return false, "Path planning pending"
    end

    self._eventBus:publish("quest:NavigationStarted", {policy = policyName, goal = goalPos})
    return true
end

--- Cancel current navigation
---@return boolean
function PhaseRunner:cancelNavigation()
    self._eventBus:publish("quest:NavigationCancelled", {})
    return true
end

--- Update event detector (call from Quest:update)
function PhaseRunner:updateEvents()
    if self._eventDetector then
        self._eventDetector:update()
    end
end

--- Get quest data accessor
---@return QuestData
function PhaseRunner:getQuestDataAccessor()
    return self._graph
end

return PhaseRunner