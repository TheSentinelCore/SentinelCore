-- NavLib/main.lua
-- Standalone navigation library for Sylvannas plugins
-- Registers _G.NavLib so other plugins can access pathfinding + movement

local Navigation = require("core/Navigation")
local Movement   = require("core/Movement")
local Obstacle   = require("core/Obstacle")
local Facade     = require("Facade")
local JSON       = require("lib/JSON")
local Helpers    = require("lib/Helpers")

_G.NavLib = {
    -- Primary API: single-call factory
    create = function(config)
        return Facade:new(config)
    end,

    -- Raw module classes (escape hatch for advanced use)
    Navigation = Navigation,
    Movement   = Movement,
    Obstacle   = Obstacle,

    -- Utilities
    JSON    = JSON,
    Helpers = Helpers,
}

core.log("[NavLib] Loaded — NavLib.create() + raw modules available via _G.NavLib")
