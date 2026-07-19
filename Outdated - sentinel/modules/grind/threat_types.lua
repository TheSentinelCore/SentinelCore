---Threat type descriptors with their default weights and half-lives.
---Centralizes the constants that ThreatMap previously defined internally,
---so callers don't need to know the magic strings or weights.
---
---Usage:
---   ThreatMap:record(ThreatTypes.DEATH, position, now_ms)
---   ThreatMap:record(ThreatTypes.PVP_PLAYER, position, now_ms)
---
---Each type has: key, default_weight, half_life_ms
local ThreatTypes = {}

ThreatTypes.DEATH = {
    key = "DEATH",
    default_weight = 10,
    half_life_ms = 30 * 60 * 1000,  -- 30 min
}

ThreatTypes.PVP_PLAYER = {
    key = "PVP_PLAYER",
    default_weight = 8,
    half_life_ms = 10 * 60 * 1000,  -- 10 min
}

ThreatTypes.DANGEROUS_MOB = {
    key = "DANGEROUS_MOB",
    default_weight = 5,
    half_life_ms = 15 * 60 * 1000,  -- 15 min
}

ThreatTypes.STUCK = {
    key = "STUCK",
    default_weight = 2,
    half_life_ms = 20 * 60 * 1000,  -- 20 min
}

---Resolve a threat descriptor from a string key (backwards-compatible).
---@param type_key string|table The string key or ThreatType descriptor
---@return table|nil The resolved threat type descriptor
function ThreatTypes.resolve(type_key)
    if type(type_key) == "table" and type_key.key then
        return type_key
    end
    for _, tt in pairs(ThreatTypes) do
        if type(tt) == "table" and tt.key == type_key then
            return tt
        end
    end
    return nil
end

return ThreatTypes
