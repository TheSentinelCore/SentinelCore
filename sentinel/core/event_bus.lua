local EventBus = {}
EventBus.__index = EventBus

function EventBus:new(logger)
    local o = setmetatable({}, EventBus)
    o._logger = logger
    o._next_id = 0
    o._subs = {}
    return o
end

local function sort_list(list)
    table.sort(list, function(a, b)
        if a.priority == b.priority then
            return a.id < b.id
        end
        return a.priority < b.priority
    end)
end

function EventBus:subscribe(event_name, handler, priority)
    self._next_id = self._next_id + 1
    local token = "sub:" .. tostring(self._next_id)
    local list = self._subs[event_name]
    if not list then
        list = {}
        self._subs[event_name] = list
    end
    list[#list + 1] = {
        id = self._next_id,
        token = token,
        handler = handler,
        priority = tonumber(priority) or 50,
    }
    sort_list(list)
    return token
end

function EventBus:unsubscribe(token)
    for event_name, list in pairs(self._subs) do
        for index = #list, 1, -1 do
            if list[index].token == token then
                table.remove(list, index)
                if #list == 0 then
                    self._subs[event_name] = nil
                end
                return true
            end
        end
    end
    return false
end

function EventBus:publish(event_name, payload)
    local list = self._subs[event_name]
    if not list then
        return
    end
    local snapshot = {}
    for index = 1, #list do
        snapshot[index] = list[index]
    end
    for _, sub in ipairs(snapshot) do
        local ok, err = pcall(sub.handler, payload)
        if not ok then
            if event_name ~= "system:error" then
                self:publish("system:error", {
                    module = "event_bus",
                    operation = event_name,
                    error = tostring(err),
                })
            elseif self._logger and type(self._logger) == "function" then
                self._logger("[Sentinel] Event handler error: " .. tostring(err))
            elseif core and core.log_error then
                core.log_error("[Sentinel] Event handler error: " .. tostring(err))
            end
        end
    end
end

return EventBus
