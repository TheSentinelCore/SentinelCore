local EventBus = require("core/event_bus")
local Blackboard = require("core/blackboard")
local ErrorBoundary = require("core/error_boundary")
local ModuleRegistry = require("runtime/module_registry")
local SensorHub = require("runtime/sensor_hub")
local CallbackBridge = require("runtime/callback_bridge")
local NavAdapter = require("integrations/nav_client/adapter")
local IziBridge = require("integrations/izi_bridge")

local SentinelApp = {}
SentinelApp.__index = SentinelApp

function SentinelApp:new()
    local logger = function(message)
        if core and core.log_error then
            core.log_error(message)
        end
    end
    local o = setmetatable({}, SentinelApp)
    o._event_bus = EventBus:new(logger)
    o._blackboard = Blackboard:new()
    o._error_boundary = ErrorBoundary:new(o._event_bus)
    o._registry = ModuleRegistry:new()
    o._sensor_hub = SensorHub:new(o._blackboard, o._event_bus)
    o._callback_bridge = CallbackBridge:new(o._event_bus)
    o._nav_adapter = NavAdapter:new(o._event_bus)
    o._izi_bridge = IziBridge:new()
    return o
end

function SentinelApp:initialize()
    -- Register modules declaratively via ModuleRegistry
    self._registry:register_all(self._blackboard, self._event_bus)

    -- Get module reference for direct access
    self._combat = self._registry:get("combat")

    -- Initialize modules
    self._registry:initialize_all(self)

    -- Combat module has its own initialize method
    if self._combat and self._combat.initialize then
        self._combat:initialize()
    end
end

function SentinelApp:shutdown()
    self._sensor_hub:shutdown()
    local modules = self._registry:all()
    for _, module in pairs(modules) do
        if module and type(module.shutdown) == "function" then
            module:shutdown()
        end
    end
    -- Shutdown modules via the registry
    self._registry:shutdown_all()
end

function SentinelApp:on_pre_tick()
    self._callback_bridge:on_pre_tick()
end

function SentinelApp:on_update()
    self._callback_bridge:on_update()
    self._error_boundary:wrap("sensor_hub", "refresh", function()
        self._sensor_hub:refresh()
    end)
    -- Poll nav adapter so all modules see fresh nav state
    self._nav_adapter:poll()

    if self._combat and self._combat.update then
        self._error_boundary:wrap("combat", "update", function()
            self._combat:update(self._blackboard)
        end)
    end
end

function SentinelApp:on_render()
    self._callback_bridge:on_render()
end

function SentinelApp:on_render_window()
    -- No editor UI to render in combat-only mode
end

function SentinelApp:on_render_menu()
    self._callback_bridge:on_render_menu()
end

function SentinelApp:on_spell_cast(data)
    self._callback_bridge:on_spell_cast(data)
end

function SentinelApp:on_legit_spell_cast(data)
    self._callback_bridge:on_legit_spell_cast(data)
end

function SentinelApp:get_blackboard()
    return self._blackboard
end

function SentinelApp:get_event_bus()
    return self._event_bus
end

function SentinelApp:get_module(name)
    return self._registry:get(name)
end

return SentinelApp
