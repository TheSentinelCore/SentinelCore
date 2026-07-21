--- Sentinel Questing Runtime Context
--- Extends RuntimeContext to include Questing module lifecycle

local RuntimeContext = require("runtime/runtime_context")
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local ModuleRegistry = require("runtime/module_registry")

local QuestingRuntimeContext = {}
QuestingRuntimeContext.__index = QuestingRuntimeContext

function QuestingRuntimeContext:new()
    local blackboard = Blackboard:new()
    local event_bus = EventBus:new(function(msg)
        if core and core.print then
            core.print("[QuestingRuntime] " .. tostring(msg))
        end
    end)
    local o = setmetatable({}, QuestingRuntimeContext)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._registry = ModuleRegistry:new()
    o._initialized = false
    o._questing_enabled = false
    return o
end

function QuestingRuntimeContext:get_blackboard()
    return self._blackboard
end

function QuestingRuntimeContext:get_event_bus()
    return self._event_bus
end

function QuestingRuntimeContext:initialize()
    if self._initialized then
        return true
    end
    self._registry:register_all(self._blackboard, self._event_bus)
    self._registry:initialize_all({
        get_blackboard = function() return self._blackboard end,
        get_event_bus = function() return self._event_bus end,
    })
    self._initialized = true
    return true
end

function QuestingRuntimeContext:shutdown()
    self._registry:shutdown_all()
    self._initialized = false
end

function QuestingRuntimeContext:tick(delta)
    if not self._initialized then return end
    self._registry:tick_all(delta)
end

--- Enable questing module and load a profile
function QuestingRuntimeContext:enable_questing(profile_path)
    self._questing_enabled = true
    self._blackboard:set("questing.enabled", true)

    -- Get the questing module
    local questing_module = self._registry:get("questing")
    if not questing_module then
        if core and core.print then
            core.print("[QuestingRuntime] ERROR: questing module not found")
        end
        return false
    end

    -- Initialize with profile
    return questing_module._questing:initialize(profile_path)
end

function QuestingRuntimeContext:disable_questing()
    self._questing_enabled = false
    self._blackboard:set("questing.enabled", false)
end

return QuestingRuntimeContext