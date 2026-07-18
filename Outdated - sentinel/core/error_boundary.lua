local ErrorBoundary = {}
ErrorBoundary.__index = ErrorBoundary

function ErrorBoundary:new(event_bus)
    local o = setmetatable({}, ErrorBoundary)
    o._event_bus = event_bus
    return o
end

function ErrorBoundary:wrap(module_name, operation, fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return true, result
    end
    if self._event_bus then
        self._event_bus:publish("system:error", {
            module = module_name,
            operation = operation,
            error = tostring(result),
        })
    end
    return false, result
end

return ErrorBoundary
