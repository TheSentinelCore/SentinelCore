-- SentinelNavClient/main.lua
-- Standalone navigation plugin for Sylvannas
-- Registers engine callbacks, manages UI, exports _G.SentinelNavClient

local SentinelNavClient = require("init")
local Navigation   = require("core/Navigation")
local Movement     = require("core/Movement")
local Obstacle     = require("core/Obstacle")
local JSON         = require("lib/JSON")
local Helpers      = require("lib/Helpers")
local UIWindow     = require("ui/window")
local color        = require("common/color")

-- Module state
local _is_loaded = false

-- Menu elements
local _menu_tree  = core.menu.tree_node()
local _toggle_btn = core.menu.button("snc_open")

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

local function on_load()
    if _is_loaded then return end

    local success = SentinelNavClient:initialize()
    if not success then
        core.log_error("[SentinelNavClient] Failed to initialize")
        return
    end

    -- Initialize UI with the shared Facade
    local facade = SentinelNavClient:get_facade()
    if facade then
        UIWindow.init(facade)
    end

    _is_loaded = true
    core.log("[SentinelNavClient] Loaded — standalone plugin ready")
end

-- Initialize eagerly so the Facade exists before other plugins' on_update fires.
-- header.lua already gates on a valid player, so this is safe.
on_load()

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

-- Update: advance movement + obstacle detection each frame
core.register_on_update_callback(function()
    if not _is_loaded then return end

    local facade = SentinelNavClient:get_facade()
    if facade then
        facade:update()
    end
end)

-- Render: sync settings from UI to Facade + render the window
core.register_on_render_callback(function()
    if not _is_loaded then return end
    UIWindow.on_render()
end)

-- Menu: tree node + AstroUI menu hooks
core.register_on_render_menu_callback(function()
    if not _is_loaded then return end
    UIWindow.on_menu_render()

    _menu_tree:render("Sentinel Navigation Client", function()
        core.menu.header():render("Version: " .. SentinelNavClient.VERSION, color.white(200))
        if _toggle_btn:render("Open Settings") then
            local ui = UIWindow.get_ui()
            if ui and ui.menu and ui.menu.enable then
                ui.menu.enable:set(not ui.menu.enable:get_state())
            end
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- Global API
-- ---------------------------------------------------------------------------

_G.SentinelNavClient = {
    --- Returns the shared Facade. Config param is ignored (settings owned by SentinelNavClient UI).
    ---@param config? table Ignored — kept for backward compatibility
    ---@return Facade|nil
    create = function(config)
        return SentinelNavClient:get_facade()
    end,

    --- No-op. UI is created automatically by SentinelNavClient.
    create_ui = function(facade_arg)
        return UIWindow
    end,

    --- UI handle
    ui = UIWindow,

    --- Raw module classes (escape hatch for advanced use)
    Navigation = Navigation,
    Movement   = Movement,
    Obstacle   = Obstacle,

    --- Utilities
    JSON    = JSON,
    Helpers = Helpers,

    --- Plugin metadata
    VERSION = SentinelNavClient.VERSION,
}

-- Make .facade a live getter so it returns the current Facade even when
-- accessed before on_load (returns nil gracefully) or after (returns Facade).
setmetatable(_G.SentinelNavClient, {
    __index = function(t, k)
        if k == "facade" then
            return SentinelNavClient:get_facade()
        end
    end
})

-- ---------------------------------------------------------------------------
-- Unload
-- ---------------------------------------------------------------------------

local function on_unload()
    SentinelNavClient:destroy()
    _G.SentinelNavClient = nil
    _is_loaded = false
    core.log("[SentinelNavClient] Unloaded")
end

-- Unload is handled via the return table's `unload` field below.

core.log("[SentinelNavClient] Module loaded — _G.SentinelNavClient available")

-- ---------------------------------------------------------------------------
-- Module export (matches SentinelGather pattern)
-- ---------------------------------------------------------------------------

return {
    name    = "SentinelNavClient",
    version = SentinelNavClient.VERSION,
    unload  = on_unload,
}
