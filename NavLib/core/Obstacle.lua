-- Obstacle.lua
-- Obstacle avoidance via trace_line probing + avoidance zone memory.
-- Proactive: MovementModule scans upcoming waypoint segments every 1.5s.
-- Reactive fallback: stuck handler probes from player position.

local DEFAULT_CONFIG = {
    avoidance_cost       = 5.0,    -- cost multiplier for path-avoid endpoint
    avoidance_radius     = 3.0,    -- yards: radius of avoidance zone around hit point
    zone_ttl             = 120.0,  -- seconds: auto-expire zones after this
    zone_prune_dist      = 100.0,  -- yards: remove zones farther than this
    max_zones            = 5,      -- cap remembered zones (well under NavBuddy's 20 limit)
    collision_flags      = 0x00000001, -- DoodadCollision

    -- Reactive probe (from player position, triggered by stuck handler)
    probe_distance       = 8.0,    -- yards: how far ahead to probe
    probe_spread_deg     = 20,     -- degrees: spread angle for side rays
    probe_height_offset  = 1.0,    -- yards: raise probe origin above ground

    -- Proactive look-ahead (along waypoint segments, periodic)
    lookahead_height_offset = 1.5, -- yards: raise ray above waypoint Z
    lookahead_spread_deg    = 15,  -- degrees: narrower spread for segment tracing
    lookahead_segments      = 3,   -- how many upcoming segments to check
}

---@class Obstacle
---@field private _config table
---@field private _zones table[]  -- remembered avoidance zones
local Obstacle = {}
Obstacle.__index = Obstacle

---Create a new Obstacle
---@param config? table Override default config values
---@return Obstacle
function Obstacle:new(config)
    local o = setmetatable({}, Obstacle)

    o._config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        o._config[k] = v
    end
    if config then
        for k, v in pairs(config) do
            o._config[k] = v
        end
    end

    o._zones = {}

    return o
end

---Update config values at runtime
---@param overrides table Key-value pairs to merge
function Obstacle:update_config(overrides)
    if not overrides then return end
    for k, v in pairs(overrides) do
        self._config[k] = v
    end
end

---Reset all remembered zones
function Obstacle:clear()
    self._zones = {}
end

-- Probing ----------------------------------------------------------------

---Probe forward from player toward target using trace_line.
---Casts a main ray + two spread rays at ±spread_deg.
---@param player_pos vec3 Current player position
---@param target_pos vec3 Direction to probe toward (next waypoint)
---@return vec3|nil hit_pos Approximate hit position, or nil if clear
function Obstacle:probe_forward(player_pos, target_pos)
    local cfg = self._config
    local flags = cfg.collision_flags

    -- Direction vector (2D, ignore Z for heading)
    local dx = target_pos.x - player_pos.x
    local dy = target_pos.y - player_pos.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return nil end

    dx = dx / len
    dy = dy / len

    -- Raise origin slightly above ground to avoid ground-level false hits
    local origin = {
        x = player_pos.x,
        y = player_pos.y,
        z = player_pos.z + cfg.probe_height_offset,
    }

    -- Build ray directions: center, left, right
    local spread_rad = math.rad(cfg.probe_spread_deg)
    local cos_s = math.cos(spread_rad)
    local sin_s = math.sin(spread_rad)

    local directions = {
        { dx = dx, dy = dy },                                      -- center
        { dx = dx * cos_s - dy * sin_s, dy = dx * sin_s + dy * cos_s }, -- left
        { dx = dx * cos_s + dy * sin_s, dy = -dx * sin_s + dy * cos_s }, -- right
    }

    local probe_dist = cfg.probe_distance

    for _, dir in ipairs(directions) do
        local probe_end = {
            x = origin.x + dir.dx * probe_dist,
            y = origin.y + dir.dy * probe_dist,
            z = origin.z,
        }

        -- trace_line returns true = clear, false = blocked
        local ok, result = pcall(core.graphics.trace_line, origin, probe_end, flags)
        if ok and result == false then
            -- Hit! Return approximate midpoint as the obstacle center
            local hit_pos = {
                x = origin.x + dir.dx * (probe_dist * 0.5),
                y = origin.y + dir.dy * (probe_dist * 0.5),
                z = player_pos.z,
            }
            core.log("[Obstacle] Probe hit (DoodadCollision) at ~"
                .. string.format("%.1f, %.1f, %.1f", hit_pos.x, hit_pos.y, hit_pos.z))
            return hit_pos
        end
    end

    return nil
end

-- Proactive Path Look-Ahead ----------------------------------------------

---Probe along a single waypoint segment A→B for doodad collisions.
---Traces center ray + two spread rays, all raised above ground.
---@param pos_a vec3|table Start of segment
---@param pos_b vec3|table End of segment
---@return table|nil hit_pos Approximate obstacle center { x, y, z }, or nil if clear
function Obstacle:probe_segment(pos_a, pos_b)
    local cfg = self._config
    local flags = cfg.collision_flags
    local h = cfg.lookahead_height_offset

    -- Raised endpoints
    local origin = { x = pos_a.x, y = pos_a.y, z = pos_a.z + h }
    local target = { x = pos_b.x, y = pos_b.y, z = pos_b.z + h }

    -- Center ray: A → B
    local ok, result = pcall(core.graphics.trace_line, origin, target, flags)
    if ok and result == false then
        return {
            x = (pos_a.x + pos_b.x) * 0.5,
            y = (pos_a.y + pos_b.y) * 0.5,
            z = (pos_a.z + pos_b.z) * 0.5,
        }
    end

    -- Side rays: spread from segment direction
    local dx = pos_b.x - pos_a.x
    local dy = pos_b.y - pos_a.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return nil end

    dx = dx / len
    dy = dy / len

    local spread_rad = math.rad(cfg.lookahead_spread_deg)
    local cos_s = math.cos(spread_rad)
    local sin_s = math.sin(spread_rad)

    local side_dirs = {
        { dx = dx * cos_s - dy * sin_s, dy = dx * sin_s + dy * cos_s },  -- left
        { dx = dx * cos_s + dy * sin_s, dy = -dx * sin_s + dy * cos_s }, -- right
    }

    for _, dir in ipairs(side_dirs) do
        local side_target = {
            x = origin.x + dir.dx * len,
            y = origin.y + dir.dy * len,
            z = target.z,
        }
        local ok2, result2 = pcall(core.graphics.trace_line, origin, side_target, flags)
        if ok2 and result2 == false then
            return {
                x = (pos_a.x + pos_b.x) * 0.5,
                y = (pos_a.y + pos_b.y) * 0.5,
                z = (pos_a.z + pos_b.z) * 0.5,
            }
        end
    end

    return nil
end

---Probe upcoming waypoint segments for obstacles.
---@param waypoints vec3[] Remaining waypoints from simple_movement
---@param max_segments? number How many segments to probe (default: config value)
---@return table|nil hit_pos First obstacle found, or nil if path is clear
---@return number|nil segment_index Which segment (1-based) had the hit
function Obstacle:probe_path_ahead(waypoints, max_segments)
    if not waypoints or #waypoints < 2 then return nil, nil end

    local n = math.min(
        max_segments or self._config.lookahead_segments,
        #waypoints - 1
    )

    for i = 1, n do
        local hit = self:probe_segment(waypoints[i], waypoints[i + 1])
        if hit then
            return hit, i
        end
    end

    return nil, nil
end

-- Zone Memory ------------------------------------------------------------

---Add an avoidance zone at the given position
---@param pos table { x, y, z } Hit position from probe
---@param radius? number Override avoidance radius
function Obstacle:add_zone(pos, radius)
    local cfg = self._config
    radius = radius or cfg.avoidance_radius

    -- Deduplicate: don't add if within radius of an existing zone
    for _, zone in ipairs(self._zones) do
        local dx = zone.x - pos.x
        local dy = zone.y - pos.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < radius then
            core.log("[Obstacle] Zone already exists near "
                .. string.format("%.1f, %.1f", pos.x, pos.y) .. ", skipping")
            return
        end
    end

    self._zones[#self._zones + 1] = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        radius = radius,
        cost = cfg.avoidance_cost,
        created = core.time(),
    }

    core.log("[Obstacle] Added avoidance zone at "
        .. string.format("%.1f, %.1f, %.1f", pos.x, pos.y, pos.z)
        .. " (r=" .. string.format("%.1f", radius) .. ")")

    -- Enforce cap: evict oldest first
    while #self._zones > cfg.max_zones do
        local removed = table.remove(self._zones, 1)
        core.log("[Obstacle] Evicted oldest zone at "
            .. string.format("%.1f, %.1f", removed.x, removed.y))
    end
end

---Prune expired or distant zones. Call periodically (e.g. on repath).
---@param player_pos? vec3 Current player position for distance pruning
function Obstacle:prune(player_pos)
    local cfg = self._config
    local now = core.time()
    local kept = {}

    for _, zone in ipairs(self._zones) do
        local age = now - zone.created
        local dominated_by_time = age > cfg.zone_ttl

        local dominated_by_dist = false
        if player_pos then
            local dx = zone.x - player_pos.x
            local dy = zone.y - player_pos.y
            local dist = math.sqrt(dx * dx + dy * dy)
            dominated_by_dist = dist > cfg.zone_prune_dist
        end

        if not dominated_by_time and not dominated_by_dist then
            kept[#kept + 1] = zone
        end
    end

    local pruned = #self._zones - #kept
    if pruned > 0 then
        core.log("[Obstacle] Pruned " .. pruned .. " expired/distant zones")
    end
    self._zones = kept
end

-- Query API (consumed by MovementModule) ---------------------------------

---Get avoidance zones for NavBuddy /path-avoid endpoint
---@return table[] Array of { x, y, z, radius, cost }
function Obstacle:get_avoidance_zones()
    return self._zones
end

---Get count of active zones
---@return number
function Obstacle:get_zone_count()
    return #self._zones
end

---No-op update for compatibility with BotManager's module update loop.
---Proactive probing is driven by MovementModule._check_proactive_obstacles().
---Reactive probing is driven by MovementModule._unstuck_probe_and_repath().
function Obstacle:update()
end

return Obstacle
