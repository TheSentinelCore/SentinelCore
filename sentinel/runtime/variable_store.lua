-- sentinel/runtime/variable_store.lua
-- Typed key-value store for profile state.
-- Variables are stored in the blackboard at module.runtime.variables.{scope}.{key}

local VariableStore = {}
VariableStore.__index = VariableStore

local VALID_TYPES = {
    bool = true,
    integer = true,
    float = true,
    string = true,
    position = true,
}

---Determine the Sylvannas type of a Lua value
---@param value any
---@return string|nil type_name "bool"|"integer"|"float"|"string"|"position"|nil
---@return string|nil error
local function infer_type(value)
    local t = type(value)
    if t == "boolean" then
        return "bool", nil
    elseif t == "number" then
        if math.floor(value) == value then
            return "integer", nil
        else
            return "float", nil
        end
    elseif t == "string" then
        return "string", nil
    elseif t == "table" then
        if value.x ~= nil and value.y ~= nil and value.zone ~= nil then
            return "position", nil
        end
        return nil, "invalid_type: table must have x, y, and zone fields for position"
    end
    return nil, "invalid_type: unsupported Lua type " .. tostring(t)
end

---Create a new VariableStore
---@param blackboard table The SentinelCore blackboard
---@return table VariableStore instance
function VariableStore:new(blackboard)
    local o = setmetatable({}, VariableStore)
    o._blackboard = blackboard
    return o
end

---Build the blackboard key for a given scope and variable name
---@param scope string "global" or operation_id
---@param key string Variable name
---@return string Full blackboard key
function VariableStore:_build_key(scope, key)
    return "module.runtime.variables." .. tostring(scope) .. "." .. tostring(key)
end

---Type-checked write.
---scope is "global" or an operation_id string
---@param scope string
---@param key string
---@param value any
---@return boolean success
---@return string|nil error
function VariableStore:set(scope, key, value)
    if type(scope) ~= "string" or scope == "" then
        return false, "scope must be a non-empty string"
    end
    if type(key) ~= "string" or key == "" then
        return false, "key must be a non-empty string"
    end

    local type_name, err = infer_type(value)
    if not type_name then
        return false, err
    end

    local bb_key = self:_build_key(scope, key)
    self._blackboard:set(bb_key, value)
    return true, nil
end

---Read with global fallthrough (if not in operation scope, checks global)
---@param scope string
---@param key string
---@return any|nil value
function VariableStore:get(scope, key)
    if type(scope) ~= "string" or scope == "" then
        return nil
    end
    if type(key) ~= "string" or key == "" then
        return nil
    end

    local bb_key = self:_build_key(scope, key)
    local value = self._blackboard:get(bb_key)
    if value ~= nil then
        return value
    end

    -- Global fallthrough: if scope is not "global", check the global scope
    if scope ~= "global" then
        local global_key = self:_build_key("global", key)
        return self._blackboard:get(global_key)
    end

    return nil
end

---Check existence of a variable
---@param scope string
---@param key string
---@return boolean
function VariableStore:has(scope, key)
    if type(scope) ~= "string" or scope == "" then
        return false
    end
    if type(key) ~= "string" or key == "" then
        return false
    end

    local bb_key = self:_build_key(scope, key)
    return self._blackboard:has(bb_key)
end

---Remove a variable
---@param scope string
---@param key string
---@return boolean success (true if the key existed)
function VariableStore:delete(scope, key)
    if type(scope) ~= "string" or scope == "" then
        return false
    end
    if type(key) ~= "string" or key == "" then
        return false
    end

    local bb_key = self:_build_key(scope, key)
    if not self._blackboard:has(bb_key) then
        return false
    end
    self._blackboard:clear(bb_key)
    return true
end

---Return the list of variable keys in a scope
---Returns only the keys within module.runtime.variables.{scope}.
---@param scope string
---@return table List of variable names (strings)
function VariableStore:list(scope)
    if type(scope) ~= "string" or scope == "" then
        return {}
    end

    local prefix = "module.runtime.variables." .. tostring(scope) .. "."
    local snapshot = self._blackboard:snapshot(prefix)
    local keys = {}
    for full_key, _ in pairs(snapshot) do
        -- Extract the variable name (everything after the scope prefix)
        local var_name = full_key:sub(#prefix + 1)
        if var_name and var_name ~= "" then
            table.insert(keys, var_name)
        end
    end
    table.sort(keys)
    return keys
end

---Clear all variables in a scope
---@param scope string
---@return boolean success
function VariableStore:clear_scope(scope)
    if type(scope) ~= "string" or scope == "" then
        return false
    end

    local prefix = "module.runtime.variables." .. tostring(scope) .. "."
    local snapshot = self._blackboard:snapshot(prefix)
    for full_key, _ in pairs(snapshot) do
        self._blackboard:clear(full_key)
    end
    return true
end

---Get the Sylvannas type of a variable
---@param scope string
---@param key string
---@return string|nil type_name "bool"|"integer"|"float"|"string"|"position"|nil
function VariableStore:get_type(scope, key)
    local value = self:get(scope, key)
    if value == nil then
        return nil
    end
    local type_name, _ = infer_type(value)
    return type_name
end

return VariableStore
