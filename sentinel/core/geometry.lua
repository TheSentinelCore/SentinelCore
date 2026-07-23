local Geometry = {}

---Compute 3D distance between two {x,y,z} points.
---Nil-safe: returns math.huge if either point is invalid.
---@param a table|nil Point with x, y, z fields
---@param b table|nil Point with x, y, z fields
---@return number Distance in yards, or math.huge if invalid
function Geometry.distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Compute squared 3D distance between two {x,y,z} points.
---Nil-safe: returns math.huge if either point is invalid, matching
---Geometry.distance's "unmeasurable" sentinel so callers can compare the two
---interchangeably (e.g. distance_sq(a, b) < distance_sq(a, c) still holds when
---one side is unmeasurable). Use this in nearest-neighbor loops that only
---compare distances and don't need the sqrt.
---@param a table|nil Point with x, y, z fields
---@param b table|nil Point with x, y, z fields
---@return number Squared distance in yards^2, or math.huge if invalid
function Geometry.distance_sq(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return dx * dx + dy * dy + dz * dz
end

---Compute a point at a given distance "away from" a center point.
---Used for flee behavior: compute position away from dangerous center.
---@param center table {x, y, z}
---@param position table {x, y, z}
---@param distance number Desired distance from center
---@return table|nil Point {x, y, z}, or nil if inputs invalid
function Geometry.away_from(center, position, distance)
    if type(center) ~= "table" or type(position) ~= "table" then
        return nil
    end
    local cx = center.x or 0
    local cy = center.y or 0
    local px = position.x or 0
    local py = position.y or 0
    local away_dx = px - cx
    local away_dy = py - cy
    local away_len = math.sqrt(away_dx * away_dx + away_dy * away_dy)
    if away_len < 1 then
        away_dx, away_dy, away_len = 1, 0, 1
    end
    local scale = distance / away_len
    return {
        x = px + away_dx * scale,
        y = py + away_dy * scale,
        z = (position.z or 0),
    }
end

return Geometry