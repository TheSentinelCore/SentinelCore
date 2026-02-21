local BB_PREFIX = "bb."

---@class Blackboard
---@field private _data table
---@field private _watchers table<string, table>
---@field private _event_bus EventBus|nil
local Blackboard = {}
Blackboard.__index = Blackboard

---@param event_bus? EventBus
---@return Blackboard
function Blackboard:new(event_bus)
    local o = setmetatable({}, Blackboard)
    o._data = {}
    o._watchers = {}
    o._event_bus = event_bus
    return o
end

---@param key string
---@param default? any
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
---@param value any
function Blackboard:set(key, value)
    local old = self._data[key]
    if old == value and type(value) ~= "table" then
        return
    end

    self._data[key] = value

    local listeners = self._watchers[key]
    if listeners then
        for i = 1, #listeners do
            local ok, err = pcall(listeners[i], key, value, old)
            if not ok and core and core.log_error then
                core.log_error("[SentinelCore] Blackboard watcher error: " .. tostring(err))
            end
        end
    end

    if self._event_bus then
        self._event_bus:emit(BB_PREFIX .. key, {
            key = key,
            new_value = value,
            old_value = old,
        })
    end
end

---@param key string
---@param callback fun(key: string, new_value: any, old_value: any)
function Blackboard:subscribe(key, callback)
    if not self._watchers[key] then
        self._watchers[key] = {}
    end
    local list = self._watchers[key]
    list[#list + 1] = callback
end

---@param key string
---@param callback function
function Blackboard:unsubscribe(key, callback)
    local listeners = self._watchers[key]
    if not listeners then
        return
    end
    for i = #listeners, 1, -1 do
        if listeners[i] == callback then
            table.remove(listeners, i)
        end
    end
end

---@param key? string
function Blackboard:clear(key)
    if key then
        if self._data[key] ~= nil then
            local old = self._data[key]
            self._data[key] = nil
            if self._event_bus then
                self._event_bus:emit(BB_PREFIX .. key, {
                    key = key,
                    new_value = nil,
                    old_value = old,
                })
            end
        end
        return
    end

    local keys = {}
    for k in pairs(self._data) do
        keys[#keys + 1] = k
    end
    for i = 1, #keys do
        self:clear(keys[i])
    end
end

---@return table
function Blackboard:snapshot()
    local out = {}
    for k, v in pairs(self._data) do
        out[k] = v
    end
    return out
end

---@return string[]
function Blackboard:keys()
    local out = {}
    for k in pairs(self._data) do
        out[#out + 1] = k
    end
    return out
end

return Blackboard
