--[[
    SentinelCore UI Window Orchestrator

    Thin shell that creates the AstroUI instance and delegates
    each tab to its own module in ui/tabs/.
]]

local AstroUI = require("lib/AstroUI")
local dashboard_tab = require("ui/tabs/dashboard_tab")
local settings_tab = require("ui/tabs/settings_tab")
local profile_tab = require("ui/tabs/profile_tab")
local log_tab = require("ui/tabs/log_tab")

local Window = {}

local _initialized = false
local _client = nil
local _ui = nil

---@param ui any
---@param client SentinelClient
local function register_tabs(ui, client)
    ui:add_tab({ id = "dashboard", label = "Dashboard" }, function(t)
        dashboard_tab.render(t, client)
    end)

    ui:add_tab({ id = "settings", label = "Settings" }, function(t)
        settings_tab.render(t, client)
    end)

    ui:add_tab({ id = "profiles", label = "Profiles" }, function(t)
        profile_tab.render(t, client)
    end)

    ui:add_tab({ id = "log", label = "Log" }, function(t)
        log_tab.render(t, client)
    end)
end

-- ============================================================================
-- MODULE API
-- ============================================================================

---@param client SentinelClient
function Window.init(client)
    if _initialized then
        return
    end

    _client = client

    _ui = AstroUI.new({
        id = "sentinel_core",
        title = "Sentinel Control Center",
        default_x = 560,
        default_y = 100,
        default_w = 760,
        default_h = 600,
        theme = "apple",
        render_layer = 1,
    })

    register_tabs(_ui, _client)

    -- Keep hidden until user toggles from main menu.
    _ui.menu.enable:set(false)

    _initialized = true
end

function Window.on_render()
    if not _initialized or not _ui then
        return
    end

    _ui:on_render()
end

function Window.on_menu_render()
    if not _initialized or not _ui then
        return
    end

    _ui:on_menu_render()
end

---@return any|nil
function Window.get_ui()
    return _ui
end

return Window
