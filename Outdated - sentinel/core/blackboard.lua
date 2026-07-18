local Schema = require("core/blackboard_schema")

local Blackboard = {}
Blackboard.__index = Blackboard

function Blackboard:new()
    local o = setmetatable({}, Blackboard)
    o._data = {}
    return o
end

function Blackboard:get(key, default)
    local value = self._data[key]
    if value == nil then
        return default
    end
    return value
end

function Blackboard:set(key, value)
    local ok, err = Schema.validate_key(key)
    if not ok then
        error("blackboard set rejected: " .. tostring(err) .. " for key " .. tostring(key))
    end
    self._data[key] = value
end

function Blackboard:clear(key)
    self._data[key] = nil
end

function Blackboard:has(key)
    return self._data[key] ~= nil
end

function Blackboard:snapshot(prefix)
    local out = {}
    for key, value in pairs(self._data) do
        if not prefix or key:find(prefix, 1, true) == 1 then
            out[key] = value
        end
    end
    return out
end

return Blackboard
