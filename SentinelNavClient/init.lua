--[[
    SentinelNavClient - Standalone Navigation Plugin

    Singleton that owns the shared Facade instance.
    All consumers (SentinelGather, BgBuddy, etc.) share this single Facade.

    Usage:
        -- Other plugins access via _G.SentinelNavClient (set by main.lua)
        local facade = _G.SentinelNavClient.facade
        facade:move_to(target)
]]

local Facade = require("Facade")

---@class SentinelNavClient
---@field private _facade Facade|nil
---@field private _initialized boolean
---@field VERSION string
---@field NAME string
local SentinelNavClient = {}
SentinelNavClient.__index = SentinelNavClient

SentinelNavClient.VERSION = "0.0.04"
SentinelNavClient.NAME = "Sentinel Navigation Client"

local _instance = nil

---Get the singleton instance
---@return SentinelNavClient
function SentinelNavClient:get_instance()
    if not _instance then
        _instance = setmetatable({}, SentinelNavClient)
        _instance._facade = nil
        _instance._initialized = false
    end
    return _instance
end

---Initialize SentinelNavClient — creates the shared Facade
---@return boolean success
function SentinelNavClient:initialize()
    local instance = self:get_instance()

    if instance._initialized then
        return true
    end

    -- Create the shared Facade (empty config — UI syncs real values immediately)
    instance._facade = Facade:new({})

    instance._initialized = true
    core.log("[SentinelNavClient] Initialized v" .. SentinelNavClient.VERSION)
    return true
end

---Get the shared Facade
---@return Facade|nil
function SentinelNavClient:get_facade()
    local instance = self:get_instance()
    return instance._facade
end

---Check if initialized
---@return boolean
function SentinelNavClient:is_initialized()
    local instance = self:get_instance()
    return instance._initialized
end

---Clean up
function SentinelNavClient:destroy()
    local instance = self:get_instance()
    if instance._facade then
        instance._facade:destroy()
        instance._facade = nil
    end
    instance._initialized = false
    _instance = nil
    core.log("[SentinelNavClient] Destroyed")
end

return SentinelNavClient
