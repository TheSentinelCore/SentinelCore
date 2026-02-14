--[[
    NavLib - Standalone Navigation Plugin

    Singleton that owns the shared Facade instance.
    All consumers (GatherBuddy, BgBuddy, etc.) share this single Facade.

    Usage:
        -- Other plugins access via _G.NavLib (set by main.lua)
        local facade = _G.NavLib.facade
        facade:move_to(target)
]]

local Facade = require("Facade")

---@class NavLibPlugin
---@field private _facade Facade|nil
---@field private _initialized boolean
---@field VERSION string
---@field NAME string
local NavLibPlugin = {}
NavLibPlugin.__index = NavLibPlugin

NavLibPlugin.VERSION = "2.0.0"
NavLibPlugin.NAME = "NavLib"

local _instance = nil

---Get the singleton instance
---@return NavLibPlugin
function NavLibPlugin:get_instance()
    if not _instance then
        _instance = setmetatable({}, NavLibPlugin)
        _instance._facade = nil
        _instance._initialized = false
    end
    return _instance
end

---Initialize NavLib — creates the shared Facade
---@return boolean success
function NavLibPlugin:initialize()
    local instance = self:get_instance()

    if instance._initialized then
        return true
    end

    -- Create the shared Facade (empty config — UI syncs real values immediately)
    instance._facade = Facade:new({})

    instance._initialized = true
    core.log("[NavLib] Initialized v" .. NavLibPlugin.VERSION)
    return true
end

---Get the shared Facade
---@return Facade|nil
function NavLibPlugin:get_facade()
    local instance = self:get_instance()
    return instance._facade
end

---Check if initialized
---@return boolean
function NavLibPlugin:is_initialized()
    local instance = self:get_instance()
    return instance._initialized
end

---Clean up
function NavLibPlugin:destroy()
    local instance = self:get_instance()
    if instance._facade then
        instance._facade:destroy()
        instance._facade = nil
    end
    instance._initialized = false
    _instance = nil
    core.log("[NavLib] Destroyed")
end

return NavLibPlugin
