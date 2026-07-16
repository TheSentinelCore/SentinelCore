local QuestGraph = require("modules/quest/quest_graph")

local QuestScorer = {}
QuestScorer.__index = QuestScorer

---Default scoring weights
---@type table<string, number>
QuestScorer.DEFAULT_WEIGHTS = {
    xp_per_minute = 0.35,
    travel_efficiency = 0.25,
    objective_overlap = 0.20,
    reward_value = 0.10,
    chain_priority = 0.10,
}

---Heuristic constants
local HEURISTICS = {
    base_death_prob = 0.05,
    level_diff_per_level = 0.15,
    elite_bonus = 0.35,
    dungeon_bonus = 0.40,
    cave_bonus = 0.20,
    mob_count_bonus = 0.10,
    class_squishiness = {
        MAGE = 0.15,
        WARLOCK = 0.10,
        PRIEST = 0.10,
        DRUID = 0.05,
        HUNTER = 0.05,
        ROGUE = 0.05,
        SHAMAN = 0.0,
        PALADIN = -0.05,
        WARRIOR = -0.10,
    },
}

---Create new QuestScorer
---@param weights table|nil Optional weight overrides
---@return QuestScorer
function QuestScorer.new(weights)
    return setmetatable({
        weights = weights or QuestScorer.DEFAULT_WEIGHTS,
    }, QuestScorer)
end

---Score a quest node given context
---@param node table QuestNode from QuestGraph
---@param context table {player_pos, player_level, nav_adapter, active_quests, profile}
---@return number score
function QuestScorer:score(node, context)
    local weights = self.weights
    local profile = context.profile
    
    -- Use profile weights if provided
    if profile and profile.scoring then
        for k, v in pairs(profile.scoring) do
            weights[k] = v
        end
    end
    
    local scores = {}
    
    -- 1. XP per minute
    scores.xp_per_minute = self:_score_xp_per_minute(node, context)
    
    -- 2. Travel efficiency (negative = penalty)
    scores.travel_efficiency = self:_score_travel(node, context)
    
    -- 3. Objective overlap with other active quests
    scores.objective_overlap = self:_score_overlap(node, context)
    
    -- 4. Reward value (vendor price of choices + fixed money)
    scores.reward_value = self:_score_rewards(node, context)
    
    -- 5. Chain priority (depth in chain * followup XP)
    scores.chain_priority = self:_score_chain(node, context)
    
    -- Death risk penalty (subtracted)
    local death_risk = self:_estimate_death_risk(node, context)
    local difficulty = self:_estimate_difficulty(node, context)
    
    -- Weighted sum
    local total = 0
    total = total + (scores.xp_per_minute or 0) * (weights.xp_per_minute or 0)
    total = total + (scores.travel_efficiency or 0) * (weights.travel_efficiency or 0)
    total = total + (scores.objective_overlap or 0) * (weights.objective_overlap or 0)
    total = total + (scores.reward_value or 0) * (weights.reward_value or 0)
    total = total + (scores.chain_priority or 0) * (weights.chain_priority or 0)
    
    -- Penalties
    total = total - death_risk * 50 -- Heavy penalty for death risk
    total = total - difficulty * 10
    
    -- Hard filters from profile
    if profile and profile.rules then
        if profile.rules.skip_elites and node.is_elite then return -9999 end
        if profile.rules.skip_dungeon_chains and node.is_dungeon then return -9999 end
        if profile.rules.max_travel_yards then
            local dist = self:_estimate_travel_distance(node, context)
            if dist > profile.rules.max_travel_yards then return -9999 end
        end
        if profile.rules.min_xp_per_minute then
            if scores.xp_per_minute < profile.rules.min_xp_per_minute then return -9999 end
        end
    end
    
    return math.max(0, total)
end

---Score all quests and return sorted
---@param nodes table[] QuestNodes
---@param context table
---@return table[] {node, score}
function QuestScorer:score_all(nodes, context)
    local results = {}
    for _, node in ipairs(nodes) do
        local score = self:score(node, context)
        if score > 0 then
            results[#results + 1] = {node = node, score = score}
        end
    end
    
    table.sort(results, function(a, b) return a.score > b.score end)
    return results
end

---Estimate XP per minute for a quest
---@param node table
---@param context table
---@return number
function QuestScorer:_score_xp_per_minute(node, context)
    local xp = node.rewards and node.rewards.xp or 0
    local est_time = self:_estimate_completion_time(node, context)
    if est_time <= 0 then return 0 end
    return (xp / est_time) * 60 -- XP per minute
end

---Estimate completion time in minutes
---@param node table
---@param context table
---@return number
function QuestScorer:_estimate_completion_time(node, context)
    local travel = self:_estimate_travel_distance(node, context) / 100 -- ~100 yd/min walking
    local combat = 0
    
    for _, obj in ipairs(node.objectives) do
        if obj.type == "KILL" then
            combat = combat + (obj.count * 0.5) -- ~30 sec per kill
        elseif obj.type == "COLLECT" then
            combat = combat + (obj.count * 0.3) -- ~20 sec per collect
        elseif obj.type == "ESCORT" then
            combat = combat + 5 -- Escort takes ~5 min
        end
    end
    
    return travel + combat
end

---Estimate total travel distance for quest
---@param node table
---@param context table
---@return number
function QuestScorer:_estimate_travel_distance(node, context)
    local player_pos = context.player_pos
    if not player_pos then return 9999 end
    
    local dist = 0
    
    -- To start NPC
    if node.start_npc then
        dist = dist + self:_distance(player_pos, node.start_npc)
    end
    
    -- Between objectives (rough estimate)
    local last_pos = node.start_npc or player_pos
    for _, obj in ipairs(node.objectives) do
        -- Would need spawn cluster centers - estimate 100yd per objective
        dist = dist + 100
    end
    
    -- To turn-in NPC
    if node.end_npc then
        dist = dist + self:_distance(last_pos, node.end_npc)
    end
    
    return dist
end

---Score travel efficiency (higher = less travel per XP)
---@param node table
---@param context table
---@return number
function QuestScorer:_score_travel(node, context)
    local dist = self:_estimate_travel_distance(node, context)
    local xp = node.rewards and node.rewards.xp or 1
    -- Inverse: less distance per XP = higher score
    if dist <= 0 then return 1 end
    return (xp / dist) * 1000
end

---Score objective overlap with other active quests
---@param node table
---@param context table
---@return number
function QuestScorer:_score_overlap(node, context)
    local active = context.active_quests or {}
    local overlap_count = 0
    
    for _, other_node in ipairs(active) do
        if other_node.id ~= node.id then
            for _, obj in ipairs(node.objectives) do
                for _, other_obj in ipairs(other_node.objectives) do
                    if obj.target_id == other_obj.target_id 
                    or obj.item_id == other_obj.item_id then
                        overlap_count = overlap_count + 1
                    end
                end
            end
        end
    end
    
    return overlap_count * 0.5 -- 0.5 per overlapping objective
end

---Score reward value
---@param node table
---@param context table
---@return number
function QuestScorer:_score_rewards(node, context)
    local value = 0
    
    -- Fixed money reward
    value = value + (node.rewards and node.rewards.money or 0)
    
    -- Choice rewards - estimate vendor value
    if node.rewards and node.rewards.choices then
        for _, choice in ipairs(node.rewards.choices) do
            -- Would need item DB for vendor price - estimate by item level
            value = value + (choice.count or 1) * 100 -- 1s per item base
        end
    end
    
    -- Fixed item rewards
    if node.rewards and node.rewards.fixed then
        for _, item in ipairs(node.rewards.fixed) do
            value = value + (item.count or 1) * 100
        end
    end
    
    return value / 10000 -- Convert to gold
end

---Score chain priority
---@param node table
---@param context table
---@return number
function QuestScorer:_score_chain(node, context)
    local score = 0
    local graph = context.quest_graph
    
    if graph then
        -- Follow chain forward and sum estimated XP
        local chain = graph:get_chain(node.id)
        for _, n in ipairs(chain.forwards) do
            score = score + (n.rewards and n.rewards.xp or 0)
        end
    end
    
    -- Also consider depth (how many prerequisites done)
    local depth = 0
    local current = node.id
    while current > 0 and graph and graph.nodes[current] do
        local n = graph.nodes[current]
        if n.prev_quest_id > 0 then
            depth = depth + 1
            current = n.prev_quest_id
        else
            break
        end
    end
    
    return score / 1000 + depth * 0.1
end

---Estimate death probability (0-1)
---@param node table
---@param context table
---@return number
function QuestScorer:_estimate_death_risk(node, context)
    local risk = HEURISTICS.base_death_prob
    local player_level = context.player_level or 1
    local _, class = UnitClass("player")
    
    for _, obj in ipairs(node.objectives) do
        if obj.type == "KILL" and obj.target_id then
            -- Would query creature_template for level/rank
            -- For now, use heuristics
            if node.is_elite then risk = risk + HEURISTICS.elite_bonus end
            if node.is_dungeon then risk = risk + HEURISTICS.dungeon_bonus end
            
            -- Level difference
            -- local mob_level = self:_get_mob_level(obj.target_id)
            -- if mob_level and mob_level > player_level + 2 then
            --     risk = risk + (mob_level - player_level - 2) * HEURISTICS.level_diff_per_level
            -- end
        end
    end
    
    -- Cave/indoor
    -- Would check zone type
    
    -- Class squishiness
    risk = risk + (HEURISTICS.class_squishiness[class] or 0)
    
    return math.min(0.9, risk)
end

---Estimate difficulty (0-10)
---@param node table
---@param context table
---@return number
function QuestScorer:_estimate_difficulty(node, context)
    local diff = 0
    
    if node.suggested_players > 1 then diff = diff + 3 end
    if node.is_elite then diff = diff + 4 end
    if node.is_dungeon then diff = diff + 5 end
    
    -- Count objectives
    diff = diff + #node.objectives * 0.5
    
    return math.min(10, diff)
end

---3D distance helper
---@param a table {x,y,z}
---@param b table {x,y,z}
---@return number
function QuestScorer:_distance(a, b)
    if not a or not b then return 9999 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

return QuestScorer