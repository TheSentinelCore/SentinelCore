local Questie = require("modules/quest/questie_adapter")
local QueryClient = require("modules/quest/query_client")
local QuestGraph = require("modules/quest/quest_graph")
local QuestScorer = require("modules/quest/quest_scorer")
local RuleEngine = require("modules/quest/rule_engine")

local Engine = {}
Engine.__index = Engine

function Engine.new(blackboard)
    return setmetatable({
        _blackboard = blackboard,
        _client = QueryClient.new(blackboard),
        _route_cache = {},
        _graph = QuestGraph.new(blackboard),
        _scorer = QuestScorer.new(blackboard),
        _rule_engine = RuleEngine,
        _last_graph_build = 0,
        _graph_build_interval = 30000, -- 30 seconds
    }, Engine)
end

--- Get or build the quest graph for current zone/level
---@param zone string|nil
---@param level_range table|nil {min, max}
---@param faction string|nil
---@return QuestGraph
function Engine:get_quest_graph(zone, level_range, faction)
    local now = self._blackboard:get("system.now_ms", 0)
    if now - self._last_graph_build > self._graph_build_interval or not next(self._graph.nodes) then
        local player_level = self._blackboard:get("player.level", 1)
        level_range = level_range or {min = math.max(1, player_level - 5), max = player_level + 5}
        faction = faction or self._blackboard:get("player.faction", "Both")
        self._graph:build_from_db(zone, level_range, faction)
        self._last_graph_build = now
    end
    return self._graph
end

--- Get available quests from graph
---@return table[]
function Engine:get_available_quests()
    local graph = self._graph
    local available = {}
    for qid, node in pairs(graph.nodes) do
        if graph.available[qid] then
            available[#available + 1] = node
        end
    end
    return available
end

--- Get quest graph instance
---@return QuestGraph
function Engine:get_graph()
    return self._graph
end

--- Get scorer instance
---@return QuestScorer
function Engine:get_scorer()
    return self._scorer
end

--- Get rule engine
---@return table
function Engine:get_rule_engine()
    return self._rule_engine
end

--- Build a complete quest plan
---@param context table
---@return table|nil QuestPlan
function Engine:build_plan(context)
    context = context or {}
    local graph = self:get_quest_graph(context.zone, context.level_range, context.faction)
    local available = self:get_available_quests()
    
    if #available == 0 then return nil end
    
    -- Score all available quests
    local scored = self._scorer:score_all(available, context)
    
    -- Filter by rules
    local profile = context.profile
    if profile then
        scored = self._rule_engine.filter_quests(scored, profile, context)
    end
    
    -- Take top K
    local top_k = context.top_k or 5
    local selected = {}
    for i = 1, math.min(top_k, #scored) do
        selected[#selected + 1] = scored[i].node
    end
    
    if #selected == 0 then return nil end
    
    -- Build plan (simplified - full planner in quest_planner.lua)
    return {
        quests = selected,
        current_quest = selected[1],
        phases = {},
        score = scored[1] and scored[1].score or 0,
        created_at = self._blackboard:get("system.now_ms", 0),
    }
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

--- Get active quest IDs
---@return integer[]
function Engine:get_active_quest_ids()
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
function Engine:is_on_quest(quest_id)
    local tracker = self._blackboard:get("module.quest.quests", {})
    return tracker[tonumber(quest_id)] ~= nil
end

--- Get quest chain for a quest
---@param quest_id integer
---@return table {backward: integer[], forward: integer[]}
function Engine:get_quest_chain(quest_id)
    local graph = self._graph
    local backward = {}
    local forward = {}
    
    -- Walk backward (prerequisites)
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
    
    -- Walk forward (follow-ups)
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

return Engine