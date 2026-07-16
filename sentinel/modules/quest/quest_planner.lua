local QuestGraph = require("modules/quest/quest_graph")
local QuestScorer = require("modules/quest/quest_scorer")
local RuleEngine = require("modules/quest/rule_engine")
local ObjectivePlanner = require("modules/quest/objective_planner")

local QuestPlanner = {}
QuestPlanner.__index = QuestPlanner

---Create new QuestPlanner
---@param blackboard table
---@param nav_adapter table|nil
---@return QuestPlanner
function QuestPlanner.new(blackboard, nav_adapter)
    return setmetatable({
        _blackboard = blackboard,
        _nav_adapter = nav_adapter,
        _graph = QuestGraph.new(blackboard),
        _scorer = QuestScorer.new(blackboard),
        _rule_engine = RuleEngine,
        _objective_planner = ObjectivePlanner.new(),
        _last_plan = nil,
        _last_plan_time = 0,
        _plan_interval = 5000, -- 5 seconds
    }, QuestPlanner)
end

---Build a complete quest plan for current zone/level
---@param context table {zone, level_range, faction, player_pos, top_k, profile}
---@return table|nil QuestPlan
function QuestPlanner:plan(context)
    local now = self._blackboard:get("system.now_ms", 0)
    if self._last_plan and now - self._last_plan_time < self._plan_interval then
        return self._last_plan
    end
    
    context = context or {}
    local player_level = self._blackboard:get("player.level", 1)
    local player_pos = context.player_pos or self._blackboard:get("player.position")
    
    -- Build quest graph for zone
    local zone = context.zone
    local level_range = context.level_range or {min = math.max(1, player_level - 5), max = player_level + 5}
    local faction = context.faction or self._blackboard:get("player.faction", "Both")
    local profile = context.profile
    
    self._graph:build_from_db(zone, level_range, faction)
    local available = self._graph:get_available_quests()
    
    if #available == 0 then
        return nil
    end
    
    -- Score all available quests
    local score_context = {
        player_pos = player_pos,
        player_level = player_level,
        active_quests = self._graph:get_active_quests(),
        profile = profile,
        nav_adapter = self._nav_adapter,
        quest_graph = self._graph,
    }
    
    local scored = self._scorer:score_all(available, score_context)
    
    -- Apply rule engine filters
    if profile then
        scored = self._rule_engine.filter_quests(scored, profile, score_context)
    end
    
    if #scored == 0 then
        return nil
    end
    
    -- Select top K quests
    local top_k = context.top_k or 5
    local selected = {}
    for i = 1, math.min(top_k, #scored) do
        selected[#selected + 1] = scored[i].node
    end
    
    -- Build phases for each selected quest using ObjectivePlanner
    local all_objectives = {}
    for _, quest in ipairs(selected) do
        for _, obj in ipairs(quest.objectives) do
            obj.quest_id = quest.id
            obj.quest_title = quest.title
            all_objectives[#all_objectives + 1] = obj
        end
    end
    
    -- Plan objective clusters and routes
    local strategy = profile and profile.objective_strategy or "cluster"
    local plan = self._objective_planner:plan(all_objectives, player_pos, self._nav_adapter, strategy)
    
    -- Convert to QuestPlan format
    local quest_plan = self:_build_quest_plan(selected, plan, scored, context)
    
    self._last_plan = quest_plan
    self._last_plan_time = now
    
    self._blackboard:set("module.quest.current_plan", quest_plan)
    self._blackboard:get("event_bus"):publish("quest:plan_ready", {plan = quest_plan})
    
    return quest_plan
end

---Build QuestPlan from selected quests and objective plan
---@param selected table[] QuestNodes
---@param obj_plan table ObjectivePlanner output
---@param scored table Scored quests
---@param context table
---@return table QuestPlan
function QuestPlanner:_build_quest_plan(selected, obj_plan, scored, context)
    local phases = {}
    local current_phase = 1
    
    -- Group objectives by quest for phase ordering
    local quest_objectives = {}
    for _, obj in ipairs(obj_plan.all_objectives or {}) do
        local qid = obj.quest_id
        if not quest_objectives[qid] then quest_objectives[qid] = {} end
        quest_objectives[qid][#quest_objectives[qid] + 1] = obj
    end
    
    -- For each quest in priority order, add phases
    for _, scored_item in ipairs(scored) do
        local quest = scored_item.node
        local qid = quest.id
        
        -- Phase 1: Travel to quest giver
        if quest.start_npc then
            phases[#phases + 1] = {
                type = "TRAVEL_TO_GIVER",
                quest_id = qid,
                target = {x = quest.start_npc.x, y = quest.start_npc.y, z = quest.start_npc.z},
                waypoints = self:_get_waypoints(context.player_pos, quest.start_npc),
                constraints = {avoid_elites = true, avoid_water = true},
            }
        end
        
        -- Phase 2: Accept quest
        phases[#phases + 1] = {
            type = "INTERACT_ACCEPT",
            quest_id = qid,
            npc_id = quest.start_npc and quest.start_npc.id,
        }
        
        -- Phase 3: Objectives (from objective planner clusters)
        local quest_objs = quest_objectives[qid] or {}
        if #quest_objs > 0 then
            local obj_phases = self:_build_objective_phases(quest, quest_objs, obj_plan)
            for _, p in ipairs(obj_phases) do
                phases[#phases + 1] = p
            end
        end
        
        -- Phase 4: Travel to turn-in
        if quest.end_npc then
            phases[#phases + 1] = {
                type = "TRAVEL_TO_TURNIN",
                quest_id = qid,
                target = {x = quest.end_npc.x, y = quest.end_npc.y, z = quest.end_npc.z},
                waypoints = self:_get_waypoints(quest.start_npc, quest.end_npc),
                constraints = {avoid_elites = true, avoid_water = true},
            }
        end
        
        -- Phase 5: Turn in
        phases[#phases + 1] = {
            type = "INTERACT_TURNIN",
            quest_id = qid,
            npc_id = quest.end_npc and quest.end_npc.id,
            reward_choice = self:_select_reward(quest),
        }
    end
    
    -- Calculate total score
    local total_score = 0
    for _, s in ipairs(scored) do
        total_score = total_score + (s.score or 0)
    end
    
    return {
        quests = selected,
        phases = phases,
        current_phase = 1,
        score = total_score,
        estimated_time_min = self:_estimate_total_time(phases),
        overlaps = self:_find_overlaps(selected),
        created_at = self._blackboard:get("system.now_ms", 0),
        objective_plan = obj_plan,
    }
end

---Build objective phases from clustered objectives
---@param quest table
---@param objectives table[]
---@param obj_plan table
---@return table[]
function QuestPlanner:_build_objective_phases(quest, objectives, obj_plan)
    local phases = {}
    
    -- Group by cluster from objective plan
    local clusters = obj_plan.clusters or {}
    local obj_to_cluster = {}
    for ci, cluster in ipairs(clusters) do
        for _, obj in ipairs(cluster.objectives) do
            obj_to_cluster[obj] = ci
        end
    end
    
    -- For each cluster, create travel + objective phases
    for ci, cluster in ipairs(clusters) do
        local cluster_objs = cluster.objectives or {}
        local quest_cluster_objs = {}
        
        -- Filter to this quest's objectives
        for _, obj in ipairs(cluster_objs) do
            if obj.quest_id == quest.id then
                quest_cluster_objs[#quest_cluster_objs + 1] = obj
            end
        end
        
        if #quest_cluster_objs == 0 then goto continue end
        
        -- Travel to cluster
        phases[#phases + 1] = {
            type = "TRAVEL_TO_OBJECTIVE",
            quest_id = quest.id,
            cluster_id = ci,
            target = cluster.center,
            waypoints = cluster.waypoints,
            constraints = {avoid_elites = true, avoid_water = true},
        }
        
        -- Objective phases
        for _, obj in ipairs(quest_cluster_objs) do
            if obj.type == "KILL" then
                phases[#phases + 1] = {
                    type = "OBJECTIVE_KILL",
                    quest_id = quest.id,
                    target_id = obj.target_id,
                    count = obj.count,
                    area = {center = cluster.center, radius = cluster.radius or 80},
                    waypoints = cluster.waypoints,
                }
            elseif obj.type == "COLLECT" then
                phases[#phases + 1] = {
                    type = "OBJECTIVE_COLLECT",
                    quest_id = quest.id,
                    item_id = obj.item_id,
                    count = obj.count,
                    sources = obj.sources,
                    area = {center = cluster.center, radius = cluster.radius or 80},
                }
            elseif obj.type == "ESCORT" then
                phases[#phases + 1] = {
                    type = "OBJECTIVE_ESCORT",
                    quest_id = quest.id,
                    npc_id = obj.target_id,
                    waypoints = obj.waypoints,
                }
            end
        end
        
        ::continue::
    end
    
    return phases
end

---Select reward for quest
---@param quest table
---@return integer choice_index
function QuestPlanner:_select_reward(quest)
    -- Delegate to RewardSelector (to be implemented)
    if quest.rewards and #quest.rewards.choices > 0 then
        return 1 -- Default first choice, RewardSelector will override
    end
    return 0
end

---Estimate total time for plan
---@param phases table[]
---@return number minutes
function QuestPlanner:_estimate_total_time(phases)
    local time = 0
    for _, phase in ipairs(phases) do
        if phase.type:match("^TRAVEL") then
            time = time + 2 -- ~2 min per travel
        elseif phase.type:match("^OBJECTIVE") then
            time = time + 5 -- ~5 min per objective
        elseif phase.type:match("^INTERACT") then
            time = time + 0.5 -- 30 sec per interaction
        end
    end
    return time
end

---Find quest overlaps (shared objectives)
---@param quests table[]
---@return table[]
function QuestPlanner:_find_overlaps(quests)
    local overlaps = {}
    for i, q1 in ipairs(quests) do
        for j = i + 1, #quests do
            local q2 = quests[j]
            local shared = 0
            for _, o1 in ipairs(q1.objectives) do
                for _, o2 in ipairs(q2.objectives) do
                    if o1.target_id == o2.target_id or o1.item_id == o2.item_id then
                        shared = shared + 1
                    end
                end
            end
            if shared > 0 then
                overlaps[#overlaps + 1] = {q1.id, q2.id, shared = shared}
            end
        end
    end
    return overlaps
end

---Get waypoints between two positions (via NavAdapter)
---@param from table
---@param to table
---@return table[]
function QuestPlanner:_get_waypoints(from, to)
    if not self._nav_adapter or not from or not to then return {} end
    -- Would call nav_adapter:plan_route or similar
    -- For now return direct path
    return {from, to}
end

---Get current active plan
---@return table|nil
function QuestPlanner:get_current_plan()
    return self._last_plan
end

---Force replan (clear cache)
function QuestPlanner:force_replan()
    self._last_plan = nil
    self._last_plan_time = 0
end

return QuestPlanner