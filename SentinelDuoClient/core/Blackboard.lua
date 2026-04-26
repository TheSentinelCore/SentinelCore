-- Blackboard.lua — Simple key-value store for duo bot state.
-- All keys should use the "duo." prefix to avoid collision.

---@class Blackboard
---@field _data table
local Blackboard = {}
Blackboard.__index = Blackboard

---@return Blackboard
function Blackboard:new()
    return setmetatable({ _data = {} }, Blackboard)
end

---@param key string
---@param default any
---@return any
function Blackboard:get(key, default)
    local v = self._data[key]
    if v == nil then return default end
    return v
end

---@param key string
---@param value any
function Blackboard:set(key, value)
    self._data[key] = value
end

---@param key string
---@return boolean
function Blackboard:has(key)
    return self._data[key] ~= nil
end

---@param key string
function Blackboard:clear(key)
    self._data[key] = nil
end

--- Clear all keys that start with the given prefix.
---@param prefix string
function Blackboard:clear_prefix(prefix)
    -- Collect keys first to avoid modifying the table during pairs() iteration
    local to_clear = {}
    for k in pairs(self._data) do
        if k:sub(1, #prefix) == prefix then
            to_clear[#to_clear + 1] = k
        end
    end
    for _, k in ipairs(to_clear) do
        self._data[k] = nil
    end
end

--- Return a shallow copy of all keys starting with prefix.
---@param prefix string
---@return table
function Blackboard:snapshot(prefix)
    local result = {}
    for k, v in pairs(self._data) do
        if k:sub(1, #prefix) == prefix then
            result[k] = v
        end
    end
    return result
end

return Blackboard
