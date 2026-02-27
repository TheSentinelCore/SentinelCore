local PathEntropy = require("ai/PathEntropy")

local PositioningService = {}

-- Shared entropy instance for position jitter
local _entropy = PathEntropy:new({ waypoint_jitter_radius = 2.0 })

--- Compute the centroid (average position) of a list of positions.
---@param positions table[] Array of {x, y, z}
---@return table|nil {x, y, z}
function PositioningService.centroid(positions)
    if not positions or #positions == 0 then return nil end
    local sx, sy, sz = 0, 0, 0
    for i = 1, #positions do
        local p = positions[i]
        sx = sx + (p.x or 0)
        sy = sy + (p.y or 0)
        sz = sz + (p.z or 0)
    end
    local n = #positions
    return { x = sx / n, y = sy / n, z = sz / n }
end

--- Compute kite position: move `distance` yards AWAY from threat centroid.
---@param from_pos table {x, y, z}
---@param threat_centroid table {x, y, z}
---@param distance number
---@return table {x, y, z}
function PositioningService.kite_position(from_pos, threat_centroid, distance)
    if not from_pos or not threat_centroid then return from_pos end
    local dx = (from_pos.x or 0) - (threat_centroid.x or 0)
    local dy = (from_pos.y or 0) - (threat_centroid.y or 0)
    local dz = (from_pos.z or 0) - (threat_centroid.z or 0)
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then
        return { x = (from_pos.x or 0) + distance, y = from_pos.y or 0, z = from_pos.z or 0 }
    end
    local nx, ny, nz = dx / len, dy / len, dz / len
    return {
        x = (from_pos.x or 0) + nx * distance,
        y = (from_pos.y or 0) + ny * distance,
        z = (from_pos.z or 0) + nz * distance,
    }
end

--- Compute optimal AoE center: enemy centroid clamped to max_range from player.
---@param player_pos table {x, y, z}
---@param enemy_positions table[] Array of {x, y, z}
---@param max_range number
---@return table|nil {x, y, z}
function PositioningService.aoe_center(player_pos, enemy_positions, max_range)
    local center = PositioningService.centroid(enemy_positions)
    if not center or not player_pos then return center end
    local dx = (center.x or 0) - (player_pos.x or 0)
    local dy = (center.y or 0) - (player_pos.y or 0)
    local dz = (center.z or 0) - (player_pos.z or 0)
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist <= max_range then return center end
    local scale = max_range / dist
    return {
        x = (player_pos.x or 0) + dx * scale,
        y = (player_pos.y or 0) + dy * scale,
        z = (player_pos.z or 0) + dz * scale,
    }
end

--- Check if pos is within range of ref.
---@param pos table {x, y, z}
---@param ref table {x, y, z}
---@param range number
---@return boolean
function PositioningService.in_range(pos, ref, range)
    if not pos or not ref then return false end
    local dx = (pos.x or 0) - (ref.x or 0)
    local dy = (pos.y or 0) - (ref.y or 0)
    local dz = (pos.z or 0) - (ref.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= range
end

--- Compute kite position with anti-detection jitter applied.
---@param from_pos table {x, y, z}
---@param threat_centroid table {x, y, z}
---@param distance number
---@return table {x, y, z}
function PositioningService.jitter_kite_position(from_pos, threat_centroid, distance)
    local base = PositioningService.kite_position(from_pos, threat_centroid, distance)
    if not base then return base end
    return _entropy:jitter_position(base)
end

--- Compute AoE center with anti-detection jitter applied.
---@param player_pos table {x, y, z}
---@param enemy_positions table[] Array of {x, y, z}
---@param max_range number
---@return table|nil {x, y, z}
function PositioningService.jitter_aoe_center(player_pos, enemy_positions, max_range)
    local base = PositioningService.aoe_center(player_pos, enemy_positions, max_range)
    if not base then return base end
    return _entropy:jitter_position(base)
end

return PositioningService
