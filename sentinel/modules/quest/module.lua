local Tracker = require("modules/quest/tracker")
local Interactions = require("modules/quest/interactions")
local Engine = require("modules/quest/engine")

local Quest = {}
Quest.__index = Quest

function Quest.new(event_bus, blackboard)
    return setmetatable({
        _event_bus = event_bus,
        _blackboard = blackboard,
        _tracker = Tracker.new(blackboard),
        _engine = Engine.new(blackboard),
        _subscriptions = {},
        _enabled = false,
    }, Quest)
end

function Quest:initialize()
    self._enabled = self._blackboard:get("module.quest.enabled", false) == true
    self._blackboard:set("module.quest.quests", {})
    self._blackboard:set("module.quest.active_count", 0)
    self._blackboard:set("module.quest.interactions", Interactions)
    self._blackboard:set("module.quest.engine", self._engine)

    self._subscriptions[#self._subscriptions + 1] = self._event_bus:subscribe("game:quest_log_update", function()
        if self._enabled then
            self._tracker:refresh(self._blackboard:get("system.now_ms", 0))
        end
    end)
end

function Quest:update(blackboard)
    if not self._enabled then
        return
    end
    local now_ms = blackboard:get("system.now_ms", 0)
    if now_ms - (self._tracker._last_refresh_ms or 0) >= 2000 then
        self._tracker:refresh(now_ms)
    end
end

function Quest:get_engine()
    return self._engine
end

function Quest:set_enabled(enabled)
    self._enabled = enabled == true
    self._blackboard:set("module.quest.enabled", self._enabled)
    if self._enabled then
        self._tracker:refresh(self._blackboard:get("system.now_ms", 0))
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
end

return Quest
