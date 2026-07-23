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
    -- B4: shared adapter (see integrations/nav_client/adapter.lua) so combat and
    -- questing stop stealing the nav client from each other via private instances.
    o._nav_adapter = NavAdapter.get_shared(o._event_bus)
    o._izi_bridge = IziBridge:new()
    return o
end

function SentinelApp:initialize()
    -- Register modules declaratively via ModuleRegistry
    self._registry:register_all(self._blackboard, self._event_bus)

    -- Get module reference for direct access. NOTE: this is the registry's module
    -- WRAPPER (modules/combat/init.lua), whose interface is init/tick/shutdown --
    -- not a raw SentinelCombat. Use :get_combat() to reach the engine itself.
    self._combat = self._registry:get("combat")

    -- Initialize modules. register_all/initialize_all already drives each wrapper's
    -- init(), which is what calls SentinelCombat:initialize().
    self._registry:initialize_all(self)
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

    -- Drive every registered module (combat, questing) AFTER sensors and nav are
    -- fresh, so a tick always sees the current frame.
    --
    -- This used to special-case combat with `if self._combat.update then ...`.
    -- self._combat is the registry WRAPPER, which has no `update` method -- the
    -- guard was always false, so combat never ticked; and tick_all was never
    -- called, so questing never ticked either. Nothing in the registry had ever
    -- run: questing would engage combat, the state machine would sit at ENGAGING
    -- forever, and no spell was ever cast. SensorHub refreshes directly above,
    -- so system.now_ms kept advancing and the loop looked alive.
    local delta_ms = 0
    if core and type(core.delta_time) == "function" then
        local ok, delta = pcall(core.delta_time)
        if ok and tonumber(delta) then
            delta_ms = math.floor(tonumber(delta) * 1000)
        end
    end
    self._error_boundary:wrap("registry", "tick_all", function()
        self._registry:tick_all(delta_ms)
    end)
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
