---@class Helpers
local Helpers = {}

---Generate a random number with gaussian (normal) distribution
---Uses Box-Muller transform for true bell curve distribution
---@param min number Minimum value
---@param max number Maximum value
---@return number Value between min and max with gaussian distribution
function Helpers.gaussian_random(min, max)
    -- Box-Muller transform
    local u1 = math.random()
    local u2 = math.random()

    -- Avoid log(0)
    while u1 == 0 do
        u1 = math.random()
    end

    local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)

    local mean = (min + max) / 2
    local stddev = (max - min) / 6  -- 99.7% within range (3 sigma)

    local result = mean + z * stddev
    return math.max(min, math.min(max, result))
end

---Add variance to a value using gaussian distribution
---@param base_value number The base value
---@param variance_percent number Variance as decimal (0.1 = ±10%)
---@return number Value with variance applied
function Helpers.add_variance(base_value, variance_percent)
    local variance = base_value * variance_percent
    return Helpers.gaussian_random(base_value - variance, base_value + variance)
end

---Calculate 3D distance between two positions
---@param pos1 table|vec3 First position with x, y, z fields
---@param pos2 table|vec3 Second position with x, y, z fields
---@return number Distance in game units
function Helpers.distance_3d(pos1, pos2)
    if not pos1 or not pos2 then return math.huge end

    local dx = (pos2.x or 0) - (pos1.x or 0)
    local dy = (pos2.y or 0) - (pos1.y or 0)
    local dz = (pos2.z or 0) - (pos1.z or 0)

    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Calculate 2D horizontal distance between two positions (ignoring Z height).
-- Uses the XY ground plane (WoW/Sylvannas convention: X=east, Y=north, Z=up).
---@param pos1 table|vec3 First position with x, y fields
---@param pos2 table|vec3 Second position with x, y fields
---@return number Distance in game units
function Helpers.distance_2d(pos1, pos2)
    if not pos1 or not pos2 then return math.huge end

    local dx = (pos2.x or 0) - (pos1.x or 0)
    local dy = (pos2.y or 0) - (pos1.y or 0)

    return math.sqrt(dx * dx + dy * dy)
end

---Compute shortest 3D distance from point P to line segment AB
---Returns both the distance and the projection parameter t (0=at A, 1=at B)
---@param px number Point X
---@param py number Point Y
---@param pz number Point Z
---@param ax number Segment start X
---@param ay number Segment start Y
---@param az number Segment start Z
---@param bx number Segment end X
---@param by number Segment end Y
---@param bz number Segment end Z
---@return number distance Distance from P to nearest point on segment AB
---@return number t Projection parameter [0,1] (where on segment the closest point is)
function Helpers.point_to_segment_distance(px, py, pz, ax, ay, az, bx, by, bz)
    local abx, aby, abz = bx - ax, by - ay, bz - az
    local apx, apy, apz = px - ax, py - ay, pz - az
    local ab_sq = abx * abx + aby * aby + abz * abz

    -- Degenerate segment (A == B): return distance to A
    if ab_sq < 1e-8 then
        return math.sqrt(apx * apx + apy * apy + apz * apz), 0
    end

    -- Project P onto AB, clamp to [0, 1]
    local t = (apx * abx + apy * aby + apz * abz) / ab_sq
    t = math.max(0, math.min(1, t))

    -- Closest point on segment
    local cx, cy, cz = ax + t * abx, ay + t * aby, az + t * abz
    local dx, dy, dz = px - cx, py - cy, pz - cz
    return math.sqrt(dx * dx + dy * dy + dz * dz), t
end

---Linear interpolation between two values
---@param a number Start value
---@param b number End value
---@param t number Interpolation factor (0-1)
---@return number Interpolated value
function Helpers.lerp(a, b, t)
    return a + (b - a) * t
end

---Linear interpolation between two vec3 positions
---@param pos1 table|vec3 Start position
---@param pos2 table|vec3 End position
---@param t number Interpolation factor (0-1)
---@return table Interpolated position
function Helpers.lerp_vec3(pos1, pos2, t)
    return {
        x = Helpers.lerp(pos1.x or 0, pos2.x or 0, t),
        y = Helpers.lerp(pos1.y or 0, pos2.y or 0, t),
        z = Helpers.lerp(pos1.z or 0, pos2.z or 0, t)
    }
end

---Clamp a value between min and max
---@param value number The value to clamp
---@param min number Minimum value
---@param max number Maximum value
---@return number Clamped value
function Helpers.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

---Deep copy a table
---@param tbl table The table to copy
---@param seen? table Internal tracking for circular references
---@return table A new table with copied values
function Helpers.deep_copy(tbl, seen)
    if type(tbl) ~= "table" then
        return tbl
    end

    seen = seen or {}
    if seen[tbl] then
        return seen[tbl]
    end

    local copy = {}
    seen[tbl] = copy

    for k, v in pairs(tbl) do
        copy[Helpers.deep_copy(k, seen)] = Helpers.deep_copy(v, seen)
    end

    local mt = getmetatable(tbl)
    if mt then
        setmetatable(copy, mt)
    end

    return copy
end

---Check if a table contains a value
---@param tbl table The table to search
---@param value any The value to find
---@return boolean True if value is found
function Helpers.table_contains(tbl, value)
    if type(tbl) ~= "table" then return false end

    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end

    return false
end

---Check if a table contains a key
---@param tbl table The table to search
---@param key any The key to find
---@return boolean True if key exists
function Helpers.table_has_key(tbl, key)
    if type(tbl) ~= "table" then return false end
    return tbl[key] ~= nil
end

---Get the length of a table (including non-sequential keys)
---@param tbl table The table to count
---@return number Number of entries
function Helpers.table_count(tbl)
    if type(tbl) ~= "table" then return 0 end

    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

---Merge two tables (shallow)
---@param t1 table Base table
---@param t2 table Table to merge in
---@return table Merged table (t1 is modified)
function Helpers.table_merge(t1, t2)
    for k, v in pairs(t2) do
        t1[k] = v
    end
    return t1
end

---Get keys of a table
---@param tbl table The table
---@return table Array of keys
function Helpers.table_keys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    return keys
end

---Get values of a table
---@param tbl table The table
---@return table Array of values
function Helpers.table_values(tbl)
    local values = {}
    for _, v in pairs(tbl) do
        table.insert(values, v)
    end
    return values
end

---Shuffle an array in place using Fisher-Yates algorithm
---@param tbl table The array to shuffle
---@return table The same array, shuffled
function Helpers.shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

---Generate a unique ID
---@return string A unique identifier
function Helpers.generate_id()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end)
end

---Format seconds into human-readable time
---@param seconds number Total seconds
---@return string Formatted time string (e.g., "1h 23m 45s")
function Helpers.format_time(seconds)
    if not seconds or seconds < 0 then return "0s" end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, secs)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

---Format a number with thousand separators
---@param num number The number to format
---@return string Formatted number string
function Helpers.format_number(num)
    local formatted = tostring(math.floor(num))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

---Normalize an angle to 0-2π range
---@param angle number Angle in radians
---@return number Normalized angle
function Helpers.normalize_angle(angle)
    while angle < 0 do
        angle = angle + 2 * math.pi
    end
    while angle >= 2 * math.pi do
        angle = angle - 2 * math.pi
    end
    return angle
end

---Calculate angle between two positions (in radians)
---@param from table|vec3 Start position
---@param to table|vec3 End position
---@return number Angle in radians
function Helpers.angle_to(from, to)
    local dx = (to.x or 0) - (from.x or 0)
    local dz = (to.z or 0) - (from.z or 0)
    return math.atan2(dz, dx)
end

---Check if a position is within a circular area
---@param pos table|vec3 Position to check
---@param center table|vec3 Center of the circle
---@param radius number Radius of the circle
---@return boolean True if position is within the circle
function Helpers.is_within_radius(pos, center, radius)
    return Helpers.distance_2d(pos, center) <= radius
end

---Safe get nested table value
---@param tbl table The table
---@param path string Dot-separated path (e.g., "settings.movement.speed")
---@param default any Default value if not found
---@return any The value or default
function Helpers.get_nested(tbl, path, default)
    if type(tbl) ~= "table" then return default end

    local current = tbl
    for key in string.gmatch(path, "[^%.]+") do
        if type(current) ~= "table" then
            return default
        end
        current = current[key]
        if current == nil then
            return default
        end
    end

    return current
end

---Safe set nested table value
---@param tbl table The table
---@param path string Dot-separated path
---@param value any The value to set
---@return boolean True if successful
function Helpers.set_nested(tbl, path, value)
    if type(tbl) ~= "table" then return false end

    local keys = {}
    for key in string.gmatch(path, "[^%.]+") do
        table.insert(keys, key)
    end

    if #keys == 0 then return false end

    local current = tbl
    for i = 1, #keys - 1 do
        local key = keys[i]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end

    current[keys[#keys]] = value
    return true
end

---Run unit tests
---@return table<string, boolean> Test results
function Helpers._test()
    local results = {}

    -- Test gaussian_random distribution
    local samples = {}
    for i = 1, 1000 do
        samples[i] = Helpers.gaussian_random(0, 100)
    end
    local sum = 0
    local min, max = 100, 0
    for _, v in ipairs(samples) do
        sum = sum + v
        if v < min then min = v end
        if v > max then max = v end
    end
    local mean = sum / #samples
    results.gaussian_mean = (mean > 40 and mean < 60)
    results.gaussian_bounds = (min >= 0 and max <= 100)

    -- Test distance calculations
    local p1 = { x = 0, y = 0, z = 0 }
    local p2 = { x = 3, y = 4, z = 0 }
    results.distance_3d = (math.abs(Helpers.distance_3d(p1, p2) - 5) < 0.001)
    -- p1={0,0,0}, p2={3,4,0}: XY horizontal distance = sqrt(9+16) = 5
    results.distance_2d = (math.abs(Helpers.distance_2d(p1, p2) - 5) < 0.001)

    -- Test clamp
    results.clamp_below = (Helpers.clamp(-5, 0, 10) == 0)
    results.clamp_above = (Helpers.clamp(15, 0, 10) == 10)
    results.clamp_within = (Helpers.clamp(5, 0, 10) == 5)

    -- Test lerp
    results.lerp = (math.abs(Helpers.lerp(0, 10, 0.5) - 5) < 0.001)

    -- Test deep_copy
    local original = { a = 1, b = { c = 2 } }
    local copy = Helpers.deep_copy(original)
    copy.b.c = 3
    results.deep_copy = (original.b.c == 2 and copy.b.c == 3)

    -- Test table_contains
    local arr = { 1, 2, 3, 4, 5 }
    results.table_contains_yes = Helpers.table_contains(arr, 3)
    results.table_contains_no = not Helpers.table_contains(arr, 10)

    -- Test table_count
    local tbl = { a = 1, b = 2, c = 3 }
    results.table_count = (Helpers.table_count(tbl) == 3)

    -- Test is_within_radius (XY ground plane: X=east, Y=north, Z=height)
    local center = { x = 0, y = 0, z = 0 }
    local inside = { x = 3, y = 4, z = 0 }  -- XY distance = sqrt(9+16) = 5
    local outside = { x = 10, y = 10, z = 0 }  -- XY distance = sqrt(200) > 10
    results.within_radius_yes = Helpers.is_within_radius(inside, center, 10)
    results.within_radius_no = not Helpers.is_within_radius(outside, center, 10)

    -- Test get_nested
    local nested = { a = { b = { c = 42 } } }
    results.get_nested = (Helpers.get_nested(nested, "a.b.c", 0) == 42)
    results.get_nested_default = (Helpers.get_nested(nested, "a.x.y", 99) == 99)

    -- Test set_nested
    local set_test = {}
    Helpers.set_nested(set_test, "a.b.c", 123)
    results.set_nested = (set_test.a.b.c == 123)

    -- Test format_time
    results.format_time = (Helpers.format_time(3661) == "1h 1m 1s")

    -- Test point_to_segment_distance: perpendicular projection
    local seg_dist, seg_t = Helpers.point_to_segment_distance(0, 5, 0, 0, 0, 0, 10, 0, 0)
    results.point_to_seg_perp = (math.abs(seg_dist - 5) < 0.001)
    results.point_to_seg_t = (math.abs(seg_t - 0) < 0.001)

    -- Test point_to_segment_distance: beyond segment end (clamps to t=1)
    local seg_dist2 = Helpers.point_to_segment_distance(15, 0, 0, 0, 0, 0, 10, 0, 0)
    results.point_to_seg_end = (math.abs(seg_dist2 - 5) < 0.001)

    -- Test point_to_segment_distance: degenerate zero-length segment
    local seg_dist3 = Helpers.point_to_segment_distance(3, 4, 0, 0, 0, 0, 0, 0, 0)
    results.point_to_seg_degenerate = (math.abs(seg_dist3 - 5) < 0.001)

    return results
end

return Helpers
