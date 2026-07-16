local Quadtree = {}
Quadtree.__index = Quadtree

local DEFAULT_CAPACITY = 10
local DEFAULT_MAX_DEPTH = 8

---@class Quadtree
---@field boundary table { x, y, z, half_size }
---@field capacity number
---@field max_depth number
---@field depth number
---@field entries table[]
---@field divided boolean
---@field nw Quadtree|nil
---@field ne Quadtree|nil
---@field sw Quadtree|nil
---@field se Quadtree|nil

---Create a new Quadtree
---@param center table { x, y, z } Center of the root node
---@param half_size number Half-size of the root node (world covers center +/- half_size)
---@param capacity number|nil Max entries per node before subdivision (default 10)
---@param max_depth number|nil Maximum tree depth (default 8)
---@return Quadtree
function Quadtree:new(center, half_size, capacity, max_depth)
    local o = {
        boundary = {
            x = center.x or 0,
            y = center.y or 0,
            z = center.z or 0,
            half_size = half_size or 5000,
        },
        capacity = capacity or DEFAULT_CAPACITY,
        max_depth = max_depth or DEFAULT_MAX_DEPTH,
        depth = 0,
        entries = {},
        divided = false,
        nw = nil, ne = nil, sw = nil, se = nil,
    }
    setmetatable(o, self)
    return o
end

---Check if a point is within the boundary
---@param point table { x, y, z }
---@return boolean
function Quadtree:_contains(point)
    local b = self.boundary
    return point.x >= b.x - b.half_size
        and point.x <= b.x + b.half_size
        and point.y >= b.y - b.half_size
        and point.y <= b.y + b.half_size
end

---Subdivide this node into four children
function Quadtree:_subdivide()
    local b = self.boundary
    local hs = b.half_size / 2
    local d = self.depth + 1

    self.nw = Quadtree:new({ x = b.x - hs, y = b.y + hs, z = b.z }, hs, self.capacity, self.max_depth)
    self.nw.depth = d
    self.ne = Quadtree:new({ x = b.x + hs, y = b.y + hs, z = b.z }, hs, self.capacity, self.max_depth)
    self.ne.depth = d
    self.sw = Quadtree:new({ x = b.x - hs, y = b.y - hs, z = b.z }, hs, self.capacity, self.max_depth)
    self.sw.depth = d
    self.se = Quadtree:new({ x = b.x + hs, y = b.y - hs, z = b.z }, hs, self.capacity, self.max_depth)
    self.se.depth = d
    self.divided = true
end

---Insert an entry into the quadtree
---@param entry table Entry with position { x, y, z }
---@return boolean success
function Quadtree:insert(entry)
    if not self:_contains(entry.position) then
        return false
    end

    if #self.entries < self.capacity or self.depth >= self.max_depth then
        self.entries[#self.entries + 1] = entry
        return true
    end

    if not self.divided then
        self:_subdivide()
    end

    return self.nw:insert(entry)
        or self.ne:insert(entry)
        or self.sw:insert(entry)
        or self.se:insert(entry)
end

---Query all entries within radius of a point
---@param point table { x, y, z }
---@param radius number
---@param results table|nil Output array (created if nil)
---@return table entries
function Quadtree:query_radius(point, radius, results)
    results = results or {}
    local b = self.boundary

    -- Quick reject: if query circle doesn't intersect this node's boundary
    local dx = math.max(0, math.abs(point.x - b.x) - b.half_size - radius)
    local dy = math.max(0, math.abs(point.y - b.y) - b.half_size - radius)
    if dx * dx + dy * dy > radius * radius then
        return results
    end

    -- Check entries in this node
    for _, entry in ipairs(self.entries) do
        local ep = entry.position
        local dist_sq = (ep.x - point.x)^2 + (ep.y - point.y)^2 + (ep.z - point.z)^2
        if dist_sq <= radius * radius then
            results[#results + 1] = entry
        end
    end

    -- Recurse into children
    if self.divided then
        self.nw:query_radius(point, radius, results)
        self.ne:query_radius(point, radius, results)
        self.sw:query_radius(point, radius, results)
        self.se:query_radius(point, radius, results)
    end

    return results
end

---Get all entries in the tree
---@param results table|nil Output array
---@return table entries
function Quadtree:all_entries(results)
    results = results or {}
    for _, entry in ipairs(self.entries) do
        results[#results + 1] = entry
    end
    if self.divided then
        self.nw:all_entries(results)
        self.ne:all_entries(results)
        self.sw:all_entries(results)
        self.se:all_entries(results)
    end
    return results
end

---Get entry count
---@return number
function Quadtree:count()
    local n = #self.entries
    if self.divided then
        n = n + self.nw:count() + self.ne:count() + self.sw:count() + self.se:count()
    end
    return n
end

---Clear the tree
function Quadtree:clear()
    self.entries = {}
    self.divided = false
    self.nw = nil
    self.ne = nil
    self.sw = nil
    self.se = nil
end

return Quadtree