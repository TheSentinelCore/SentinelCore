-- sentinel/ui/window.lua
-- SentinelCore main UI: Combat panel + Settings panel
-- Built on shared/ui/sentinel_ui.lua primitives

local SentinelUI = require("shared/ui/sentinel_ui")
local CombatPanel = require("ui/panels/combat_panel")
local SettingsPanel = require("ui/panels/settings_panel")

local Window = {}
Window.__index = Window

function Window:new(blackboard, event_bus)
    local o = setmetatable({}, Window)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._combat_panel = CombatPanel:new(blackboard, event_bus)
    o._settings_panel = SettingsPanel:new(blackboard, event_bus)
    o._initialized = false
    o._combat_module = nil
    return o
end

function Window:init(app)
    if self._initialized then return end

    self._combat_module = app:get_module("combat")
    self._combat = self._combat_module and self._combat_module.get_combat and self._combat_module:get_combat() or nil

    -- Initialize panels
    self._combat_panel:init(self._combat)
    self._settings_panel:init()

    self._initialized = true
    print("[Sentinel UI] Initialized")
end

function Window:tick(delta)
    if not self._initialized then return end
    self._combat_panel:tick(delta)
    self._settings_panel:tick(delta)
end

function Window:update()
    if not self._initialized then return end
    self._combat_panel:update()
    self._settings_panel:update()
end

function Window:render()
    if not self._initialized then return end
    self._combat_panel:render()
    self._settings_panel:render()
end

function Window:on_render_window()
    if not self._initialized then return end
    self._combat_panel:render_window()
    self._settings_panel:render_window()
end

function Window:on_render_menu()
    if not self._initialized then return end
    self._combat_panel:render_menu()
    self._settings_panel:render_menu()
end

function Window:on_update()
    self:update()
end

function Window:on_render()
    self:render()
end

function Window:shutdown()
    self._initialized = false
    self._combat_panel:shutdown()
    self._settings_panel:shutdown()
    self._combat_module = nil
    self._combat = nil
end

function Window:reload_ui()
    self:shutdown()
    -- Will be re-initialized on next tick
    return true
end

function Window.get_ui()
    return nil
end

return Window