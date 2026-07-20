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
    -- Surface the error so it isn't silently swallowed (previously a render-time
    -- throw would kill the UI with no indication). Use core.log_error if present.
    if core and type(core.log_error) == "function" then
        pcall(core.log_error, "[Sentinel][error_boundary] " .. tostring(module_name) .. ":" .. tostring(operation) .. " -> " .. tostring(result))
    end
    return false, result
end

return ErrorBoundary
