---@class PathValidationService
---Path validity checking and deviation detection.
---Extracted from Movement.lua's _check_path_validity() and _check_deviation() logic.
local PathValidationService = {}
PathValidationService.__index = PathValidationService

local Defaults = require("core/Defaults")
local Helpers = require("lib/Helpers")

-- Lateral deviation should be measured in XY only; Z is handled separately.
local function point_to_segment_distance_2d(px, py, ax, ay, bx, by)
    local abx, aby = bx - ax, by - ay
    local apx, apy = px - ax, py - ay
    local ab_sq = abx * abx + aby * aby

    if ab_sq < 1e-8 then
        local dx, dy = px - ax, py - ay
        return math.sqrt(dx * dx + dy * dy), 0
    end

    local t = (apx * abx + apy * aby) / ab_sq
    t = Helpers.clamp(t, 0, 1)

    local cx, cy = ax + t * abx, ay + t * aby
    local dx, dy = px - cx, py - cy
    return math.sqrt(dx * dx + dy * dy), t
end

local function find_best_segment_2d(current_pos, path_waypoints, seg_start, seg_end)
    local best_dist = math.huge
    local best_t = 0
    local best_seg = 0

    for i = seg_start, seg_end do
        local a = path_waypoints[i]
        local b = path_waypoints[i + 1]
        local dist, t = point_to_segment_distance_2d(
            current_pos.x, current_pos.y,
            a.x, a.y,
            b.x, b.y
        )
        if dist < best_dist then
            best_dist = dist
            best_t = t
            best_seg = i
        end
    end

    return best_dist, best_t, best_seg
end

local function invoke_callback(callback, valid, first_invalid_segment)
    if not callback then
        return
    end
    local ok, err = pcall(callback, valid, first_invalid_segment)
    if not ok and core and core.log_error then
        core.log_error("[PathValidationService] Callback error: " .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------------

---@param blackboard table Blackboard instance
---@param config? table Optional config overrides
---@return PathValidationService
function PathValidationService:new(blackboard, config)
    local o = setmetatable({}, self)
    o._bb = blackboard

    -- Load defaults
    local defaults = Defaults.flat(Defaults.movement)
    o._config = {}
    for k, v in pairs(defaults) do o._config[k] = v end
    if config then
        for k, v in pairs(config) do o._config[k] = v end
    end

    return o
end

--------------------------------------------------------------------------------
-- Path Validity Check
--------------------------------------------------------------------------------

---Downsample a waypoint list to approximately `target_count` evenly-spaced samples.
---Always includes first and last waypoint.
---@param waypoints table[] Array of {x, y, z}
---@param target_count? number Target sample count (default 10)
---@return table[] Downsampled waypoints
function PathValidationService:_downsample(waypoints, target_count)
    target_count = target_count or 10
    local n = #waypoints

    if n <= target_count then
        return waypoints  -- No need to downsample
    end

    local sample = {}
    sample[1] = waypoints[1]  -- Always include first

    -- Distribute (target_count - 2) intermediate samples
    local inner_count = target_count - 2
    local stride = (n - 1) / (inner_count + 1)

    for i = 1, inner_count do
        local idx = math.floor(1 + i * stride + 0.5)
        idx = Helpers.clamp(idx, 2, n - 1)
        sample[#sample + 1] = waypoints[idx]
    end

    sample[#sample + 1] = waypoints[n]  -- Always include last

    return sample
end

---Async check if a path is still valid on the navmesh.
---Downsamples to ~10 waypoints, calls nav_service:check_path().
---@param nav_service table NavigationService instance
---@param current_pos table {x, y, z} Player position
---@param remaining_waypoints table[] Remaining path waypoints
---@param callback function callback(valid: boolean, first_invalid_segment: number|nil)
function PathValidationService:check_path_validity(nav_service, current_pos, remaining_waypoints, callback)
    if not remaining_waypoints or #remaining_waypoints < 3 then
        invoke_callback(callback, true, nil)  -- Too few waypoints to validate
        return
    end

    -- Downsample to avoid false positives from dense Chaikin-smoothed paths
    local sample = self:_downsample(remaining_waypoints, 10)

    nav_service:check_path(current_pos, sample, function(success, data, err)
        if not success then
            invoke_callback(callback, true, nil)  -- Can't validate, assume OK
            return
        end
        invoke_callback(callback, data.valid ~= false, data.first_invalid_segment)
    end)
end

--------------------------------------------------------------------------------
-- Deviation Detection
--------------------------------------------------------------------------------

---Check if the player has deviated from the path.
---Uses closest-segment search with corridor-adaptive thresholds.
---@param current_pos table {x, y, z} Player position
---@param path_waypoints table[] Full path waypoints
---@param path_index number Current waypoint index (1-based)
---@param corridor_widths? table Corridor width per waypoint
---@return table result { deviated: boolean, drift: number, vertical_drift: number, threshold: number, segment_index: number }
function PathValidationService:check_deviation(current_pos, path_waypoints, path_index, corridor_widths)
    local cfg = self._config
    local result = {
        deviated = false,
        drift = 0,
        vertical_drift = 0,
        threshold = cfg.deviation_threshold or 2.0,
        segment_index = 0,
    }

    if not current_pos or not path_waypoints then return result end
    if #path_waypoints == 0 then return result end

    -- Degenerate path (single waypoint): still support wrong-floor detection
    -- when player is under/over the target column.
    if #path_waypoints == 1 then
        local wp = path_waypoints[1]
        local lateral = Helpers.distance_2d(current_pos, wp)
        local vertical = math.abs((current_pos.z or 0) - (wp.z or 0))
        local vert_threshold = cfg.deviation_vertical_threshold or 2.0
        local lat_gate = math.max((cfg.deviation_threshold or 2.0) * 1.5, 3.0)

        result.drift = lateral
        result.vertical_drift = vertical
        result.threshold = vert_threshold

        if vertical > vert_threshold and lateral <= lat_gate then
            result.deviated = true
        end
        return result
    end

    if path_index > #path_waypoints then return result end

    -- Robust segment matching:
    -- 1) search a local window around path_index (back + forward),
    -- 2) if local match is still far, fall back to full-path search.
    local last_segment = #path_waypoints - 1
    local idx = Helpers.clamp(path_index or 1, 1, #path_waypoints)
    local back_window = 60
    local forward_window = 120

    local search_start = math.max(1, idx - back_window)
    local search_end = math.min(last_segment, idx + forward_window)
    local best_dist, best_t, best_seg = find_best_segment_2d(
        current_pos,
        path_waypoints,
        search_start,
        search_end
    )

    local fallback_threshold = math.max((cfg.deviation_threshold or 2.0) * 2.5, 6.0)
    if best_seg == 0 or best_dist > fallback_threshold then
        best_dist, best_t, best_seg = find_best_segment_2d(
            current_pos,
            path_waypoints,
            1,
            last_segment
        )
        if best_seg == 0 then
            return result
        end
    end

    result.drift = best_dist
    result.segment_index = best_seg

    -- Check 1: Vertical deviation (wrong floor detection)
    local a = path_waypoints[best_seg]
    local b = path_waypoints[best_seg + 1]
    local expected_z = a.z + best_t * (b.z - a.z)
    local vertical_drift = math.abs(current_pos.z - expected_z)
    result.vertical_drift = vertical_drift

    local vert_threshold = cfg.deviation_vertical_threshold or 2.0
    if vertical_drift > vert_threshold then
        result.deviated = true
        result.threshold = vert_threshold
        return result
    end

    -- Wrong-floor near destination: if we are already under/over destination XY
    -- column with a large Z gap, trigger deviation even if segment projection is
    -- locally ambiguous.
    local destination = path_waypoints[#path_waypoints]
    if destination then
        local dest_lateral = Helpers.distance_2d(current_pos, destination)
        local dest_lateral_gate = cfg.deviation_destination_lateral_gate
            or math.max((cfg.deviation_threshold or 2.0) * 2.0, 4.0)
        local dest_vertical_drift = math.abs((current_pos.z or 0) - (destination.z or 0))

        if dest_lateral <= dest_lateral_gate and dest_vertical_drift > vert_threshold then
            result.deviated = true
            result.threshold = vert_threshold
            if dest_vertical_drift > result.vertical_drift then
                result.vertical_drift = dest_vertical_drift
            end
            return result
        end
    end

    -- Check 2: Lateral deviation
    local lat_threshold = cfg.deviation_threshold or 2.0

    -- Corridor-adaptive: use corridor width if available
    if corridor_widths then
        local w1 = corridor_widths[best_seg]
        local w2 = corridor_widths[best_seg + 1]
        if w1 and w2 then
            local interpolated_width = w1 + best_t * (w2 - w1)
            local corridor_factor = cfg.deviation_corridor_factor or 0.75
            lat_threshold = math.max(2.0, interpolated_width * corridor_factor)
        end
    end

    result.threshold = lat_threshold

    if best_dist > lat_threshold then
        result.deviated = true
    end

    return result
end

---Decide if a repath should be triggered based on deviation result.
---@param deviation_result table Result from check_deviation
---@param max_repaths number Max allowed repaths
---@param current_count number Current repath count
---@return boolean should_repath
function PathValidationService:should_repath(deviation_result, max_repaths, current_count)
    if not deviation_result.deviated then return false end
    if current_count >= max_repaths then return false end
    return true
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------

---Update config at runtime
---@param overrides table
function PathValidationService:update_config(overrides)
    if not overrides then return end
    for k, v in pairs(overrides) do
        self._config[k] = v
    end
end

---Get config value
---@param key string
---@param default? any
---@return any
function PathValidationService:get_config(key, default)
    local val = self._config[key]
    if val == nil then return default end
    return val
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

function PathValidationService:_test()
    local Blackboard = require("core/Blackboard")
    local results = {}

    -- Test 1: Construction
    local bb = Blackboard:new()
    local svc = PathValidationService:new(bb)
    results["construction"] = (svc ~= nil and svc._config.deviation_threshold == 2.0)

    -- Test 2: Downsample - small path unchanged
    local small_path = {
        { x = 0, y = 0, z = 0 },
        { x = 1, y = 0, z = 0 },
        { x = 2, y = 0, z = 0 },
    }
    local downsampled = svc:_downsample(small_path, 10)
    results["downsample_small"] = (#downsampled == 3)

    -- Test 3: Downsample - large path reduced
    local large_path = {}
    for i = 1, 50 do
        large_path[i] = { x = i, y = 0, z = 0 }
    end
    downsampled = svc:_downsample(large_path, 10)
    results["downsample_large"] = (#downsampled == 10)
    results["downsample_first"] = (downsampled[1].x == 1)
    results["downsample_last"] = (downsampled[#downsampled].x == 50)

    -- Test 4: No deviation on path
    local path = {
        { x = 0, y = 0, z = 0 },
        { x = 10, y = 0, z = 0 },
        { x = 20, y = 0, z = 0 },
    }
    local pos_on_path = { x = 5, y = 0, z = 0 }
    local dev = svc:check_deviation(pos_on_path, path, 2, nil)
    results["no_deviation"] = (not dev.deviated and dev.drift < 0.01)

    -- Test 4b: path_index=1 still evaluates correctly
    dev = svc:check_deviation(pos_on_path, path, 1, nil)
    results["no_deviation_index1"] = (not dev.deviated and dev.drift < 0.01)

    -- Test 5: Lateral deviation detected
    local pos_off_path = { x = 5, y = 10, z = 0 }  -- 10 units off
    dev = svc:check_deviation(pos_off_path, path, 2, nil)
    results["lateral_deviation"] = (dev.deviated and dev.drift > 9.0)

    -- Test 6: Vertical deviation detected
    local pos_wrong_floor = { x = 5, y = 0, z = 10 }  -- 10 units up
    dev = svc:check_deviation(pos_wrong_floor, path, 2, nil)
    results["vertical_deviation"] = (dev.deviated and dev.vertical_drift > 9.0)

    -- Test 7: Corridor-adaptive threshold
    local corridor = { 8.0, 8.0, 8.0 }  -- 8yd wide corridor
    local pos_moderate = { x = 5, y = 4, z = 0 }  -- 4 units off
    svc._config.deviation_corridor_factor = 0.75
    dev = svc:check_deviation(pos_moderate, path, 2, corridor)
    -- corridor threshold = max(2.0, 8.0 * 0.75) = 6.0, drift = 4 < 6 = not deviated
    results["corridor_adaptive"] = (not dev.deviated)

    -- Test 8: Lookahead compatibility (closest segment can be ahead of path_index)
    local long_path = {}
    for i = 0, 100, 10 do
        long_path[#long_path + 1] = { x = i, y = 0, z = 0 }
    end
    local pos_near_ahead = { x = 45, y = 0.2, z = 0 }
    dev = svc:check_deviation(pos_near_ahead, long_path, 2, nil)
    results["ahead_segment_match"] = (not dev.deviated and dev.drift < 1.0)

    -- Test 8a: wrong-floor near destination should trigger even when segment
    -- projection around current index appears valid.
    local path_near_dest_vertical = {
        { x = 0, y = 0, z = 0 },
        { x = 30, y = 0, z = 0 },
        { x = 30, y = 0, z = 15 },
    }
    local pos_under_dest = { x = 30, y = 0, z = 0 }
    dev = svc:check_deviation(pos_under_dest, path_near_dest_vertical, 2, nil)
    results["dest_column_vertical_deviation"] = dev.deviated and dev.vertical_drift > 10

    -- Test 8b: single-waypoint wrong-floor detection near target column
    local single_wp = { { x = 5, y = 5, z = 20 } }
    local pos_below_wp = { x = 5.5, y = 5.4, z = 5 }
    dev = svc:check_deviation(pos_below_wp, single_wp, 1, nil)
    results["single_wp_vertical_deviation"] = dev.deviated and dev.vertical_drift > 10

    -- Test 8c: single-waypoint vertical mismatch but far lateral should not trigger
    local pos_far_xy = { x = 40, y = 40, z = 5 }
    dev = svc:check_deviation(pos_far_xy, single_wp, 1, nil)
    results["single_wp_far_lateral_not_deviated"] = not dev.deviated

    -- Test 9: should_repath
    results["should_repath_yes"] = svc:should_repath({ deviated = true }, 5, 2)
    results["should_repath_no_deviated"] = not svc:should_repath({ deviated = false }, 5, 2)
    results["should_repath_max_reached"] = not svc:should_repath({ deviated = true }, 5, 5)

    -- Test 10: Config override
    svc = PathValidationService:new(bb, { deviation_threshold = 5.0 })
    results["config_override"] = (svc._config.deviation_threshold == 5.0)

    return results
end

return PathValidationService
