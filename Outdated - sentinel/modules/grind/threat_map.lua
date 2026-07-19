local ThreatMap = {}
ThreatMap.__index = ThreatMap

local SpatialThreatMap = require("modules/grind/spatial_threat_map")
local ThreatTypes = require("modules/grind/threat_types")

---Create a new ThreatMap instance.
---@return table threat_map
function ThreatMap:new()
    local o = {
        _spatial = SpatialThreatMap:new(),
    }
    setmetatable(o, self)
    return o
end

---Record a threat at a position.
---Accepts either a ThreatType descriptor or a string key for backwards compatibility.
---
---@param threat_type table|string ThreatType descriptor or string key (DEATH, PVP_PLAYER, etc.)
---@param position table { x, y, z }
---@param weight number|nil Threat weight (defaults to ThreatType.default_weight if nil)
---@param timestamp number|nil Time in milliseconds
function ThreatMap:record(threat_type, position, weight, timestamp)
    local tt = type(threat_type) == "table" and threat_type or ThreatTypes.resolve(threat_type)
    if not tt then
        error("unknown threat type: " .. tostring(threat_type))
    end

    local entry_weight = weight or tt.default_weight
    local ts = timestamp or (core and core.get_system_time and core.get_system_time() or 0)
    self._spatial:record(tt.key, position, ts, entry_weight)
end

---Sum effective weights of all entries within radius of position.
---@param position table { x, y, z }
---@param radius number Search radius in yards
---@param now_ms number Current time in milliseconds
---@return number heat
function ThreatMap:get_heat(position, radius, now_ms)
    return self._spatial:get_heat(position, radius, now_ms)
end

---Check if a position is dangerous (heat exceeds threshold).
---Uses DEFAULT_QUERY_RADIUS for the spatial query.
---@param position table { x, y, z }
---@param now_ms number Current time in milliseconds
---@return boolean
function ThreatMap:is_dangerous(position, now_ms)
    return self._spatial:is_dangerous(position, now_ms)
end

---Return the index of the hotspot with the lowest heat.
---Hotspot format: { center = { x, y, z }, radius = number }
---@param hotspots table Array of hotspot tables
---@param now_ms number Current time in milliseconds
---@return number|nil index Index of safest hotspot, or nil if list is empty
function ThreatMap:get_safest_hotspot(hotspots, now_ms)
    return self._spatial:get_safest_hotspot(hotspots, now_ms)
end

---Remove entries whose effective weight has decayed below GC_MIN_WEIGHT.
---@param now_ms number Current time in milliseconds
function ThreatMap:gc(now_ms)
    self._spatial:gc(now_ms)
end

---Return the number of entries currently stored.
---@return number
function ThreatMap:entry_count()
    return self._spatial:entry_count()
end

return ThreatMap