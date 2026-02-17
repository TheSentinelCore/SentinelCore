---@class QuestingBuddy
---@field private _manager QuestingManager|nil
---@field private _initialized boolean
---@field VERSION string
---@field NAME string
local QuestingBuddy = {}
QuestingBuddy.__index = QuestingBuddy

QuestingBuddy.VERSION = "0.1.0"
QuestingBuddy.NAME = "QuestingBuddy"

local _instance = nil

---@return QuestingBuddy
function QuestingBuddy:get_instance()
    if not _instance then
        _instance = self:_create_instance()
    end
    return _instance
end

---@return QuestingBuddy
function QuestingBuddy:_create_instance()
    local instance = setmetatable({}, QuestingBuddy)
    instance._initialized = false
    instance._manager = nil

    local ok, QuestingManager = pcall(require, "modules/QuestingManager")
    if not ok then
        core.log_error("[QuestingBuddy] Failed to load QuestingManager: " .. tostring(QuestingManager))
        return instance
    end

    instance._manager = QuestingManager:new()
    return instance
end

---@return boolean
function QuestingBuddy:initialize()
    local instance = self:get_instance()
    if instance._initialized then
        return true
    end

    if not instance._manager then
        core.log_error("[QuestingBuddy] Manager not available")
        return false
    end

    instance._initialized = true
    core.log("[QuestingBuddy] Initialized v" .. QuestingBuddy.VERSION)
    return true
end

---@return boolean
function QuestingBuddy:start()
    local instance = self:get_instance()
    if not instance._initialized then
        if not self:initialize() then
            return false
        end
    end

    if not instance._manager then
        return false
    end

    instance._manager:set_enabled(true)
    return true
end

function QuestingBuddy:stop()
    local instance = self:get_instance()
    if instance._manager then
        instance._manager:set_enabled(false)
    end
end

---@param enabled boolean
function QuestingBuddy:set_enabled(enabled)
    local instance = self:get_instance()
    if instance._manager then
        instance._manager:set_enabled(enabled)
    end
end

---@param config table
function QuestingBuddy:configure(config)
    local instance = self:get_instance()
    if instance._manager then
        instance._manager:update_config(config)
    end
end

function QuestingBuddy:update()
    local instance = self:get_instance()
    if instance._initialized and instance._manager then
        instance._manager:update()
    end
end

---@return table
function QuestingBuddy:get_status()
    local instance = self:get_instance()
    if instance._manager then
        return instance._manager:get_status()
    end

    return {
        enabled = false,
        state = "uninitialized",
    }
end

---@return QuestingManager|nil
function QuestingBuddy:get_manager()
    local instance = self:get_instance()
    return instance._manager
end

function QuestingBuddy:destroy()
    local instance = self:get_instance()
    if instance._manager then
        instance._manager:set_enabled(false)
        instance._manager = nil
    end
    instance._initialized = false
    _instance = nil
end

return QuestingBuddy
