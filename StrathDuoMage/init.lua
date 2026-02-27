local Bot = require("core/Bot")

---@class StrathDuoMageBootstrap
---@field private _bot StrathDuoBot|nil
---@field private _initialized boolean
---@field VERSION string
---@field NAME string
local StrathDuoMage = {}
StrathDuoMage.__index = StrathDuoMage

StrathDuoMage.VERSION = "0.1.0"
StrathDuoMage.NAME = "StrathDuoMage"

local _instance = nil

---@return StrathDuoMageBootstrap
function StrathDuoMage:get_instance()
    if not _instance then
        _instance = setmetatable({}, StrathDuoMage)
        _instance._bot = nil
        _instance._initialized = false
    end
    return _instance
end

---@param opts? table
---@return boolean
---@return string|nil
function StrathDuoMage:initialize(opts)
    local instance = self:get_instance()
    if instance._initialized then
        return true, nil
    end

    instance._bot = Bot:new(opts or {})
    instance._initialized = true
    return true, nil
end

---@return StrathDuoBot|nil
function StrathDuoMage:get_bot()
    return self:get_instance()._bot
end

function StrathDuoMage:destroy()
    local instance = self:get_instance()
    if instance._bot and instance._bot.destroy then
        instance._bot:destroy()
    end
    instance._bot = nil
    instance._initialized = false
    _instance = nil
end

return StrathDuoMage
