-- NavLib/main.lua
-- Standalone navigation library for Sylvannas plugins
-- Registers _G.NavLib so other plugins can access pathfinding + movement

local NavigationClient = require("NavigationClient")
local MovementModule = require("MovementModule")
local JSON = require("JSON")
local Helpers = require("Helpers")

_G.NavLib = {
    NavigationClient = NavigationClient,
    MovementModule = MovementModule,
    JSON = JSON,
    Helpers = Helpers,
}

core.log("[NavLib] Loaded — NavigationClient + MovementModule available via _G.NavLib")
