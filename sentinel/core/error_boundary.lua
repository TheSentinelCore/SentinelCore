-- core/error_boundary.lua
-- Fault isolation for everything the kernel invokes on someone else's behalf.
--
-- ADR 08 §5.1: "ErrorBoundary + Quarantine -- mandatory once third-party code runs. No
-- engine-level error isolation is documented -- every callback must self-pcall."
--
-- Three properties, each of which had to be learned the hard way:
--
--   ISOLATION      A throw stops here. The tick keeps running.
--   ATTRIBUTION    Every fault names its owner. ADR 08 §5.1 on Log: "with plugin
--                  attribution, or this is undebuggable."
--   DEDUPLICATION  A handler that faults every frame faults ~60x/second. Logging all of
--                  them is how a real error becomes invisible. Repeats are suppressed but
--                  COUNTED, so silence stays measurable (`fault_count`).

local ErrorBoundary = {}
ErrorBoundary.__index = ErrorBoundary

function ErrorBoundary:new(event_bus)
    local o = setmetatable({}, ErrorBoundary)
    o._event_bus = event_bus
    -- Keyed by "module\0operation": { count, last_error }. The NUL separator keeps
    -- ("a", "b.c") and ("a.b", "c") distinct.
    o._faults = {}
    return o
end

local function fault_key(module_name, operation)
    return tostring(module_name) .. "\0" .. tostring(operation)
end

--- Report a fault: publish once per distinct message, log once per distinct message, and
--- count every occurrence. Nothing in here may throw -- a broken bus or logger must not
--- convert a handled fault into an unhandled one.
function ErrorBoundary:_report(module_name, operation, err)
    local key = fault_key(module_name, operation)
    local entry = self._faults[key]
    local message = tostring(err)

    if entry and entry.last_error == message then
        entry.count = entry.count + 1
        return -- same failure as last time: already reported
    end

    local count = entry and (entry.count + 1) or 1
    self._faults[key] = { count = count, last_error = message }

    if self._event_bus then
        pcall(function()
            self._event_bus:publish("system:error", {
                module = module_name,
                operation = operation,
                error = message,
                count = count,
            })
        end)
    end

    -- Surface the error so it isn't silently swallowed (previously a render-time throw
    -- would kill the UI with no indication).
    if core and type(core.log_error) == "function" then
        pcall(core.log_error, "[Sentinel][error_boundary] " .. tostring(module_name)
            .. ":" .. tostring(operation) .. " -> " .. message)
    end
end

---Run `fn(...)` isolated from the caller.
---@return boolean ok, ... all values returned by fn (or the error message when ok is false)
function ErrorBoundary:wrap(module_name, operation, fn, ...)
    local results = { pcall(fn, ...) }
    local ok = results[1]

    if ok then
        -- A previously faulting operation that now succeeds gets a clean slate, so a
        -- recurrence after recovery is reported rather than swallowed as a "repeat".
        local entry = self._faults[fault_key(module_name, operation)]
        if entry then entry.last_error = nil end
        return unpack(results, 1, math.max(#results, 1))
    end

    self:_report(module_name, operation, results[2])
    return false, results[2]
end

---Wrap a function for registration as an injector callback. This is the ADR requirement --
---"every callback must self-pcall" -- expressed as a value the caller can hand to
---`core.register_*_callback` directly.
---@return function guarded A function that never throws and passes through fn's returns
function ErrorBoundary:wrap_callback(module_name, operation, fn)
    return function(...)
        local results = { self:wrap(module_name, operation, fn, ...) }
        if results[1] then
            return unpack(results, 2, math.max(#results, 2))
        end
        return nil
    end
end

---@return number occurrences of faults for this (module, operation), including suppressed ones
function ErrorBoundary:fault_count(module_name, operation)
    local entry = self._faults[fault_key(module_name, operation)]
    return entry and entry.count or 0
end

---@return table|nil { count, last_error }
function ErrorBoundary:last_fault(module_name, operation)
    return self._faults[fault_key(module_name, operation)]
end

---@return table faults keyed by "module:operation", for telemetry and the cockpit
function ErrorBoundary:fault_report()
    local out = {}
    for key, entry in pairs(self._faults) do
        local module_name, operation = key:match("^(.-)%z(.*)$")
        out[tostring(module_name) .. ":" .. tostring(operation)] = {
            count = entry.count,
            last_error = entry.last_error,
        }
    end
    return out
end

return ErrorBoundary
