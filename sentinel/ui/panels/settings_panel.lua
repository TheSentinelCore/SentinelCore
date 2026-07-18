-- sentinel/ui/panels/settings_panel.lua
-- Global settings panel

local SentinelUI = require("shared/ui/sentinel_ui")

local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel

function SettingsPanel:new(blackboard, event_bus)
    local o = setmetatable({}, SettingsPanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    return o
end

function SettingsPanel:init()
    self._ui = SentinelUI.new({
        id = "sentinel_settings",
        title = "Sentinel Settings",
        default_x = 600,
        default_y = 100,
        default_w = 450,
        default_h = 500,
        theme = "sentinel",
    })

    -- General tab
    self._ui:add_tab({ id = "general", label = "General" }, function(t)
        local humanization = self._ui.menu.checkbox(true, "sentinel_settings_humanization")
        local debug = self._ui.menu.checkbox(false, "sentinel_settings_debug")
        local nav_debug = self._ui.menu.checkbox(false, "sentinel_settings_nav_debug")

        t:keybind_grid({
            elements = {
                self._ui.menu.slider_int(0, 999, 999, "sentinel_settings_toggle_ui_key"),
                self._ui.menu.slider_int(0, 999, 999, "sentinel_settings_reload_key"),
            },
            labels = { "Toggle UI", "Reload Sentinel" }
        })

        t:checkbox_grid({
            label = "Core",
            columns = 2,
            elements = {
                { element = humanization, label = "Humanization" },
                { element = debug, label = "Debug Mode" },
                { element = nav_debug, label = "Nav Debug" },
            }
        })
    end)

    -- Navigation tab
    self._ui:add_tab({ id = "navigation", label = "Navigation" }, function(t)
        t:slider_list({
            label = "Pathfinding",
            elements = {
                { element = self._ui.menu.slider_int(100, 5000, 500, "sentinel_settings_path_interval"), label = "Path Interval", suffix = "ms" },
                { element = self._ui.menu.slider_int(1, 10, 3, "sentinel_settings_waypoint_tolerance"), label = "Waypoint Tolerance", suffix = "yd" },
            }
        })
    end)

    -- UI tab
    self._ui:add_tab({ id = "ui", label = "UI" }, function(t)
        t:slider_list({
            label = "Appearance",
            elements = {
                { element = self._ui.menu.slider_int(50, 150, 100, "sentinel_settings_ui_scale"), label = "UI Scale", suffix = "%" },
                { element = self._ui.menu.slider_int(1, 6, 6, "sentinel_settings_ui_theme"), label = "Theme (1=rogue,2=neutral,3=hunter,4=astro,5=apple,6=sentinel)", min = 1, max = 6 },
            }
        })
    end)

    return true
end

function SettingsPanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function SettingsPanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
end

function SettingsPanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function SettingsPanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function SettingsPanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function SettingsPanel:shutdown()
    self._ui = nil
end

return SettingsPanel