local Client = require("core/Client")

---@class SentinelCoreBootstrap
---@field private _client SentinelClient|nil
---@field private _initialized boolean
---@field VERSION string
---@field NAME string
local SentinelCore = {}
SentinelCore.__index = SentinelCore

SentinelCore.VERSION = "0.1.0"
SentinelCore.NAME = "SentinelCore"

local _instance = nil

---@return SentinelCoreBootstrap
function SentinelCore:get_instance()
    if not _instance then
        _instance = setmetatable({}, SentinelCore)
        _instance._client = nil
        _instance._initialized = false
    end
    return _instance
end

---@param config? table
---@return boolean
---@return string|nil
function SentinelCore:initialize(config)
    local instance = self:get_instance()
    if instance._initialized then
        return true, nil
    end

    instance._client = Client:new(config or {})
    instance._initialized = true
    return true, nil
end

---@return SentinelClient|nil
function SentinelCore:get_client()
    return self:get_instance()._client
end

---@return boolean
function SentinelCore:is_initialized()
    return self:get_instance()._initialized
end

function SentinelCore:destroy()
    local instance = self:get_instance()
    if instance._client and instance._client.destroy then
        instance._client:destroy()
    end
    instance._client = nil
    instance._initialized = false
    _instance = nil
end

return SentinelCore
