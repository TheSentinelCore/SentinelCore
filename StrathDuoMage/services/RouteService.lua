local RouteService = {}
RouteService.__index = RouteService

local function safe_method(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(obj[method], obj, ...)
    if ok then
        return value
    end
    return nil
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
    local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
    local dz = (tonumber(a.z) or 0) - (tonumber(b.z) or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function copy_pos(pos)
    if type(pos) ~= "table" then
        return nil
    end
    local x = tonumber(pos.x)
    local y = tonumber(pos.y)
    local z = tonumber(pos.z)
    if not x or not y or not z then
        return nil
    end
    return { x = x, y = y, z = z }
end

local function midpoint(a, b)
    local pa = copy_pos(a)
    local pb = copy_pos(b)
    if not pa or not pb then
        return nil
    end
    return {
        x = (pa.x + pb.x) * 0.5,
        y = (pa.y + pb.y) * 0.5,
        z = (pa.z + pb.z) * 0.5,
    }
end

local function project_point_to_segment(p, a, b, clamp_t)
    local pp = copy_pos(p)
    local pa = copy_pos(a)
    local pb = copy_pos(b)
    if not pp or not pa or not pb then
        return nil
    end

    local abx = pb.x - pa.x
    local aby = pb.y - pa.y
    local abz = pb.z - pa.z
    local den = (abx * abx) + (aby * aby) + (abz * abz)
    if den <= 0.0001 then
        return copy_pos(pa)
    end

    local apx = pp.x - pa.x
    local apy = pp.y - pa.y
    local apz = pp.z - pa.z
    local t = ((apx * abx) + (apy * aby) + (apz * abz)) / den
    if clamp_t then
        if t < 0 then
            t = 0
        elseif t > 1 then
            t = 1
        end
    end

    return {
        x = pa.x + (abx * t),
        y = pa.y + (aby * t),
        z = pa.z + (abz * t),
    }
end

local function lerp(a, b, alpha)
    local pa = copy_pos(a)
    local pb = copy_pos(b)
    if not pa then
        return copy_pos(pb)
    end
    if not pb then
        return copy_pos(pa)
    end
    local t = tonumber(alpha) or 0.35
    if t < 0 then
        t = 0
    elseif t > 1 then
        t = 1
    end
    return {
        x = pa.x + (pb.x - pa.x) * t,
        y = pa.y + (pb.y - pa.y) * t,
        z = pa.z + (pb.z - pa.z) * t,
    }
end

---@class RouteService
function RouteService:new(bb, cfg, movement, logger)
    local o = setmetatable({}, RouteService)
    o._bb = bb
    o._cfg = cfg or {}
    o._movement = movement
    o._log = logger
    o._segment_index = 1
    o._pull_index = 1
    o._collecting = false
    o._initialized = false
    o._collect_started_at = 0
    o._point_entered_at = 0
    o._anchor_prev = nil
    return o
end

function RouteService:_route_cfg()
    return self._cfg.route or {}
end

function RouteService:_segments()
    local route = self:_route_cfg()
    local segments = route.segments
    if type(segments) == "table" then
        return segments
    end
    return {}
end

function RouteService:_active_segment()
    local segments = self:_segments()
    if #segments == 0 then
        return nil, 0
    end

    if self._segment_index < 1 then
        self._segment_index = 1
    end
    if self._segment_index > #segments then
        self._segment_index = #segments
    end

    return segments[self._segment_index], #segments
end

function RouteService:_segment_pull_points(segment)
    if type(segment) ~= "table" then
        return {}
    end
    if type(segment.pull_points) == "table" and #segment.pull_points > 0 then
        return segment.pull_points
    end
    if type(segment.pull_point) == "table" then
        return { segment.pull_point }
    end
    return {}
end

function RouteService:get_current_pull_point()
    local segment = self:_active_segment()
    local points = self:_segment_pull_points(segment)
    if #points == 0 then
        return nil, 0, 0
    end

    if self._pull_index < 1 then
        self._pull_index = 1
    end
    if self._pull_index > #points then
        self._pull_index = #points
    end

    return points[self._pull_index], self._pull_index, #points
end

function RouteService:get_active_segment()
    local segment = self:_active_segment()
    return segment
end

function RouteService:is_collecting()
    return self._collecting == true
end

function RouteService:get_reach_tolerance()
    local route = self:_route_cfg()
    return tonumber(route.point_reach_tolerance) or 2.0
end

function RouteService:start_collection(now, force_reset)
    if self._collecting and not force_reset then
        return
    end
    self._collecting = true
    self._initialized = true
    self._pull_index = 1
    self._collect_started_at = tonumber(now) or 0
    self._point_entered_at = tonumber(now) or 0
    self._bb:set("route.collecting", true)
    self._bb:set("route.collect_complete", false)
end

function RouteService:ensure_started(now)
    if self._initialized then
        return
    end
    local _, total = self:_active_segment()
    if total <= 0 then
        return
    end
    self:start_collection(now, true)
end

function RouteService:finish_collection(now)
    self._collecting = false
    self._bb:set("route.collecting", false)
    self._bb:set("route.collect_complete", true)
    self._bb:set("route.collect_finished_at", tonumber(now) or 0)
end

function RouteService:advance_pull_point(now)
    local _, idx, total = self:get_current_pull_point()
    if idx <= 0 or total <= 0 then
        return false
    end

    self._pull_index = idx + 1
    self._point_entered_at = tonumber(now) or 0

    if self._pull_index > total then
        self._bb:set("route.points_exhausted", true)
        return false
    end

    self._bb:set("route.points_exhausted", false)
    return true
end

function RouteService:should_skip_current_point(now)
    local timeout = tonumber(self:_route_cfg().point_timeout_secs) or 4.0
    if timeout <= 0 then
        return false
    end

    local entered = tonumber(self._point_entered_at) or 0
    local cur = tonumber(now) or 0
    if entered <= 0 then
        self._point_entered_at = cur
        return false
    end

    return (cur - entered) >= timeout
end

function RouteService:is_collect_complete(now)
    if not self._collecting then
        return self._bb:get("route.collect_complete", false) == true
    end

    local route = self:_route_cfg()
    local min_enemy = tonumber(route.min_enemy_count_for_aoe) or 8
    local timeout = tonumber(route.collect_timeout_secs) or 18.0
    local enemy_count = tonumber(self._bb:get("combat.enemy_count", 0)) or 0
    local elapsed = (tonumber(now) or 0) - (tonumber(self._collect_started_at) or 0)
    local _, idx, total = self:get_current_pull_point()
    local points_done = total > 0 and idx >= total and self._bb:get("route.points_exhausted", false) == true

    local complete = enemy_count >= min_enemy or (timeout > 0 and elapsed >= timeout) or points_done
    self._bb:set("route.collect_complete", complete)
    return complete
end

function RouteService:next_segment(now)
    local _, total = self:_active_segment()
    if total <= 0 then
        return false
    end

    local loop = self:_route_cfg().loop ~= false
    self._segment_index = self._segment_index + 1
    if self._segment_index > total then
        if loop then
            self._segment_index = 1
        else
            self._segment_index = total
        end
    end

    self._pull_index = 1
    self._anchor_prev = nil
    self:start_collection(now, true)
    self._bb:set("route.segment_index", self._segment_index)
    self._bb:set("route.segment_changed_at", tonumber(now) or 0)
    self._bb:set("route.points_exhausted", false)
    return true
end

function RouteService:_visible_enemy_positions(max_radius)
    local player = self._bb:get("player.object")
    local player_pos = self._bb:get("player.position")
    if not player or not player_pos then
        return {}
    end

    local positions = {}
    if not (core and core.object_manager and core.object_manager.get_visible_objects) then
        return positions
    end

    local ok, objects = pcall(core.object_manager.get_visible_objects)
    if not ok or type(objects) ~= "table" then
        return positions
    end

    local radius = tonumber(max_radius) or 40.0
    local focus_pos = copy_pos(self._bb:get("route.target_focus_position"))
    local focus_radius = tonumber(self._bb:get("route.target_focus_radius", radius)) or radius

    for i = 1, #objects do
        local unit = objects[i]
        if unit
            and safe_method(unit, "is_valid") == true
            and safe_method(unit, "is_dead") ~= true
            and safe_method(unit, "is_unit") == true
            and safe_method(unit, "is_basic_object") ~= true
            and safe_method(player, "can_attack", unit) == true then
            local pos = copy_pos(safe_method(unit, "get_position"))
            if pos and distance(player_pos, pos) <= radius then
                if not focus_pos or distance(pos, focus_pos) <= focus_radius then
                    positions[#positions + 1] = pos
                end
            end
        end
    end

    return positions
end

function RouteService:_centroid(positions)
    if type(positions) ~= "table" or #positions == 0 then
        return nil
    end

    local sx, sy, sz = 0, 0, 0
    for i = 1, #positions do
        local p = positions[i]
        sx = sx + (tonumber(p.x) or 0)
        sy = sy + (tonumber(p.y) or 0)
        sz = sz + (tonumber(p.z) or 0)
    end

    local n = #positions
    return { x = sx / n, y = sy / n, z = sz / n }
end

function RouteService:_apply_lead(anchor, lead_distance)
    local pos = copy_pos(anchor)
    local lead = tonumber(lead_distance) or 0
    if not pos or math.abs(lead) < 0.001 then
        return pos
    end

    local player_pos = copy_pos(self._bb:get("player.position"))
    if not player_pos then
        return pos
    end

    local dx = player_pos.x - pos.x
    local dy = player_pos.y - pos.y
    local dz = player_pos.z - pos.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then
        return pos
    end

    return {
        x = pos.x + (dx / len) * lead,
        y = pos.y + (dy / len) * lead,
        z = pos.z + (dz / len) * lead,
    }
end

function RouteService:_compute_blizzard_anchor()
    local segment = self:get_active_segment()
    local route = self:_route_cfg()
    local blizzard_cfg = (type(segment) == "table" and type(segment.blizzard) == "table") and segment.blizzard or {}

    local scan_radius = tonumber(blizzard_cfg.scan_radius) or tonumber(route.blizzard_scan_radius) or 40.0
    local strategy = tostring(blizzard_cfg.strategy or route.blizzard_strategy or "cluster_centroid")
    local lane_start = copy_pos(blizzard_cfg.lane_start)
    local lane_end = copy_pos(blizzard_cfg.lane_end)
    local clamp_to_lane = blizzard_cfg.clamp_to_lane
    if clamp_to_lane == nil then
        clamp_to_lane = route.clamp_blizzard_to_lane ~= false
    end

    local enemies = self:_visible_enemy_positions(scan_radius)
    local centroid = self:_centroid(enemies)
    local anchor = nil

    if strategy == "lane_midpoint" and lane_start and lane_end then
        anchor = midpoint(lane_start, lane_end)
    else
        anchor = copy_pos(centroid)
        if not anchor and type(segment) == "table" then
            anchor = copy_pos(segment.gather_anchor)
        end
    end

    if anchor and lane_start and lane_end and clamp_to_lane then
        anchor = project_point_to_segment(anchor, lane_start, lane_end, true)
    end

    local lead = tonumber(blizzard_cfg.lead_distance) or tonumber(route.blizzard_lead_distance) or 0
    anchor = self:_apply_lead(anchor, lead)

    local alpha = tonumber(blizzard_cfg.smoothing_alpha) or tonumber(route.blizzard_smoothing_alpha) or 0.35
    if self._anchor_prev and anchor then
        anchor = lerp(self._anchor_prev, anchor, alpha)
    end

    if anchor then
        self._anchor_prev = copy_pos(anchor)
    end

    return anchor
end

function RouteService:_publish_focus()
    local segment = self:get_active_segment()
    local point = self:get_current_pull_point()
    local focus = nil
    local radius = nil

    if type(point) == "table" then
        if type(point.focus) == "table" then
            focus = copy_pos(point.focus)
        else
            focus = copy_pos(point)
        end
        radius = tonumber(point.focus_radius)
    end

    if not focus and type(segment) == "table" then
        focus = copy_pos(segment.gather_anchor)
    end

    if not radius and type(segment) == "table" then
        radius = tonumber(segment.focus_radius)
    end
    if not radius then
        radius = tonumber(self:_route_cfg().default_focus_radius) or 18.0
    end

    self._bb:set("route.target_focus_position", focus)
    self._bb:set("route.target_focus_radius", radius)
end

---@param now number
function RouteService:update(now)
    local segment, total_segments = self:_active_segment()
    if total_segments <= 0 then
        self._collecting = false
        self._initialized = false
        self._bb:set("route.segment_index", 0)
        self._bb:set("route.pull_index", 0)
        self._bb:set("route.collecting", false)
        self._bb:set("route.collect_complete", false)
        self._bb:set("route.pull_point", nil)
        self._bb:set("route.target_focus_position", nil)
        self._bb:set("combat.blizzard_anchor", nil)
        return
    end

    local point, idx = self:get_current_pull_point()
    self._bb:set("route.segment_index", self._segment_index)
    self._bb:set("route.segment", segment)
    self._bb:set("route.pull_index", idx or 0)
    self._bb:set("route.pull_point", point)
    self._bb:set("route.collecting", self._collecting == true)

    self:_publish_focus()

    local anchor = self:_compute_blizzard_anchor()
    self._bb:set("combat.blizzard_anchor", anchor)
end

return RouteService
