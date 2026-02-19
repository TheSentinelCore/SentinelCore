---@class ObstacleService
---Obstacle detection and avoidance zone management.
---Probes for doodad collisions via raycast and maintains a FIFO zone list.
local ObstacleService = {}
ObstacleService.__index = ObstacleService

local Defaults = require("core.Defaults")
local Events = require("events.Events")

local DEFAULT_CONFIG = Defaults.flat(Defaults.obstacles)
DEFAULT_CONFIG.collision_flags = 0x00000001  -- DoodadCollision

local DEG_TO_RAD = math.pi / 180

--------------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------------

---@param event_bus table EventBus instance
---@param blackboard table Blackboard instance
---@param config? table Optional config overrides
---@return ObstacleService
function ObstacleService:new(event_bus, blackboard, config)
    local o = setmetatable({}, self)
    o._event_bus = event_bus
    o._bb = blackboard

    -- Build config from defaults + overrides
    o._config = {}
    for k, v in pairs(DEFAULT_CONFIG) do o._config[k] = v end
    if config then
        for k, v in pairs(config) do o._config[k] = v end
    end

    -- Zone storage
    o._zones = {}

    return o
end

--------------------------------------------------------------------------------
-- Probing
--------------------------------------------------------------------------------

---Rotate a 2D direction vector by angle (radians)
---@param dx number
---@param dy number
---@param angle number Radians
---@return number, number Rotated dx, dy
local function rotate_2d(dx, dy, angle)
    local cos_a = math.cos(angle)
    local sin_a = math.sin(angle)
    return dx * cos_a - dy * sin_a, dx * sin_a + dy * cos_a
end

---Probe forward from player toward target with 3-ray spread.
---Returns approximate hit position or nil if clear.
---@param player_pos table {x, y, z}
---@param target_pos table {x, y, z}
---@return table|nil hit_pos Approximate hit position
function ObstacleService:probe_forward(player_pos, target_pos)
    local cfg = self._config

    -- 2D direction to target
    local dx = target_pos.x - player_pos.x
    local dy = target_pos.y - player_pos.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return nil end

    -- Normalize
    dx, dy = dx / len, dy / len

    -- Raised origin
    local origin = {
        x = player_pos.x,
        y = player_pos.y,
        z = player_pos.z + cfg.probe_height_offset,
    }

    local spread_rad = cfg.probe_spread_deg * DEG_TO_RAD
    local dist = cfg.probe_distance
    local flags = cfg.collision_flags

    -- 3 rays: center, left, right
    local directions = {
        { dx, dy },  -- center
        { rotate_2d(dx, dy, -spread_rad) },  -- left
        { rotate_2d(dx, dy, spread_rad) },   -- right
    }

    for _, dir in ipairs(directions) do
        local probe_end = {
            x = origin.x + dir[1] * dist,
            y = origin.y + dir[2] * dist,
            z = origin.z,
        }

        local ok, result = pcall(core.graphics.trace_line, origin, probe_end, flags)
        if ok and result == false then
            -- Hit! Return approximate midpoint
            local hit_pos = {
                x = origin.x + dir[1] * (dist * 0.5),
                y = origin.y + dir[2] * (dist * 0.5),
                z = player_pos.z,
            }
            return hit_pos
        end
    end

    return nil  -- All clear
end

---Probe a single path segment (A to B) with 3-ray spread.
---Returns hit info or nil if clear.
---@param pos_a table {x, y, z} Segment start
---@param pos_b table {x, y, z} Segment end
---@return table|nil hit_info {x, y, z} hit position
function ObstacleService:probe_segment(pos_a, pos_b)
    local cfg = self._config
    local h_off = cfg.lookahead_height_offset
    local flags = cfg.collision_flags

    -- Raise both points
    local a = { x = pos_a.x, y = pos_a.y, z = pos_a.z + h_off }
    local b = { x = pos_b.x, y = pos_b.y, z = pos_b.z + h_off }

    -- Center ray: A -> B
    local ok, result = pcall(core.graphics.trace_line, a, b, flags)
    if ok and result == false then
        -- Hit on center ray
        return {
            x = (pos_a.x + pos_b.x) * 0.5,
            y = (pos_a.y + pos_b.y) * 0.5,
            z = (pos_a.z + pos_b.z) * 0.5,
        }
    end

    -- Side rays (only if segment long enough)
    local dx = pos_b.x - pos_a.x
    local dy = pos_b.y - pos_a.y
    local seg_len = math.sqrt(dx * dx + dy * dy)
    if seg_len < 0.5 then return nil end

    -- Normalize direction
    local ndx, ndy = dx / seg_len, dy / seg_len
    local spread_rad = cfg.lookahead_spread_deg * DEG_TO_RAD

    local side_dirs = {
        { rotate_2d(ndx, ndy, -spread_rad) },
        { rotate_2d(ndx, ndy, spread_rad) },
    }

    for _, dir in ipairs(side_dirs) do
        local side_end = {
            x = a.x + dir[1] * seg_len,
            y = a.y + dir[2] * seg_len,
            z = a.z,
        }
        local ok2, result2 = pcall(core.graphics.trace_line, a, side_end, flags)
        if ok2 and result2 == false then
            return {
                x = (pos_a.x + pos_b.x) * 0.5,
                y = (pos_a.y + pos_b.y) * 0.5,
                z = (pos_a.z + pos_b.z) * 0.5,
            }
        end
    end

    return nil  -- All clear
end

---Probe multiple path segments ahead for obstacles.
---Returns first hit and segment index, or nil.
---@param waypoints table[] Array of {x, y, z} waypoints
---@param max_segments? number Max segments to check (default from config)
---@return table|nil hit_pos
---@return number|nil segment_index 1-based segment index where hit occurred
function ObstacleService:probe_path_ahead(waypoints, max_segments)
    if not waypoints or #waypoints < 2 then return nil, nil end

    local cfg = self._config
    local n = math.min(max_segments or cfg.lookahead_segments, #waypoints - 1)

    for i = 1, n do
        local hit = self:probe_segment(waypoints[i], waypoints[i + 1])
        if hit then
            return hit, i
        end
    end

    return nil, nil
end

--------------------------------------------------------------------------------
-- Zone Management
--------------------------------------------------------------------------------

---Add an avoidance zone at position. Deduplicates by distance.
---@param pos table {x, y, z}
---@param radius? number Override radius (default from config)
function ObstacleService:add_zone(pos, radius)
    local cfg = self._config
    local r = radius or cfg.avoidance_radius

    -- Dedup: check if too close to existing zone
    for _, zone in ipairs(self._zones) do
        local dist = math.sqrt(
            (zone.x - pos.x) * (zone.x - pos.x) +
            (zone.y - pos.y) * (zone.y - pos.y)
        )
        if dist < r then
            return  -- Already covered
        end
    end

    -- Create zone
    local zone = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        radius = r,
        cost = cfg.avoidance_cost,
        created = core and core.time and core.time() or os.time(),
    }
    self._zones[#self._zones + 1] = zone

    -- Update blackboard
    self._bb:set("obstacles.zones", self._zones)
    self._bb:set("obstacles.last_hit", pos)

    -- Emit event
    self._event_bus:emit(Events.OBSTACLE_DETECTED, {
        position = pos,
        radius = r,
        zone_count = #self._zones,
    })

    -- FIFO eviction if over max
    while #self._zones > cfg.max_zones do
        table.remove(self._zones, 1)  -- Remove oldest
    end

    -- Update blackboard after possible eviction
    self._bb:set("obstacles.zones", self._zones)
end

---Remove a zone by index
---@param index number 1-based index
function ObstacleService:remove_zone(index)
    if index >= 1 and index <= #self._zones then
        table.remove(self._zones, index)
        self._bb:set("obstacles.zones", self._zones)
    end
end

---Prune zones by TTL and distance from player
---@param player_pos? table {x, y, z} If provided, also prune by distance
function ObstacleService:prune(player_pos)
    local cfg = self._config
    local now = core and core.time and core.time() or os.time()
    local kept = {}

    for _, zone in ipairs(self._zones) do
        local age = now - zone.created
        local expired = age > cfg.zone_ttl

        local too_far = false
        if player_pos then
            local dist = math.sqrt(
                (zone.x - player_pos.x) * (zone.x - player_pos.x) +
                (zone.y - player_pos.y) * (zone.y - player_pos.y)
            )
            too_far = dist > cfg.zone_prune_dist
        end

        if not expired and not too_far then
            kept[#kept + 1] = zone
        end
    end

    self._zones = kept
    self._bb:set("obstacles.zones", self._zones)
end

---Get all current avoidance zones
---@return table[] Array of zone tables
function ObstacleService:get_avoidance_zones()
    return self._zones
end

---Get count of active zones
---@return number
function ObstacleService:get_zone_count()
    return #self._zones
end

---Clear all zones
function ObstacleService:clear()
    self._zones = {}
    self._bb:set("obstacles.zones", self._zones)
    self._bb:clear("obstacles.last_hit")
end

---Update config at runtime
---@param overrides table
function ObstacleService:update_config(overrides)
    if not overrides then return end
    for k, v in pairs(overrides) do
        self._config[k] = v
    end
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

function ObstacleService:_test()
    local EventBus = require("events.EventBus")
    local Blackboard = require("core.Blackboard")
    local results = {}

    -- Test 1: Construction
    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local svc = ObstacleService:new(bus, bb)
    results["construction"] = (svc ~= nil and svc._config.avoidance_radius == 3.0)

    -- Test 2: Add zone
    svc:add_zone({ x = 100, y = 200, z = 50 })
    results["add_zone"] = (svc:get_zone_count() == 1)
    results["zone_in_bb"] = (bb:get("obstacles.zones") ~= nil and #bb:get("obstacles.zones") == 1)

    -- Test 3: Dedup (same position)
    svc:add_zone({ x = 100.5, y = 200.5, z = 50 })  -- Within radius
    results["dedup"] = (svc:get_zone_count() == 1)

    -- Test 4: Different position (far enough)
    svc:add_zone({ x = 200, y = 300, z = 50 })
    results["different_zone"] = (svc:get_zone_count() == 2)

    -- Test 5: Event emitted
    local event_received = false
    bus:on(Events.OBSTACLE_DETECTED, function(data)
        event_received = true
    end)
    svc:add_zone({ x = 500, y = 500, z = 50 })
    results["event_emitted"] = event_received

    -- Test 6: FIFO eviction (max_zones = 5)
    svc:clear()
    for i = 1, 7 do
        svc:add_zone({ x = i * 100, y = i * 100, z = 0 })
    end
    results["fifo_eviction"] = (svc:get_zone_count() == 5)

    -- Test 7: Clear
    svc:clear()
    results["clear"] = (svc:get_zone_count() == 0)

    -- Test 8: Prune by TTL (mock time by setting created in the past)
    svc:add_zone({ x = 10, y = 10, z = 0 })
    svc._zones[1].created = (core and core.time and core.time() or os.time()) - 999
    svc:prune()
    results["prune_ttl"] = (svc:get_zone_count() == 0)

    -- Test 9: Config override
    svc = ObstacleService:new(bus, bb, { avoidance_radius = 5.0 })
    results["config_override"] = (svc._config.avoidance_radius == 5.0)

    -- Test 10: Runtime config update
    svc:update_config({ max_zones = 10 })
    results["runtime_config"] = (svc._config.max_zones == 10)

    return results
end

return ObstacleService
