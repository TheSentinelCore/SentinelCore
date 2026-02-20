---@class PathValidationService
---Path validity checking and deviation detection.
---Extracted from Movement.lua's _check_path_validity() and _check_deviation() logic.
local PathValidationService = {}
PathValidationService.__index = PathValidationService

local Defaults = require("core/Defaults")
local Helpers = require("lib/Helpers")

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
        callback(true, nil)  -- Too few waypoints to validate
        return
    end

    -- Downsample to avoid false positives from dense Chaikin-smoothed paths
    local sample = self:_downsample(remaining_waypoints, 10)

    nav_service:check_path(current_pos, sample, function(success, data, err)
        if not success then
            callback(true, nil)  -- Can't validate, assume OK
            return
        end
        callback(data.valid ~= false, data.first_invalid_segment)
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
    if path_index < 2 or path_index > #path_waypoints then return result end

    -- Search backwards from current index for closest segment
    -- Use a 60-segment window to account for lookahead
    local best_dist = math.huge
    local best_t = 0
    local best_seg = 0
    local search_start = math.max(1, path_index - 60)

    for i = search_start, math.min(path_index, #path_waypoints - 1) do
        local a = path_waypoints[i]
        local b = path_waypoints[i + 1]
        local dist, t = Helpers.point_to_segment_distance(
            current_pos.x, current_pos.y, current_pos.z,
            a.x, a.y, a.z,
            b.x, b.y, b.z
        )
        if dist < best_dist then
            best_dist = dist
            best_t = t
            best_seg = i
        end
    end

    if best_seg == 0 then return result end

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

    -- Test 8: should_repath
    results["should_repath_yes"] = svc:should_repath({ deviated = true }, 5, 2)
    results["should_repath_no_deviated"] = not svc:should_repath({ deviated = false }, 5, 2)
    results["should_repath_max_reached"] = not svc:should_repath({ deviated = true }, 5, 5)

    -- Test 9: Config override
    svc = PathValidationService:new(bb, { deviation_threshold = 5.0 })
    results["config_override"] = (svc._config.deviation_threshold == 5.0)

    return results
end

return PathValidationService
