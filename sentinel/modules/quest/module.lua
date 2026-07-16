local Tracker = require("modules/quest/tracker")
local Interactions = require("modules/quest/interactions")
local Engine = require("modules/quest/engine")
local QuestGraph = require("modules/quest/quest_graph")
local QuestScorer = require("modules/quest/quest_scorer")
local RuleEngine = require("modules/quest/rule_engine")
local ObjectivePlanner = require("modules/quest/objective_planner")
local QuestPlanner = require("modules/quest/quest_planner")
local Heatmap = require("modules/quest/heatmap")
local QuestProfileManager = require("modules/quest/quest_profile_manager")

local Quest = {}
Quest.__index = Quest

function Quest.new(event_bus, blackboard, nav_adapter)
    local engine = Engine.new(blackboard)
    return setmetatable({
        _event_bus = event_bus,
        _blackboard = blackboard,
        _nav_adapter = nav_adapter,
        _tracker = Tracker.new(blackboard),
        _engine = engine,
        _graph = QuestGraph.new(blackboard),
        _scorer = QuestScorer.new(blackboard),
        _rule_engine = RuleEngine,
        _objective_planner = ObjectivePlanner.new(),
        _quest_planner = QuestPlanner.new(blackboard, nav_adapter),
        _heatmap = Heatmap.new(blackboard, engine._client),
        _quest_profile_manager = QuestProfileManager.new(event_bus, blackboard),
        _subscriptions = {},
        _enabled = false,
        _last_plan_build = 0,
        _plan_build_interval = 5000, -- 5 seconds
        _current_plan = nil,
    }, Quest)
end

function Quest:initialize()
    self._enabled = self._blackboard:get("module.quest.enabled", false) == true
    self._blackboard:set("module.quest.quests", {})
    self._blackboard:set("module.quest.active_count", 0)
    self._blackboard:set("module.quest.interactions", Interactions)
    self._blackboard:set("module.quest.engine", self._engine)
    self._blackboard:set("module.quest.graph", self._graph)
    self._blackboard:set("module.quest.scorer", self._scorer)
    self._blackboard:set("module.quest.rule_engine", self._rule_engine)
    self._blackboard:set("module.quest.objective_planner", self._objective_planner)
    self._blackboard:set("module.quest.quest_planner", self._quest_planner)
    self._blackboard:set("module.quest.heatmap", self._heatmap)

    -- Initialize quest profile manager
    self._quest_profile_manager:initialize()
    self._blackboard:set("module.quest.quest_profile_manager", self._quest_profile_manager)

    self._subscriptions[#self._subscriptions + 1] = self._event_bus:subscribe("game:quest_log_update", function()
        if self._enabled then
            self._tracker:refresh(self._blackboard:get("system.now_ms", 0))
            -- Mark plan as dirty on quest log change
            self._current_plan = nil
            self._heatmap:mark_dirty()
        end
    end)
end

function Quest:update(blackboard)
    if not self._enabled then
        return
    end
    local now_ms = blackboard:get("system.now_ms", 0)
    
    -- Refresh tracker
    if now_ms - (self._tracker._last_refresh_ms or 0) >= 2000 then
        self._tracker:refresh(now_ms)
    end
    
    -- Update quest profile manager
    if self._quest_profile_manager then
        local player = blackboard:get("player.object")
        local player_level = 70
        if player and type(player.get_level) == "function" then
            local ok, lv = pcall(player.get_level, player)
            if ok and type(lv) == "number" then player_level = lv end
        end
        local map_id = blackboard:get("system.map_id", 0) or 0
        local faction = blackboard:get("player.faction", "Alliance") or "Alliance"
        
        -- Get active quest profile for current zone/level
        local profile = self._quest_profile_manager:get_active_quest_profile()
        if not profile then
            -- Try to auto-load
            self._quest_profile_manager:try_autoload(player_level, map_id, faction)
            profile = self._quest_profile_manager:get_active_quest_profile()
        end
        if profile then
            self._blackboard:set("module.quest.active_profile", profile)
        end
    end
    
    -- Rebuild quest plan if needed
    if not self._current_plan or now_ms - self._last_plan_build > self._plan_build_interval then
        local profile = blackboard:get("module.quest.active_profile")
        if profile then
            local context = {
                zone = profile.zone,
                level_range = profile.level_range,
                faction = profile.faction,
                profile = profile,
                top_k = 5,
                player_pos = blackboard:get("player.position"),
                nav_adapter = self._nav_adapter,
                quest_graph = self._graph,
            }
            
            -- Use full QuestPlanner
            local plan = self._quest_planner:plan(context)
            if plan then
                self._current_plan = plan
                self._last_plan_build = now_ms
                blackboard:set("module.quest.current_plan", plan)
                self._event_bus:publish("quest:plan_ready", {plan = plan})
            end
        end
    end
end

function Quest:get_engine()
    return self._engine
end

function Quest:get_graph()
    return self._graph
end

function Quest:get_scorer()
    return self._scorer
end

function Quest:get_objective_planner()
    return self._objective_planner
end

function Quest:get_quest_planner()
    return self._quest_planner
end

function Quest:get_heatmap()
    return self._heatmap
end

function Quest:get_current_plan()
    return self._current_plan
end

function Quest:set_enabled(enabled)
    self._enabled = enabled == true
    self._blackboard:set("module.quest.enabled", self._enabled)
    if self._enabled then
        self._tracker:refresh(self._blackboard:get("system.now_ms", 0))
        self._current_plan = nil -- Force replan on enable
    end
end

function Quest:get_tracker()
    return self._tracker
end

function Quest:shutdown()
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
    self._subscriptions = {}
    if self._quest_profile_manager then
        self._quest_profile_manager:shutdown()
    end
end

return Quest