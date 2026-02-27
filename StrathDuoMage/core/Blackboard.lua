local Blackboard = {}
Blackboard.__index = Blackboard

---@return Blackboard
function Blackboard:new()
    return setmetatable({ _data = {} }, Blackboard)
end

---@param key string
---@param value any
function Blackboard:set(key, value)
    self._data[key] = value
end

---@param key string
---@param default any
---@return any
function Blackboard:get(key, default)
    local value = self._data[key]
    if value == nil then
        return default
    end
    return value
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

---@return table
function Blackboard:snapshot()
    local out = {}
    for k, v in pairs(self._data) do
        out[k] = v
    end
    return out
end

return Blackboard
