--- Shared safe-call utilities for game_object method invocation.
--- Eliminates the 7+ copies of safe_method/safe_unit_call across the codebase.
local M = {}

---@param obj any game_object or nil
---@param method string method name to call
---@param ... any additional arguments
---@return any result or nil on failure
function M.safe_method(obj, method, ...)
    if not obj then
        return nil
    end
    local fn = obj[method]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, obj, ...)
    if not ok then
        return nil
    end
    return value
end

---@param target game_object|nil
---@return string
function M.safe_target_name(target)
    local name = M.safe_method(target, "get_name")
    if type(name) == "string" and name ~= "" then
        return name
    end
    return "unknown"
end

local OBJECT_UNWRAP_KEYS = {
    "object",
    "raw_object",
    "game_object",
}

---@param value any
---@return any
function M.unwrap_game_object(value)
    if type(value) ~= "table" then
        return value
    end

    for i = 1, #OBJECT_UNWRAP_KEYS do
        local candidate = rawget(value, OBJECT_UNWRAP_KEYS[i])
        if candidate ~= nil then
            return candidate
        end
    end

    return value
end

---@param lhs game_object|nil
---@param rhs game_object|nil
---@return boolean
function M.is_same_unit(lhs, rhs)
    if not lhs or not rhs then
        return false
    end
    -- Use rawequal to bypass the Sylvannas __eq metamethod which throws
    -- "Invalid game object!" when either operand is a stale game object ref.
    if rawequal(lhs, rhs) then
        return true
    end

    local lhs_guid = tonumber(M.safe_method(lhs, "get_guid"))
        or tonumber(M.safe_method(lhs, "get_object_guid"))
        or 0
    local rhs_guid = tonumber(M.safe_method(rhs, "get_guid"))
        or tonumber(M.safe_method(rhs, "get_object_guid"))
        or 0
    if lhs_guid > 0 and rhs_guid > 0 then
        return lhs_guid == rhs_guid
    end

    return false
end

return M
