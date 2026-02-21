---@class RotationRegistry
---@field private _by_key table<string, table>
local RotationRegistry = {}
RotationRegistry.__index = RotationRegistry

---@return RotationRegistry
function RotationRegistry:new()
    local o = setmetatable({}, RotationRegistry)
    o._by_key = {}
    return o
end

---@param class_id number
---@param spec_id number
---@param provider table
function RotationRegistry:register(class_id, spec_id, provider)
    local key = tostring(class_id) .. ":" .. tostring(spec_id)
    self._by_key[key] = provider
end

---@param class_id number
---@param spec_id number
---@return table|nil
function RotationRegistry:get(class_id, spec_id)
    local key = tostring(class_id) .. ":" .. tostring(spec_id)
    return self._by_key[key]
end

return RotationRegistry
