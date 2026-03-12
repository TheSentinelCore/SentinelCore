local EventBus = require("core/event_bus")
local Blackboard = require("core/blackboard")
local ErrorBoundary = require("core/error_boundary")
local ModuleRegistry = require("runtime/module_registry")
local SensorHub = require("runtime/sensor_hub")
local CallbackBridge = require("runtime/callback_bridge")
local NavAdapter = require("integrations/nav_client/adapter")
local SentinelCombat = require("modules/combat/module")
local BattlegroundModule = require("modules/battleground/module")
local SentinelGrind = require("modules/grind/module")
local UIWindow = require("ui/window")

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
    return o
end

function SentinelApp:initialize()
    self._combat = SentinelCombat:new(self._event_bus, self._blackboard, self._nav_adapter)
    self._battleground = BattlegroundModule:new(self._event_bus, self._blackboard, self._nav_adapter)
    self._grind = SentinelGrind:new(self._event_bus, self._blackboard, self._nav_adapter)
    self._registry:register("combat", self._combat)
    self._registry:register("battleground", self._battleground)
    self._registry:register("grind", self._grind)
    self._combat:initialize()
    self._battleground:initialize()
    self._grind:initialize()
    self._ui = UIWindow
    self._ui.init(self)
end

function SentinelApp:shutdown()
    local modules = self._registry:all()
    for _, module in pairs(modules) do
        if module and type(module.shutdown) == "function" then
            module:shutdown()
        end
    end
    if self._ui and type(self._ui.shutdown) == "function" then
        self._ui.shutdown()
    end
end

function SentinelApp:on_pre_tick()
    self._callback_bridge:on_pre_tick()
end

function SentinelApp:on_update()
    self._callback_bridge:on_update()
    self._error_boundary:wrap("sensor_hub", "refresh", function()
        self._sensor_hub:refresh()
    end)
    if self._ui then
        self._error_boundary:wrap("ui", "update", function()
            self._ui.on_update()
        end)
    end
    -- Poll nav adapter so all modules see fresh nav state (is_active, get_state)
    self._nav_adapter:poll()

    self._error_boundary:wrap("battleground", "update", function()
        self._battleground:update(self._blackboard)
    end)
    self._error_boundary:wrap("grind", "update", function()
        self._grind:update(self._blackboard)
    end)
    self._error_boundary:wrap("combat", "update", function()
        self._combat:update(self._blackboard)
    end)
end

function SentinelApp:on_render()
    self._callback_bridge:on_render()
    if self._ui then
        self._error_boundary:wrap("ui", "render", function()
            self._ui.on_render()
        end)
    end
end

function SentinelApp:on_render_menu()
    self._callback_bridge:on_render_menu()
    if self._ui then
        self._error_boundary:wrap("ui", "render_menu", function()
            self._ui.on_menu_render()
        end)
    end
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

function SentinelApp:get_ui()
    return self._ui and self._ui.get_ui and self._ui.get_ui() or nil
end

return SentinelApp
