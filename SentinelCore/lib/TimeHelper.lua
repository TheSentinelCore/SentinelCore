--- Centralized time helper to eliminate repeated defensive core.time() boilerplate.
---@return number seconds  Current time (0 when core unavailable, e.g. in tests)
local function get_now()
    return (core and core.time and core.time()) or 0
end

return { get_now = get_now }
