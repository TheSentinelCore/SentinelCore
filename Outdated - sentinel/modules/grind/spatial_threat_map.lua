local SpatialThreatMap = {}
SpatialThreatMap.__index = SpatialThreatMap

local Geometry = require("core/geometry")
local ThreatTypes = require("modules/grind/threat_types")

local DANGER_THRESHOLD = 8
local DEFAULT_QUERY_RADIUS = 60
local GC_MIN_WEIGHT = 0.1
local MAX_ENTRIES = 500
local LN2 = math.log(2)

-- Quadtree node
local QuadtreeNode = {}
QuadtreeNode.__index = QuadtreeNode

function QuadtreeNode:new(boundary, capacity)
    local o = setmetatable({
        _boundary = boundary,  -- {x, y, width, height} in 2D
        _capacity = capacity or 8,
        _entries = {},
        _divided = false,
        _nw = nil, _ne = nil, _sw = nil, _se = nil,
    }, self)
    return o
end

function QuadtreeNode:_subdivide()
    local x, y, w, h = self._boundary.x, self._boundary.y, self._boundary.w / 2, self._boundary.h / 2
    self._nw = QuadtreeNode:new({ x = x, y = y, w = w, h = h }, self._capacity)
    self._ne = QuadtreeNode:new({ x = x + w, y = y, w = w, h = h }, self._capacity)
    self._sw = QuadtreeNode:new({ x = x, y = y + h, w = w, h = h }, self._capacity)
    self._se = QuadtreeNode:new({ x = x + w, y = y + h, w = w, h = h }, self._capacity)
    self._divided = true

    -- Redistribute existing entries
    for _, entry in ipairs(self._entries) do
        self:_insert_into_children(entry)
    end
    self._entries = {}
end

function QuadtreeNode:_contains(entry)
    local b = self._boundary
    local ex, ey = entry.position.x, entry.position.y
    return ex >= b.x and ex < b.x + b.w and ey >= b.y and ey < b.y + b.h
end

function QuadtreeNode:_insert_into_children(entry)
    if entry.position.x < self._nw._boundary.x + self._nw._boundary.w then
        if entry.position.y < self._nw._boundary.y + self._nw._boundary.h then
            self._nw:insert(entry)
        else
            self._sw:insert(entry)
        end
    else
        if entry.position.y < self._ne._boundary.y + self._ne._boundary.h then
            self._ne:insert(entry)
        else
            self._se:insert(entry)
        end
    end
end

function QuadtreeNode:insert(entry)
    if not self:_contains(entry) then return false end

    if #self._entries < self._capacity and not self._divided then
        table.insert(self._entries, entry)
        return true
    end

    if not self._divided then
        self:_subdivide()
    end

    return self._nw:insert(entry) or self._ne:insert(entry)
        or self._sw:insert(entry) or self._se:insert(entry)
end

function QuadtreeNode:query_range(range, found, now_ms)
    -- range: { x, y, radius }
    local b = self._boundary
    local dx = math.max(0, math.max(b.x - range.x - range.radius, range.x - range.radius - (b.x + b.w)))
    local dy = math.max(0, math.max(b.y - range.y - range.radius, range.y - range.radius - (b.y + b.h)))
    if dx * dx + dy * dy > range.radius * range.radius then return end

    for _, entry in ipairs(self._entries) do
        local dist = Geometry.distance({ x = entry.position.x, y = entry.position.y, z = 0 },
                                      { x = range.x, y = range.y, z = 0 })
        if dist <= range.radius then
            local ew = decay(entry.weight, entry.timestamp, entry.half_life_ms, now_ms)
            if ew >= GC_MIN_WEIGHT then
                table.insert(found, entry)
            end
        end
    end

    if self._divided then
        self._nw:query_range(range, found, now_ms)
        self._ne:query_range(range, found, now_ms)
        self._sw:query_range(range, found, now_ms)
        self._se:query_range(range, found, now_ms)
    end
end

function QuadtreeNode:gc(now_ms, kept)
    local i = 1
    while i <= #self._entries do
        local e = self._entries[i]
        local ew = decay(e.weight, e.timestamp, e.half_life_ms, now_ms)
        if ew < GC_MIN_WEIGHT then
            table.remove(self._entries, i)
        else
            i = i + 1
        end
    end
    if self._divided then
        self._nw:gc(now_ms, kept)
        self._ne:gc(now_ms, kept)
        self._sw:gc(now_ms, kept)
        self._se:gc(now_ms, kept)
    end
end

function QuadtreeNode:count()
    local c = #self._entries
    if self._divided then
        c = c + self._nw:count() + self._ne:count() + self._sw:count() + self._se:count()
    end
    return c
end

-- Decay function
local function decay(weight, timestamp, half_life_ms, now_ms)
    local elapsed = now_ms - timestamp
    if elapsed <= 0 then return weight end
    return weight * math.exp(-LN2 * elapsed / half_life_ms)
end

---Create a new SpatialThreatMap instance.
---@param boundary table|nil Optional boundary {x, y, w, h}. Defaults to world bounds.
---@return table spatial_threat_map
function SpatialThreatMap:new(boundary)
    local o = setmetatable({
        _root = QuadtreeNode:new(boundary or { x = -2000, y = -2000, w = 4000, h = 4000 }, 8),
        _count = 0,
    }, self)
    return o
end

---Record a threat at a position.
---@param threat_type string Threat type key (DEATH, PVP_PLAYER, etc.)
---@param position table { x, y, z }
---@param timestamp number Time in milliseconds
---@param weight number Threat weight
function SpatialThreatMap:record(threat_type, position, timestamp, weight)
    if self._count >= MAX_ENTRIES then
        -- Could implement LRU eviction here if needed
        return
    end

    local tt = ThreatTypes[threat_type] or ThreatTypes.DEATH
    local entry = {
        type = threat_type,
        position = { x = position.x, y = position.y, z = position.z },
        weight = weight or tt.default_weight,
        timestamp = timestamp,
        half_life_ms = tt.half_life_ms,
    }

    if self._root:insert(entry) then
        self._count = self._count + 1
    end
end

---Get heat at position within radius.
---@param position table { x, y, z }
---@param radius number Search radius
---@param now_ms number Current time
---@return number heat
function SpatialThreatMap:get_heat(position, radius, now_ms)
    local found = {}
    self._root:query_range({ x = position.x, y = position.y, radius = radius }, found, now_ms)
    local heat = 0
    for _, entry in ipairs(found) do
        heat = heat + decay(entry.weight, entry.timestamp, entry.half_life_ms, now_ms)
    end
    return heat
end

---Check if position is dangerous.
---@param position table { x, y, z }
---@param now_ms number Current time
---@return boolean
function SpatialThreatMap:is_dangerous(position, now_ms)
    return self:get_heat(position, DEFAULT_QUERY_RADIUS, now_ms) > DANGER_THRESHOLD
end

---Find safest hotspot from a list.
---@param hotspots table Array of { center = {x,y,z}, radius = number }
---@param now_ms number Current time
---@return number|nil index
function SpatialThreatMap:get_safest_hotspot(hotspots, now_ms)
    if #hotspots == 0 then return nil end
    local best_idx = 1
    local best_heat = self:get_heat(hotspots[1].center, DEFAULT_QUERY_RADIUS, now_ms)
    for i = 2, #hotspots do
        local heat = self:get_heat(hotspots[i].center, DEFAULT_QUERY_RADIUS, now_ms)
        if heat < best_heat then
            best_heat = heat
            best_idx = i
        end
    end
    return best_idx
end

---Garbage collect decayed entries.
---@param now_ms number Current time
function SpatialThreatMap:gc(now_ms)
    -- Rebuild tree by collecting surviving entries
    local survivors = {}
    self._root:gc(now_ms, survivors)
    -- For simplicity, rebuild the entire tree
    local new_root = QuadtreeNode:new({ x = -2000, y = -2000, w = 4000, h = 4000 }, 8)
    for _, entry in ipairs(survivors) do
        new_root:insert(entry)
    end
    self._root = new_root
    self._count = new_root:count()
end

---Return entry count.
---@return number
function SpatialThreatMap:entry_count()
    return self._count
end

return SpatialThreatMap