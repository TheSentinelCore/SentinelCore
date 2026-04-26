-- EventBus.lua — Simple publish/subscribe event system.

---@class EventBus
---@field _handlers table<string, table[]>
---@field _next_token number
local EventBus = {}
EventBus.__index = EventBus

---@return EventBus
function EventBus:new()
    return setmetatable({
        _handlers   = {},
        _next_token = 1,
    }, EventBus)
end

--- Subscribe to an event. Returns a token that can be used to unsubscribe.
---@param event_name string
---@param callback function
---@return number token
function EventBus:subscribe(event_name, callback)
    if not self._handlers[event_name] then
        self._handlers[event_name] = {}
    end
    local token = self._next_token
    self._next_token = self._next_token + 1
    table.insert(self._handlers[event_name], { token = token, callback = callback })
    return token
end

--- Publish an event to all subscribers.
---@param event_name string
---@param data any
function EventBus:publish(event_name, data)
    local handlers = self._handlers[event_name]
    if not handlers then return end
    for _, entry in ipairs(handlers) do
        local ok, err = pcall(entry.callback, data)
        if not ok then
            pcall(core.log_error, "[DuoFarm] EventBus error on '" .. event_name .. "': " .. tostring(err))
        end
    end
end

--- Unsubscribe by token.
---@param token number
function EventBus:unsubscribe(token)
    for event_name, handlers in pairs(self._handlers) do
        for i, entry in ipairs(handlers) do
            if entry.token == token then
                table.remove(handlers, i)
                return
            end
        end
    end
end

return EventBus
