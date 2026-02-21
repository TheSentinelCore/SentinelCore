---@module BGBOT.shared.utils
-- Shared utility functions: distance, vec3 helpers, table utils.
-- All functions are pure (no API side-effects).

local utils = {}

local sqrt = math.sqrt
local max  = math.max
local min  = math.min

----------------------------------------------------------------------
-- Vec3 helpers  (using {x,y,z} tables)
----------------------------------------------------------------------

---@param a table {x,y,z}
---@param b table {x,y,z}
---@return number
function utils.distance_3d(a, b)
    if not a or not b
        or a.x == nil or a.y == nil or a.z == nil
        or b.x == nil or b.y == nil or b.z == nil then
        return 999999
    end
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return sqrt(dx * dx + dy * dy + dz * dz)
end

---@param a table {x,y,z}
---@param b table {x,y,z}
---@return number  horizontal distance (ignores Z)
function utils.distance_2d(a, b)
    if not a or not b
        or a.x == nil or a.y == nil
        or b.x == nil or b.y == nil then
        return 999999
    end
    local dx = a.x - b.x
    local dy = a.y - b.y
    return sqrt(dx * dx + dy * dy)
end

---@param pos table {x,y,z}
---@param game_obj game_object  object with :get_position() → vec3
---@return number
function utils.distance_to_object(pos, game_obj)
    if not game_obj then return 999999 end
    local ok, op = pcall(function()
        return game_obj:get_position()
    end)
    if not ok or not op then return 999999 end
    return utils.distance_3d(pos, { x = op.x or 0, y = op.y or 0, z = op.z or 0 })
end

---@param game_obj game_object
---@return table {x,y,z}
function utils.pos_from_object(game_obj)
    if not game_obj then return { x = 0, y = 0, z = 0 } end
    local ok, p = pcall(function()
        return game_obj:get_position()
    end)
    if not ok or not p then
        return { x = 0, y = 0, z = 0 }
    end
    return { x = p.x or 0, y = p.y or 0, z = p.z or 0 }
end

----------------------------------------------------------------------
-- Confidence
----------------------------------------------------------------------

---@param last_seen number  core.time() timestamp
---@param now number  current core.time()
---@param decay_per_sec number  default 0.1
---@return number  0.0 – 1.0
function utils.compute_confidence(last_seen, now, decay_per_sec)
    local age = now - last_seen
    if age <= 0 then return 1.0 end
    return max(0.0, 1.0 - (age * (decay_per_sec or 0.1)))
end

----------------------------------------------------------------------
-- Table utilities
----------------------------------------------------------------------

--- Shallow copy
function utils.shallow_copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

--- Count elements matching predicate
function utils.count_where(list, predicate)
    local n = 0
    for _, v in ipairs(list) do
        if predicate(v) then n = n + 1 end
    end
    return n
end

--- Filter list by predicate
function utils.filter(list, predicate)
    local out = {}
    for _, v in ipairs(list) do
        if predicate(v) then out[#out + 1] = v end
    end
    return out
end

--- Safe clamp
function utils.clamp(val, lo, hi)
    return max(lo, min(hi, val))
end

----------------------------------------------------------------------
-- Handle-key helper  (DEC-011)
----------------------------------------------------------------------

---@param game_obj game_object
---@return string  stable key for entity table
function utils.handle_key(game_obj)
    return tostring(game_obj)
end

return utils
