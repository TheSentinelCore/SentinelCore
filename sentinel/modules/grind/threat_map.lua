local ThreatMap = {}
ThreatMap.__index = ThreatMap

local DANGER_THRESHOLD = 8
local DEFAULT_QUERY_RADIUS = 60
local GC_MIN_WEIGHT = 0.1
local MAX_ENTRIES = 500

local HALF_LIVES_MS = {
    DEATH           = 30 * 60 * 1000,  -- 30 min
    PVP_PLAYER      = 10 * 60 * 1000,  -- 10 min
    DANGEROUS_MOB   = 15 * 60 * 1000,  -- 15 min
    STUCK           = 20 * 60 * 1000,  -- 20 min
}

local LN2 = math.log(2)

local function distance_3d(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Compute the decayed weight using exponential half-life decay.
---Formula: weight * 2^(-(now - timestamp) / half_life_ms)
---@param weight number Original weight
---@param timestamp number Time the entry was recorded (ms)
---@param half_life_ms number Half-life in milliseconds
---@param now_ms number Current time in milliseconds
---@return number effective_weight
local function decay(weight, timestamp, half_life_ms, now_ms)
    local elapsed = now_ms - timestamp
    if elapsed <= 0 then return weight end
    return weight * math.exp(-LN2 * elapsed / half_life_ms)
end

---Create a new ThreatMap instance.
---@return table threat_map
function ThreatMap:new()
    local o = {
        _entries = {},
    }
    setmetatable(o, self)
    return o
end

---Record a threat at a position.
---@param threat_type string One of DEATH, PVP_PLAYER, DANGEROUS_MOB, STUCK
---@param position table { x, y, z }
---@param weight number Threat weight
---@param timestamp number Time in milliseconds
function ThreatMap:record(threat_type, position, weight, timestamp)
    local half_life_ms = HALF_LIVES_MS[threat_type]
    if not half_life_ms then
        error("unknown threat type: " .. tostring(threat_type))
    end
    -- Enforce hard cap to prevent unbounded growth in long sessions
    if #self._entries >= MAX_ENTRIES then
        table.remove(self._entries, 1)
    end
    self._entries[#self._entries + 1] = {
        type = threat_type,
        position = { x = position.x, y = position.y, z = position.z },
        weight = weight,
        timestamp = timestamp,
        half_life_ms = half_life_ms,
    }
end

---Sum effective weights of all entries within radius of position.
---@param position table { x, y, z }
---@param radius number Search radius in yards
---@param now_ms number Current time in milliseconds
---@return number heat
function ThreatMap:get_heat(position, radius, now_ms)
    local heat = 0
    for i = 1, #self._entries do
        local e = self._entries[i]
        if distance_3d(position, e.position) <= radius then
            heat = heat + decay(e.weight, e.timestamp, e.half_life_ms, now_ms)
        end
    end
    return heat
end

---Check if a position is dangerous (heat exceeds threshold).
---Uses DEFAULT_QUERY_RADIUS for the spatial query.
---@param position table { x, y, z }
---@param now_ms number Current time in milliseconds
---@return boolean
function ThreatMap:is_dangerous(position, now_ms)
    return self:get_heat(position, DEFAULT_QUERY_RADIUS, now_ms) > DANGER_THRESHOLD
end

---Return the index of the hotspot with the lowest heat.
---Hotspot format: { center = { x, y, z }, radius = number }
---@param hotspots table Array of hotspot tables
---@param now_ms number Current time in milliseconds
---@return number|nil index Index of safest hotspot, or nil if list is empty
function ThreatMap:get_safest_hotspot(hotspots, now_ms)
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

---Remove entries whose effective weight has decayed below GC_MIN_WEIGHT.
---@param now_ms number Current time in milliseconds
function ThreatMap:gc(now_ms)
    local kept = {}
    for i = 1, #self._entries do
        local e = self._entries[i]
        local ew = decay(e.weight, e.timestamp, e.half_life_ms, now_ms)
        if ew >= GC_MIN_WEIGHT then
            kept[#kept + 1] = e
        end
    end
    self._entries = kept
end

---Return the number of entries currently stored.
---@return number
function ThreatMap:entry_count()
    return #self._entries
end

return ThreatMap
