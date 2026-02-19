local Defaults = require("core.Defaults")
local Helpers = require("lib.Helpers")

local BASE_RUN_SPEED = 7.0  -- WoW base run speed in yd/s

local MovementService = {}
MovementService.__index = MovementService

function MovementService:new(blackboard, config)
    local o = setmetatable({}, self)
    o._bb = blackboard

    -- Load defaults
    local defaults = Defaults.flat(Defaults.movement)
    o._config = {}
    for k, v in pairs(defaults) do o._config[k] = v end
    if config then
        for k, v in pairs(config) do o._config[k] = v end
    end

    -- simple_movement reference (loaded lazily)
    o._sm = nil
    o._last_applied_speed = 0
    o._initialized = false

    return o
end

-- Initialize simple_movement (call once when first needed)
function MovementService:_ensure_init()
    if self._initialized then return true end

    local ok, sm = pcall(require, "common/utility/simple_movement")
    if not ok or not sm then
        if core and core.log_error then
            core.log_error("[MovementService] Failed to load simple_movement")
        end
        return false
    end

    self._sm = sm
    self._initialized = true

    -- Configure simple_movement
    if self._sm.set_threshold then
        self._sm:set_threshold(self._config.waypoint_tolerance or 3.0)
    end
    if self._sm.set_final_threshold then
        self._sm:set_final_threshold(self._config.final_tolerance or 1.5)
    end
    if self._sm.set_smoothing_enabled then
        self._sm:set_smoothing_enabled(false)  -- We handle smoothing server-side
    end
    if self._sm.set_use_look_at then
        self._sm:set_use_look_at(false)
    end

    return true
end

-- Start following a path (array of {x,y,z} waypoints)
function MovementService:navigate(waypoints)
    if not self:_ensure_init() then return false end
    if not waypoints or #waypoints == 0 then return false end

    self._sm:navigate(waypoints)
    self._last_applied_speed = 0
    return true
end

-- Process one tick of movement. Returns true if destination reached.
function MovementService:process()
    if not self._sm then return false end
    return self._sm:process()
end

-- Stop all movement
function MovementService:stop()
    if self._sm then
        self._sm:stop()
    end
    self._last_applied_speed = 0
end

-- Get current waypoint index (1-based)
function MovementService:get_current_index()
    if not self._sm or not self._sm.get_current_index then return 1 end
    return self._sm:get_current_index()
end

-- Get remaining waypoint count
function MovementService:get_remaining_waypoints()
    if not self._sm or not self._sm.get_remaining_waypoints then return 0 end
    return self._sm:get_remaining_waypoints()
end

-- Check if simple_movement is currently moving
function MovementService:is_moving()
    if not self._sm or not self._sm.is_moving then return false end
    return self._sm:is_moving()
end

-- Strafe in a direction ("left" or "right")
function MovementService:strafe(direction)
    if not self._sm or not self._sm.strafe then return end
    self._sm:strafe(direction)
end

-- Apply dynamic speed scaling based on current player speed
-- This adjusts tolerances, look-ahead distance, and turn speed
-- to handle mounted/sprint speeds smoothly
function MovementService:apply_dynamic_speed(blackboard)
    local bb = blackboard or self._bb
    local cfg = self._config

    if not cfg.dynamic_speed then return end

    local cur_speed = bb:get("player.speed", 0)
    if cur_speed < 0.1 then return end  -- Not moving

    -- Throttle: only recalc if speed changed > 5%
    if self._last_applied_speed > 0 then
        local delta = math.abs(cur_speed - self._last_applied_speed) / self._last_applied_speed
        if delta < 0.05 then return end
    end
    self._last_applied_speed = cur_speed

    -- Speed ratio relative to base run speed
    local ratio = cur_speed / BASE_RUN_SPEED

    -- Look-ahead distance: scale with speed, clamp [5, 12]
    local look_dist = Helpers.clamp(cur_speed * 0.45, 5.0, 12.0)

    -- Base tolerance
    local base_tol = cfg.waypoint_tolerance or 3.0

    -- Corridor-aware: if corridor widths available, cap tolerance
    local corridor_widths = bb:get("path.corridor_widths")
    if corridor_widths then
        local index = bb:get("path.index", 1)
        if corridor_widths[index] then
            local min_width = corridor_widths[index]
            base_tol = math.min(base_tol, min_width * 0.4)
        end
    end

    -- Tolerance scaling
    local max_scale = cfg.dynamic_speed_max_tolerance_scale or 1.20
    local max_bonus = cfg.dynamic_speed_max_tolerance_bonus or 0.75
    local tol_scale = Helpers.clamp(0.85 + (ratio * 0.20), 0.90, max_scale)
    local min_tol = 1.5
    local max_tol = base_tol + max_bonus
    local scaled_tol = Helpers.clamp(base_tol * tol_scale, min_tol, max_tol)

    -- Final tolerance (modest scaling)
    local final_tol = Helpers.clamp((cfg.final_tolerance or 1.5) * Helpers.clamp(ratio * 0.15 + 0.85, 0.95, 1.25), 0.8, 2.0)

    -- Ramp detection: if waypoint has significant Z change, tighten everything
    local waypoints = bb:get("path.waypoints")
    local path_index = bb:get("path.index", 1)
    if waypoints and waypoints[path_index] then
        local target_wp = waypoints[path_index]
        local pos = bb:get("player.position")
        if pos then
            local z_delta = math.abs(target_wp.z - pos.z)
            local ramp_z = cfg.dynamic_speed_ramp_z_delta or 1.2
            if z_delta >= ramp_z then
                local ramp_tol = cfg.dynamic_speed_ramp_tolerance or 1.8
                scaled_tol = ramp_tol
                final_tol = ramp_tol * 0.75
                look_dist = cfg.dynamic_speed_ramp_look_distance or 6.0
            end
        end
    end

    -- Turn speed: scale with ratio, clamp [0.05, 0.25]
    local turn_speed = Helpers.clamp(0.05 * ratio, 0.05, 0.25)

    -- Apply to simple_movement
    if self._sm then
        if self._sm.set_threshold then self._sm:set_threshold(scaled_tol) end
        if self._sm.set_final_threshold then self._sm:set_final_threshold(final_tol) end
        if self._sm.set_look_distance then self._sm:set_look_distance(look_dist) end
        if self._sm.set_turn_speed then self._sm:set_turn_speed(turn_speed) end
    end
end

-- Update config at runtime
function MovementService:update_config(overrides)
    if not overrides then return end
    for k, v in pairs(overrides) do
        self._config[k] = v
    end
    -- Re-apply base thresholds if simple_movement is initialized
    if self._sm then
        if overrides.waypoint_tolerance and self._sm.set_threshold then
            self._sm:set_threshold(overrides.waypoint_tolerance)
        end
        if overrides.final_tolerance and self._sm.set_final_threshold then
            self._sm:set_final_threshold(overrides.final_tolerance)
        end
    end
end

-- Get current config value
function MovementService:get_config(key, default)
    local val = self._config[key]
    if val == nil then return default end
    return val
end

function MovementService:_test()
    local Blackboard = require("core.Blackboard")
    local results = {}

    -- Test 1: Construction
    local bb = Blackboard:new()
    local svc = MovementService:new(bb)
    results["construction"] = (svc ~= nil and svc._config.waypoint_tolerance == 3.0)

    -- Test 2: Config override
    svc = MovementService:new(bb, { waypoint_tolerance = 5.0 })
    results["config_override"] = (svc._config.waypoint_tolerance == 5.0)

    -- Test 3: Runtime config update
    svc:update_config({ final_tolerance = 2.0 })
    results["runtime_config"] = (svc._config.final_tolerance == 2.0)

    -- Test 4: get_config
    results["get_config"] = (svc:get_config("waypoint_tolerance") == 3.0)
    results["get_config_default"] = (svc:get_config("nonexistent", 42) == 42)

    -- Test 5: Dynamic speed calculation (mock)
    -- Can't fully test without simple_movement, but verify logic doesn't crash
    bb:set("player.speed", 14.0)  -- mounted speed
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("path.waypoints", {{ x = 10, y = 0, z = 0 }})
    bb:set("path.index", 1)
    -- apply_dynamic_speed should not crash even without simple_movement
    local ok = pcall(function() svc:apply_dynamic_speed(bb) end)
    results["dynamic_speed_no_crash"] = ok

    return results
end

return MovementService
