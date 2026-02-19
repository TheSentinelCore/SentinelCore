--[[
    SentinelNavClient - Standalone Navigation Plugin

    Singleton that owns the shared Client instance.
    All consumers (SentinelGather, BgBuddy, etc.) share this single Client.

    Usage:
        -- Other plugins access via _G.SentinelNavClient (set by main.lua)
        local client = _G.SentinelNavClient.client
        client:move_to(target)
]]

local Client = require("core/Client")

---@class SentinelNavClient
---@field private _client Client|nil
---@field private _initialized boolean
---@field VERSION string
---@field NAME string
local SentinelNavClient = {}
SentinelNavClient.__index = SentinelNavClient

SentinelNavClient.VERSION = "0.0.5"
SentinelNavClient.NAME = "Sentinel Navigation Client"

local _instance = nil

---Get the singleton instance
---@return SentinelNavClient
function SentinelNavClient:get_instance()
    if not _instance then
        _instance = setmetatable({}, SentinelNavClient)
        _instance._client = nil
        _instance._initialized = false
    end
    return _instance
end

---Initialize SentinelNavClient — creates the shared Client
---@return boolean success
function SentinelNavClient:initialize()
    local instance = self:get_instance()

    if instance._initialized then
        return true
    end

    -- Create the shared Client (empty config — UI syncs real values immediately)
    instance._client = Client:new({})

    instance._initialized = true
    return true
end

---Get the shared Client
---@return Client|nil
function SentinelNavClient:get_client()
    local instance = self:get_instance()
    return instance._client
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
    if instance._client then
        instance._client:destroy()
        instance._client = nil
    end
    instance._initialized = false
    _instance = nil
end

return SentinelNavClient
