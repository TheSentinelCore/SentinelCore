local EventBus = {}
EventBus.__index = EventBus

---@return EventBus
function EventBus:new()
    return setmetatable({ _listeners = {} }, EventBus)
end

---@param event_name string
---@param handler fun(data: table|nil)
---@param opts? table
function EventBus:on(event_name, handler, opts)
    if type(event_name) ~= "string" or type(handler) ~= "function" then
        return
    end

    local list = self._listeners[event_name]
    if type(list) ~= "table" then
        list = {}
        self._listeners[event_name] = list
    end

    list[#list + 1] = {
        fn = handler,
        owner = opts and opts.owner or nil,
    }
end

---@param owner any
function EventBus:off_owner(owner)
    if owner == nil then
        return
    end

    for name, list in pairs(self._listeners) do
        local kept = {}
        for i = 1, #list do
            if list[i].owner ~= owner then
                kept[#kept + 1] = list[i]
            end
        end
        self._listeners[name] = kept
    end
end

---@param event_name string
---@param data? table
function EventBus:emit(event_name, data)
    local list = self._listeners[event_name]
    if type(list) ~= "table" then
        return
    end

    for i = 1, #list do
        local entry = list[i]
        if entry and type(entry.fn) == "function" then
            pcall(entry.fn, data)
        end
    end
end

return EventBus
