-- sentinel/ui/window.lua
-- SentinelCore main UI: Combat panel + Settings panel + Panel System
-- Built on shared/ui/sentinel_ui.lua primitives

local SentinelUI = require("shared/ui/sentinel_ui")
local CombatPanel = require("ui/panels/combat_panel")
local SettingsPanel = require("ui/panels/settings_panel")

local Window = {}
Window.__index = Window

-- Panel registry: tracks all registered panels and their state
local PanelRegistry = {}
PanelRegistry.__index = PanelRegistry

function PanelRegistry:new()
    local o = setmetatable({}, PanelRegistry)
    o._panels = {}
    return o
end

function PanelRegistry:register(name, render_fn, options)
    if not name or not render_fn then
        return nil, "name and render_fn required"
    end

    options = options or {}

    local panel = {
        name = name,
        visible = options.default_visible ~= false,
        render_fn = render_fn,
        render_window_fn = options.render_window_fn,
        options = {
            default_visible = options.default_visible ~= false,
            dock = options.dock or "center",
            width = options.width,
            height = options.height,
            title = options.title,
        },
        frame = nil,
        width = options.width,
        height = options.height,
    }

    self._panels[name] = panel
    return panel
end

function PanelRegistry:get(name)
    return self._panels[name]
end

function PanelRegistry:set(name, panel)
    self._panels[name] = panel
end

function PanelRegistry:all()
    return self._panels
end

function PanelRegistry:names()
    local result = {}
    for name, _ in pairs(self._panels) do
        table.insert(result, name)
    end
    return result
end

function Window:new(blackboard, event_bus)
    local o = setmetatable({}, Window)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._combat_panel = CombatPanel:new(blackboard, event_bus)
    o._settings_panel = SettingsPanel:new(blackboard, event_bus)
    o._initialized = false
    o._combat_module = nil
    o._panel_registry = PanelRegistry:new()
    o._toolbar = nil
    -- Editor panels (quest authoring UI). Each is an independent window that
    -- renders via its SentinelUI instance. Registered in init().
    o._editor_panel_defs = {
        { name = "explorer",       mod = "ui/panels/explorer_panel",        title = "Explorer",       dock = "left" },
        { name = "inspector",      mod = "ui/panels/inspector_panel",       title = "Inspector",      dock = "right" },
        { name = "timeline",       mod = "ui/panels/timeline_panel",        title = "Timeline",       dock = "bottom" },
        { name = "action_palette", mod = "ui/panels/action_palette_panel",  title = "Actions",        dock = "left" },
        { name = "validation",     mod = "ui/panels/validation_panel",      title = "Validation",     dock = "bottom" },
        { name = "console",        mod = "ui/panels/console_panel",         title = "Console",        dock = "bottom" },
        { name = "variables",      mod = "ui/panels/variables_panel",       title = "Variables",      dock = "right" },
        { name = "npc_library",    mod = "ui/panels/npc_library_panel",     title = "NPC Library",    dock = "left" },
        { name = "quest_browser",  mod = "ui/panels/quest_browser_panel",   title = "Quest Browser",  dock = "left" },
        { name = "target_capture", mod = "ui/panels/target_capture_panel",  title = "Target Capture", dock = "right" },
        { name = "world_map",      mod = "ui/panels/world_map_panel",       title = "World Map",     dock = "center" },
        { name = "search",         mod = "ui/panels/search_panel",          title = "Search",         dock = "center" },
    }
    o._editor_panels = {}
    return o
end

function Window:init(app)
    if self._initialized then return end

    self._combat_module = app:get_module("combat")
    self._combat = self._combat_module and self._combat_module.get_combat and self._combat_module:get_combat() or nil

    -- Initialize panels
    self._combat_panel:init(self._combat)
    self._settings_panel:init()

    -- Construct, init and register editor panels as independent windows.
    for _, def in ipairs(self._editor_panel_defs) do
        local PanelClass = require(def.mod)
        local instance = PanelClass:new(self._blackboard, self._event_bus)
        if instance.init then instance:init() end
        -- Editor panels render regardless of the rotation enable toggle.
        if instance.set_visible then instance:set_visible(true) end
        self._editor_panels[def.name] = instance
        self:register_panel(def.name, function()
            -- Editor panels draw via on_render_window (the Sylvannas custom
            -- window callback), not the world-overlay render path.
        end, {
            default_visible = true,
            dock = def.dock,
            title = def.title,
            render_window_fn = function()
                if instance.render_window then instance:render_window() end
            end,
        })
    end

    -- Register existing panels with panel system
    self:_register_builtin_panels()

    -- Load saved layout (if any)
    self:load_layout()

    self._initialized = true
    print("[Sentinel UI] Initialized")
end

function Window:_register_builtin_panels()
    -- Register combat panel as an operational panel
    self:register_panel("combat", function()
        if self._combat_panel then
            self._combat_panel:render()
        end
    end, {
        default_visible = true,
        dock = "right",
        width = 450,
        title = "Combat"
    })

    -- Register settings panel
    self:register_panel("settings", function()
        if self._settings_panel then
            self._settings_panel:render()
        end
    end, {
        default_visible = true,
        dock = "bottom",
        width = 450,
        title = "Settings"
    })
end

-- Panel registration and management API
function Window:register_panel(name, render_fn, options)
    options = options or {}
    local panel = self._panel_registry:register(name, render_fn, options)
    return panel ~= nil
end

function Window:show_panel(name)
    local panel = self._panel_registry:get(name)
    if panel then
        panel.visible = true
        return true
    end
    return false
end

function Window:hide_panel(name)
    local panel = self._panel_registry:get(name)
    if panel then
        panel.visible = false
        return true
    end
    return false
end

function Window:toggle_panel(name)
    local panel = self._panel_registry:get(name)
    if panel then
        panel.visible = not panel.visible
        return true
    end
    return false
end

function Window:get_panel(name)
    return self._panel_registry:get(name)
end

function Window:get_panel_names()
    return self._panel_registry:names()
end

-- Layout persistence
function Window:save_layout()
    local layout = {
        panels = {},
    }

    local panels = self._panel_registry:all()
    for name, panel in pairs(panels) do
        table.insert(layout.panels, {
            name = name,
            visible = panel.visible,
            options = panel.options,
        })
    end

    local json_str, err = nil, nil
    -- Try to use JSON library if available
    local ok_json, JSON = pcall(require, "lib/JSON")
    if ok_json and JSON then
        json_str, err = JSON.encode(layout)
    else
        -- Fallback: manual JSON
        json_str = '{"panels":['
        local first = true
        for name, panel in pairs(panels) do
            if not first then json_str = json_str .. "," end
            first = false
            json_str = json_str .. string.format(
                '{"name":"%s","visible":%s,"options":{"dock":"%s","width":%s,"height":%s,"title":"%s"}}',
                name,
                tostring(panel.visible),
                panel.options.dock or "center",
                panel.options.width or "null",
                panel.options.height or "null",
                panel.options.title or ""
            )
        end
        json_str = json_str .. ']}'
    end

    if core and core.write_data_file then
        local ok, write_err = pcall(core.write_data_file, "sentinel/layout.json", json_str)
        if ok then
            return true
        end
        return false, write_err
    end
    return true
end

function Window:load_layout()
    local layout_data = nil

    if core and core.read_data_file then
        local content, err = core.read_data_file("sentinel/layout.json")
        if content then
            local ok_json, JSON = pcall(require, "lib/JSON")
            if ok_json and JSON then
                layout_data, _ = JSON.decode(content)
            else
                -- Try Lua parse as fallback
                local ok, decoded = pcall(function()
                    return assert(loadstring("return " .. content))()
                end)
                if ok then layout_data = decoded end
            end
        end
    end

    if not layout_data or not layout_data.panels then
        return true -- No layout to restore
    end

    for _, saved_panel in ipairs(layout_data.panels or {}) do
        local panel = self._panel_registry:get(saved_panel.name)
        if panel and saved_panel.visible ~= nil then
            panel.visible = saved_panel.visible
        end
    end

    return true
end

function Window:tick(delta)
    if not self._initialized then return end
    self._combat_panel:tick(delta)
    self._settings_panel:tick(delta)
    for _, panel in pairs(self._editor_panels) do
        if panel.tick then panel:tick(delta) end
    end
end

function Window:update()
    if not self._initialized then return end
    self._combat_panel:update()
    self._settings_panel:update()
    for _, panel in pairs(self._editor_panels) do
        if panel.update then panel:update() end
    end
end

function Window:render()
    if not self._initialized then return end
    -- Render toolbar first (handles panel visibility dropdowns)
    if self._toolbar then
        self._toolbar:render_panel_dropdown()
    end

    -- Render registered panels
    for name, panel in pairs(self._panel_registry:all()) do
        if panel.visible and type(panel.render_fn) == "function" then
            panel.render_fn()
        end
    end
end

function Window:on_render_window()
    if not self._initialized then return end
    -- Render every visible panel's window so it appears as a clickable/poppable
    -- Sylvannas custom window.
    for name, panel in pairs(self._panel_registry:all()) do
        if panel.visible and type(panel.render_window_fn) == "function" then
            panel.render_window_fn()
        end
    end
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

-- Toolbar integration
function Window:set_toolbar(toolbar)
    self._toolbar = toolbar
end

function Window:shutdown()
    self._initialized = false
    self._combat_panel:shutdown()
    self._settings_panel:shutdown()
    for _, panel in pairs(self._editor_panels) do
        if panel.shutdown then panel:shutdown() end
    end
    self._editor_panels = {}
    self._combat_module = nil
    self._combat = nil
    self._panel_registry = nil
    self._toolbar = nil
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