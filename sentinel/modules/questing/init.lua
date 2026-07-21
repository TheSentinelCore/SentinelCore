-- modules/questing/init.lua
-- Questing module entry point for ModuleRegistry
-- Wraps questing runtime with the registry interface

local QuestingModule = require("modules/questing/module")

local QuestingModuleInit = {}
QuestingModuleInit.__index = QuestingModuleInit

function QuestingModuleInit:new(blackboard, event_bus)
    local o = setmetatable({}, QuestingModuleInit)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._questing = QuestingModule:new(blackboard, event_bus)
    return o
end

function QuestingModuleInit:init()
    -- Questing module initializes on-demand via profile loading
    self._initialized = true
end

function QuestingModuleInit:tick(delta)
    if not self._initialized then return end
    self._questing:tick(delta)
end

function QuestingModuleInit:shutdown()
    if self._questing then
        self._questing:shutdown()
    end
end

return QuestingModuleInit