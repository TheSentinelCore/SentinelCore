-- modules/questing/init.lua
-- Questing module entry point for ModuleRegistry
-- Wraps questing runtime with the registry interface

local QuestingModule = require("modules/questing/module")

local QuestingModuleInit = {}
QuestingModuleInit.__index = QuestingModuleInit

-- RE2: fixed boot-time profile path. The in-game profile-picker UI is out of
-- scope here; until it exists, the registry auto-loads whatever compiled
-- RuntimeProfile JSON is staged at this path. A missing/unreadable file is
-- not fatal — QuestingModule:initialize logs "questing:error" and the module
-- stays disabled until a profile is loaded via the editor (load_compiled_profile).
QuestingModuleInit.DEFAULT_PROFILE_PATH = "SentinelCore/questing/active_profile.json"

function QuestingModuleInit:new(blackboard, event_bus)
    local o = setmetatable({}, QuestingModuleInit)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._questing = QuestingModule:new(blackboard, event_bus)
    return o
end

function QuestingModuleInit:init()
    -- RE2: actually initialize the questing module. Previously this only set
    -- a flag and never called QuestingModule:initialize, so the registry's
    -- boot chain (SentinelApp → ModuleRegistry → QuestingModule) never
    -- loaded a profile and questing never ran.
    self._initialized = true
    self._questing:initialize(QuestingModuleInit.DEFAULT_PROFILE_PATH)
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