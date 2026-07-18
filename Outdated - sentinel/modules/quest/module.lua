-- sentinel/modules/quest/module.lua
-- Quest Module v2: Profile-based execution

local Tracker = require("modules/quest/tracker")
local Interactions = require("modules/quest/interactions")
local PhaseRunner = require("modules/quest/phase_runner")
local ProfileLoader = require("modules/quest/profile_loader")
local ProfileExecutor = require("modules/quest/profile_executor")
local QuestGraph = require("modules/quest/quest_graph") -- Read-only data accessor
local Heatmap = require("modules/quest/heatmap")
local StepExecutors = require("modules/quest/step_executors")

local Quest = {}
Quest.__index = Quest

function Quest.new(event_bus, blackboard, nav_adapter)
    local phaseRunner = PhaseRunner.new(blackboard, event_bus)
    local profileLoader = ProfileLoader.new()
    local profileExecutor = ProfileExecutor.new(blackboard, phaseRunner, nav_adapter, event_bus)
    local questGraph = QuestGraph.new(blackboard) -- Read-only data accessor
    local heatmap = Heatmap.new(blackboard)
    
    return setmetatable({
        _event_bus = event_bus,
        _blackboard = blackboard,
        _nav_adapter = nav_adapter,
        _tracker = Tracker.new(blackboard),
        _phase_runner = phaseRunner,
        _profile_loader = profileLoader,
        _profile_executor = profileExecutor,
        _graph = questGraph,
        _heatmap = heatmap,
        _step_executors = StepExecutors,
        _subscriptions = {},
        _enabled = false,
        _current_profile_id = nil,
    }, Quest)
end

function Quest:initialize()
    self._enabled = self._blackboard:get("module.quest.enabled", false) == true
    self._blackboard:set("module.quest.quests", {})
    self._blackboard:set("module.quest.active_count", 0)
    self._blackboard:set("module.quest.interactions", Interactions)
    self._blackboard:set("module.quest.phase_runner", self._phase_runner)
    self._blackboard:set("module.quest.graph", self._graph)
    self._blackboard:set("module.quest.heatmap", self._heatmap)
    self._blackboard:set("module.quest.nav_adapter", self._nav_adapter)

    self._subscriptions[#self._subscriptions + 1] = self._event_bus:subscribe("game:quest_log_update", function()
        if self._enabled then
            self._tracker:refresh(self._blackboard:get("system.now_ms", 0))
            -- Reset profile executor state on quest log change
            self._profile_executor:stop()
        end
    end)
end

local _quest_diag_last_ms = 0
local QUEST_DIAG_MS = 5000

function Quest:update(blackboard)
    local now_ms = blackboard:get("system.now_ms", 0)

    -- Throttled diagnostic
    if now_ms - _quest_diag_last_ms >= QUEST_DIAG_MS then
        _quest_diag_last_ms = now_ms
        if core and core.log then
            local bb_enabled = self._blackboard:get("module.quest.enabled")
            local executor = self._profile_executor
            local states = executor._executor and executor._executor.getActiveStates() or {}
            local stateStr = ""
            for k, v in pairs(states) do stateStr = stateStr .. k .. "=" .. v .. " " end
            pcall(core.log, string.format(
                "[Quest] DIAG: self_enabled=%s bb_enabled=%s executor_running=%s active_states=%s",
                tostring(self._enabled), tostring(bb_enabled),
                tostring(self._profile_executor._started),
                stateStr))
        end
    end

    if not self._enabled then
        return
    end
    
    -- Update phase runner events
    if self._phase_runner then
        self._phase_runner:updateEvents()
    end
    
    -- Refresh tracker
    if now_ms - (self._tracker._last_refresh_ms or 0) >= 2000 then
        local ok, err = pcall(self._tracker.refresh, self._tracker, now_ms)
        if not ok then
            pcall(core.log, "[Quest] tracker.refresh ERROR: " .. tostring(err))
        end
    end
    
    -- Update profile executor
    if self._profile_executor and self._profile_executor._started then
        self._profile_executor:update()
    end
end

function Quest:startProfile(profileId)
    local compiled = self._profile_loader:loadProfile(profileId)
    if not compiled then
        pcall(core.log, "[Quest] Failed to load profile: " .. tostring(profileId))
        return false
    end

    self._profile_executor:setProfile(compiled)
    self._current_profile_id = profileId
    self._profile_executor:start()
    
    return true
end

function Quest:stopProfile()
    self._profile_executor:stop()
    self._current_profile_id = nil
end

function Quest:getProfileExecutor()
    return self._profile_executor
end

function Quest:getPhaseRunner()
    return self._phase_runner
end

function Quest:getGraph()
    return self._graph
end

function Quest:getHeatmap()
    return self._heatmap
end

function Quest:getStepExecutors()
    return self._step_executors
end

function Quest:setEnabled(enabled)
    local was_enabled = self._enabled
    self._enabled = enabled == true
    self._blackboard:set("module.quest.enabled", self._enabled)
    if self._enabled and not was_enabled then
        self._tracker:refresh(self._blackboard:get("system.now_ms", 0))
        -- Auto-load and start active profile if configured
        if self._profile_loader then
            local activeProfile = self._profile_loader:loadActiveProfile()
            if activeProfile then
                self._profile_executor:setProfile(activeProfile)
                self._profile_executor:start()
            end
        end
    end
end

function Quest:getTracker()
    return self._tracker
end

function Quest:shutdown()
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
    self._subscriptions = {}
    if self._profile_executor then
        self._profile_executor:stop()
    end
    if self._phase_runner then
        self._phase_runner:shutdown()
    end
end

return Quest