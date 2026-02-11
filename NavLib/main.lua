-- NavLib/main.lua
-- Standalone navigation library for Sylvannas plugins
-- Registers _G.NavLib so other plugins can access pathfinding + movement

local NavigationClient = require("NavigationClient")
local MovementModule   = require("MovementModule")
local ObstacleModule   = require("ObstacleModule")
local NavLibFacade     = require("NavLibFacade")
local JSON             = require("JSON")
local Helpers          = require("Helpers")

_G.NavLib = {
    -- Primary API: single-call factory
    create = function(config)
        return NavLibFacade:new(config)
    end,

    -- Raw module classes (escape hatch for advanced use)
    NavigationClient = NavigationClient,
    MovementModule   = MovementModule,
    ObstacleModule   = ObstacleModule,

    -- Utilities
    JSON    = JSON,
    Helpers = Helpers,
}

core.log("[NavLib] Loaded — NavLib.create() + raw modules available via _G.NavLib")
