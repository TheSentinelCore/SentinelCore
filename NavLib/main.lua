-- NavLib/main.lua
-- Standalone navigation library for Sylvannas plugins
-- Registers _G.NavLib so other plugins can access pathfinding + movement + settings UI

local Navigation = require("core/Navigation")
local Movement   = require("core/Movement")
local Obstacle   = require("core/Obstacle")
local Facade     = require("Facade")
local JSON       = require("lib/JSON")
local Helpers    = require("lib/Helpers")
local UIWindow   = require("ui/window")

_G.NavLib = {
    -- Primary API: single-call factory
    create = function(config)
        return Facade:new(config)
    end,

    -- UI API: create settings window for a facade instance
    create_ui = function(facade)
        UIWindow.init(facade)
        return UIWindow
    end,

    -- UI handle (set after create_ui)
    ui = UIWindow,

    -- Raw module classes (escape hatch for advanced use)
    Navigation = Navigation,
    Movement   = Movement,
    Obstacle   = Obstacle,

    -- Utilities
    JSON    = JSON,
    Helpers = Helpers,
}

core.log("[NavLib] Loaded — NavLib.create() + NavLib.create_ui() available via _G.NavLib")
