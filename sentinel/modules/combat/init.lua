-- modules/combat/init.lua
-- Combat module entry point for ModuleRegistry
-- Wraps SentinelCombat with the registry interface: init(blackboard, event_bus) -> module

local SentinelCombat = require("modules/combat/module")
local NavAdapter = require("integrations/nav_client/adapter")
local IziBridge = require("integrations/izi_bridge")

local CombatModule = {}
CombatModule.__index = CombatModule

function CombatModule:new(blackboard, event_bus)
    local o = setmetatable({}, CombatModule)
    o._blackboard = blackboard
    o._event_bus = event_bus
    -- B4: shared adapter keyed by event_bus -- same instance SentinelApp holds when
    -- this event_bus is the shared app bus (see integrations/nav_client/adapter.lua).
    o._nav_adapter = NavAdapter.get_shared(event_bus)
    o._izi_bridge = IziBridge:new()
    o._combat = SentinelCombat:new(event_bus, blackboard, o._nav_adapter, o._izi_bridge)
    return o
end

function CombatModule:init()
    self._combat:initialize()
    self._initialized = true
end

function CombatModule:tick(delta)
    if not self._initialized then return end
    self._combat:update(self._blackboard)
end

function CombatModule:shutdown()
    if self._combat then
        self._combat:shutdown()
    end
end

function CombatModule:get_combat()
    return self._combat
end

return CombatModule