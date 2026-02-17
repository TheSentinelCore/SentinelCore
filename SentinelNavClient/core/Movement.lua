-- Movement.lua
-- Path following and stuck recovery for SentinelNavClient consumers
-- Uses Navigation for pathfinding, simple_movement for locomotion

local vec3 = require("common/geometry/vector_3")
local simple_movement = require("common/utility/simple_movement")
local Navigation = require("core/Navigation")
local Defaults = require("core/Defaults")
local Helpers = require("lib/Helpers")

-- State constants
local S_IDLE = "idle"
local S_REQUESTING = "requesting_path"
local S_MOVING = "moving"
local S_STUCK = "stuck"
local S_ARRIVED = "arrived"
local S_FAILED = "failed"

-- Speed constants
local BASE_RUN_SPEED = 7.0 -- yards/sec, standard run speed

-- Build DEFAULT_CONFIG from single source of truth
local DEFAULT_CONFIG = Defaults.flat(Defaults.movement)
DEFAULT_CONFIG.smooth_ratio = DEFAULT_CONFIG.smooth_ratio / 100 -- slider is %, engine is decimal

-- Class ------------------------------------------------------------------

---@class Movement
---@field private _nav_client Navigation
---@field private _config table
---@field private _state string
---@field private _destination vec3|nil
---@field private _current_path vec3[]|nil
---@field private _callback function|nil
---@field private _pending_move table|nil
---@field private _last_stuck_time number
---@field private _last_stuck_pos vec3|nil
---@field private _stuck_count number
---@field private _unstuck_timer number
---@field private _unstuck_phase string|nil
---@field private _path_check_time number
---@field private _route_data table|nil
---@field private _corridor_widths number[]|nil
---@field private _obstacle_module table|nil
---@field private _obstacle_lookahead_time number
---@field private _last_deviation_check number
---@field private _last_repath_time number
---@field _path_index number
local Movement = {}
Movement.__index = Movement

---Create a new Movement
---@param nav_client Navigation Navigation client instance
---@param config? table Override default config values
---@return Movement
function Movement:new(nav_client, config)
    if not nav_client then
        error("Movement requires a Navigation instance")
    end

    local o = setmetatable({}, Movement)

    o._nav_client = nav_client

    -- Merge config with defaults
    o._config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        o._config[k] = v
    end
    if config then
        for k, v in pairs(config) do
            o._config[k] = v
        end
    end

    -- State
    o._state = S_IDLE
    o._destination = nil
    o._current_path = nil
    o._callback = nil
    o._pending_move = nil

    -- Stuck detection
    o._last_stuck_time = 0
    o._last_stuck_pos = nil
    o._stuck_count = 0
    o._unstuck_timer = 0
    o._unstuck_phase = nil

    -- Path validation
    o._path_check_time = 0
    o._validity_repath_pending = false

    -- Route mode
    o._route_data = nil

    -- Corridor data
    o._corridor_widths = nil

    -- Obstacle avoidance
    o._obstacle_module = nil
    o._obstacle_lookahead_time = 0

    -- Deviation monitoring
    o._last_deviation_check = 0
    o._last_repath_time = 0
    o._deviation_repath_count = 0

    -- Compatibility: consumers read _path_index directly
    o._path_index = 1

    -- Speed scaling state
    o._last_applied_speed = 0

    -- Configure simple_movement
    simple_movement:set_threshold(o._config.waypoint_tolerance)
    simple_movement:set_final_threshold(o._config.final_tolerance)
    simple_movement:set_smoothing_enabled(false)
    simple_movement:set_use_look_at(false)
    -- simple_movement:set_turn_speed(0.05)

    return o
end

-- State management -------------------------------------------------------

---Set state with log
---@param new_state string
function Movement:_set_state(new_state)
    if self._state == new_state then return end
    self:_verbose("State: " .. self._state .. " -> " .. new_state)
    self._state = new_state
end

---Get current state
---@return string
function Movement:get_state()
    return self._state
end

---Check if actively moving or requesting a path
---@return boolean
function Movement:is_moving()
    return self._state == S_MOVING or self._state == S_REQUESTING
end

---Get current waypoint path
---@return vec3[]|nil
function Movement:get_current_path()
    return self._current_path
end

---Get current movement destination
---@return vec3|nil
function Movement:get_destination()
    return self._destination
end

---Get current waypoint index in the path
---@return number
function Movement:get_path_index()
    return self._path_index or 1
end

---Update config values at runtime (e.g., from UI settings)
---@param overrides table Key-value pairs to merge into config
function Movement:update_config(overrides)
    if not overrides then return end
    for k, v in pairs(overrides) do
        self._config[k] = v
    end
    -- Propagate tolerance changes to simple_movement when not using dynamic speed
    -- (dynamic speed handles this itself in _apply_dynamic_speed)
    if not self._config.dynamic_speed then
        simple_movement:set_threshold(self._config.waypoint_tolerance)
        simple_movement:set_final_threshold(self._config.final_tolerance)
    end
end

---Log a message only when debug_verbose is enabled
---@param msg string
function Movement:_verbose(msg)
    if self._config.debug_verbose then
        core.log("[Movement] " .. msg)
    end
end

---Attach an ObstacleModule for avoidance-aware pathfinding
---@param obstacle_module table
function Movement:set_obstacle_module(obstacle_module)
    self._obstacle_module = obstacle_module
end

---Build opts table for find_path from current config
---@param extra? table Additional opts to merge (e.g., map_id from caller)
---@return table
function Movement:_build_path_opts(extra)
    local o = {
        smoothing         = self._config.smoothing,
        optimize          = self._config.optimize,
        anti_detection    = self._config.anti_detection,
        max_deviation     = self._config.max_deviation,
        allow_partial     = self._config.allow_partial,
        smooth_iterations = self._config.smooth_iterations,
        smooth_samples    = self._config.smooth_samples,
        smooth_ratio      = self._config.smooth_ratio,
        min_corner_angle  = self._config.min_corner_angle,
        keep_originals    = self._config.keep_originals,
        filter_ground     = self._config.filter_ground,
        filter_water      = self._config.filter_water,
        filter_lava       = self._config.filter_lava,
        wall_clearance    = self._config.wall_clearance,
    }
    if extra then
        for k, v in pairs(extra) do o[k] = v end
    end
    return o
end

---Build opts table for find_path_corridor from current config
---Omits anti_detection/max_deviation (corridor has no random variant)
---@param extra? table Additional opts to merge
---@return table
function Movement:_build_corridor_opts(extra)
    local o = {
        smoothing         = self._config.smoothing,
        optimize          = self._config.optimize,
        allow_partial     = self._config.allow_partial,
        smooth_iterations = self._config.smooth_iterations,
        smooth_samples    = self._config.smooth_samples,
        smooth_ratio      = self._config.smooth_ratio,
        min_corner_angle  = self._config.min_corner_angle,
        keep_originals    = self._config.keep_originals,
        filter_ground     = self._config.filter_ground,
        filter_water      = self._config.filter_water,
        filter_lava       = self._config.filter_lava,
        probe_distance    = self._config.corridor_probe_dist,
        wall_clearance    = self._config.wall_clearance,
    }
    if extra then
        for k, v in pairs(extra) do o[k] = v end
    end
    return o
end

---Determine if corridor pathfinding should be used (indoor + enabled)
---@return boolean
function Movement:_should_use_corridor()
    if not self._config.use_corridor_indoor then return false end
    return Navigation.is_indoor()
end

---Compute the minimum corridor width from stored corridor data
---@return number|nil min_width Minimum width in yards, or nil if no data
function Movement:_compute_min_corridor_width()
    if not self._corridor_widths or #self._corridor_widths == 0 then
        return nil
    end
    local min_w = self._corridor_widths[1]
    for i = 2, #self._corridor_widths do
        if self._corridor_widths[i] < min_w then
            min_w = self._corridor_widths[i]
        end
    end
    return min_w
end

---Get corridor widths for the current path (nil if outdoor or no data)
---@return number[]|nil
function Movement:get_corridor_widths()
    return self._corridor_widths
end

---Best-effort accessor for the current target waypoint.
---@return vec3|table|nil
function Movement:_get_active_waypoint()
    if simple_movement.get_target then
        local ok, target = pcall(function()
            return simple_movement:get_target()
        end)
        if ok and target then
            return target
        end
    end

    if self._current_path and #self._current_path > 0 then
        local idx = self._path_index or 1
        return self._current_path[idx] or self._current_path[#self._current_path]
    end

    return nil
end

---Get progress information
---@return table { state, destination?, distance_remaining?, path_index?, path_count?, current_leg?, total_legs?, route_mode? }
function Movement:get_progress()
    local progress = { state = self._state, destination = self._destination }

    if self._state == S_MOVING and self._destination then
        local player = core.object_manager.get_local_player()
        if player and player:is_valid() then
            progress.distance_remaining = player:get_position():dist_to(self._destination)
        end
        progress.path_index = simple_movement:get_current_index()
        progress.path_count = simple_movement:get_waypoint_count()
    end

    if self._route_data then
        progress.current_leg = self._route_data.current_leg
        progress.total_legs = self._route_data.total_legs
        progress.route_mode = true
    end

    return progress
end

---Stop all movement and reset to idle
function Movement:stop()
    simple_movement:stop()
    self._state = S_IDLE
    self._destination = nil
    self._current_path = nil
    self._callback = nil
    self._pending_move = nil
    self._stuck_count = 0
    self._unstuck_phase = nil
    self._route_data = nil
    self._corridor_widths = nil
    self._obstacle_lookahead_time = 0
    self._last_deviation_check = 0
    self._last_repath_time = 0
    self._deviation_repath_count = 0
    self._path_index = 1
    self._last_applied_speed = 0
    self._validity_repath_pending = false
    simple_movement:set_threshold(self._config.waypoint_tolerance)
    simple_movement:set_final_threshold(self._config.final_tolerance)
end

-- Update loop ------------------------------------------------------------

---Apply dynamic speed adaptation to movement parameters.
---Scales look-ahead, waypoint tolerance, final tolerance, and turn speed
---based on the player's current velocity relative to BASE_RUN_SPEED.
---Respects indoor corridor tolerance when corridor data is present.
---@param player game_object
function Movement:_apply_dynamic_speed(player)
    if not self._config.dynamic_speed then return end

    local cur_speed = player:get_movement_speed()
    if not cur_speed or cur_speed < 0.1 then return end

    -- Throttle updates: only recalculate if speed changed by > 5%
    if self._last_applied_speed > 0 and math.abs(cur_speed - self._last_applied_speed) < (self._last_applied_speed * 0.05) then
        return
    end
    self._last_applied_speed = cur_speed

    -- Ratio vs base run speed (e.g. 14.0 / 7.0 = 2.0 for epic mount)
    local ratio = cur_speed / BASE_RUN_SPEED

    -- Look-ahead: increase with speed but keep conservative to avoid waypoint cutting.
    local look_dist = math.max(5.0, math.min(12.0, cur_speed * 0.45))

    -- Tolerance: start from corridor-aware base tolerance.
    local base_tol = self._config.waypoint_tolerance
    if self._corridor_widths then
        local min_w = self:_compute_min_corridor_width()
        if min_w and min_w < base_tol then
            base_tol = math.max(1.0, min_w * 0.4)
        end
    end

    local max_scale = self._config.dynamic_speed_max_tolerance_scale or 1.20
    local max_bonus = self._config.dynamic_speed_max_tolerance_bonus or 0.75
    local tol_scale = math.max(0.90, math.min(max_scale, 0.85 + (ratio * 0.20)))
    local max_tol = math.min(base_tol * max_scale, base_tol + max_bonus)
    local min_tol = math.max(1.0, math.min(1.5, base_tol))
    local new_tolerance = math.max(min_tol, math.min(max_tol, base_tol * tol_scale))

    -- Final tolerance: modest scaling only; avoid over-inflating arrival radius.
    local final_ratio = math.max(0.95, math.min(1.25, ratio))
    local new_final = math.max(1.0, math.min(2.4, self._config.final_tolerance * final_ratio))

    -- Ramp-aware guard: tighten tolerance/look-ahead when climbing.
    local active_wp = self:_get_active_waypoint()
    if active_wp then
        local player_pos = player:get_position()
        if player_pos then
            local dz = math.abs((active_wp.z or player_pos.z or 0) - (player_pos.z or 0))
            if dz >= (self._config.dynamic_speed_ramp_z_delta or 1.2) then
                local ramp_tol = self._config.dynamic_speed_ramp_tolerance or 1.8
                local ramp_look = self._config.dynamic_speed_ramp_look_distance or 6.0
                new_tolerance = math.min(new_tolerance, ramp_tol)
                new_final = math.min(new_final, math.max(1.0, ramp_tol * 0.75))
                look_dist = math.min(look_dist, ramp_look)
            end
        end
    end

    -- Turn speed: proportional to velocity (0.05-0.25).
    local turn_speed = math.max(0.05, math.min(0.25, 0.05 * ratio))

    -- Apply to simple_movement.
    simple_movement:set_look_distance(look_dist)
    simple_movement:set_threshold(new_tolerance)
    simple_movement:set_final_threshold(new_final)
    simple_movement:set_turn_speed(turn_speed)
end

---Call every frame to drive movement
function Movement:update()
    -- Nothing to do in terminal/idle states
    if self._state == S_IDLE or self._state == S_ARRIVED or self._state == S_FAILED then
        return
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end

    -- Deferred move: waiting for cast/channel to end
    if self._pending_move then
        if not player:is_casting_spell() and not player:is_channelling_spell() then
            local pm = self._pending_move
            self._pending_move = nil
            self:move_to(pm.target, pm.callback, pm.opts)
        end
        return
    end

    -- Waiting for async path response
    if self._state == S_REQUESTING then return end

    -- Active movement
    if self._state == S_MOVING then
        -- Adapt to speed changes (mount/dismount/sprint)
        self:_apply_dynamic_speed(player)

        local reached = simple_movement:process()
        self._path_index = simple_movement:get_current_index() or 1

        if reached then
            self:_on_arrival()
            return
        end

        -- Fallback arrival check by distance
        if self._destination then
            local dist = player:get_position():dist_to(self._destination)
            if dist <= self._config.final_tolerance then
                self:_on_arrival()
                return
            end
        end

        -- Stuck detection (skip while casting)
        if not player:is_casting_spell() and not player:is_channelling_spell() then
            self:_check_stuck(player)
        end

        -- Route leg tracking
        if self._route_data then
            self:_check_route_progress()
        end

        -- Periodic path validation
        self:_check_path_validity(player)

        -- Deviation-aware adaptive repath
        self:_check_deviation(player)

        -- Proactive obstacle look-ahead
        self:_check_proactive_obstacles()
    end

    -- Process timed unstuck actions (strafe / backward)
    if self._unstuck_phase then
        self:_process_unstuck_action()
    end
end

-- Single-target movement -------------------------------------------------

---Move to a target position using navmesh pathfinding
---@param target vec3 Destination
---@param callback? fun(success: boolean, reason: string|nil)
---@param opts? table { use_navmesh?: boolean, map_id?: number }
function Movement:move_to(target, callback, opts)
    if not target then
        core.log_error("[Movement] move_to: no target")
        if callback then callback(false, "No target") end
        return
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() or player:is_dead() then
        core.log_error("[Movement] move_to: player not available")
        if callback then callback(false, "Player not available") end
        return
    end

    opts = opts or {}

    -- Store destination and callback
    self._destination = target
    self._callback = callback
    self._route_data = nil
    self._partial_path = false

    -- Reset stuck detection and obstacle look-ahead
    self._stuck_count = 0
    self._last_stuck_time = core.time()
    self._last_stuck_pos = player:get_position()
    self._path_check_time = core.time()
    self._obstacle_lookahead_time = 0
    self._last_deviation_check = 0
    self._last_repath_time = 0
    self._deviation_repath_count = 0
    self._unstuck_phase = nil

    -- Defer if casting
    if player:is_casting_spell() or player:is_channelling_spell() then
        self:_verbose("Player casting, deferring movement")
        self:_set_state(S_REQUESTING)
        self._pending_move = { target = target, callback = callback, opts = opts }
        return
    end

    -- Direct movement (no pathfinding)
    if opts.use_navmesh == false then
        self:_start_movement({ target })
        return
    end

    -- Request path from SentinelNavServer
    self:_set_state(S_REQUESTING)

    local start_pos = player:get_position()
    local use_corridor = self:_should_use_corridor()

    -- Shared callback for both path types
    local function on_path(ok, data, err)
        if self._state ~= S_REQUESTING then
            core.log_warning("[Movement] Path received but state is " .. self._state .. ", ignoring")
            return
        end

        if not ok or not data then
            core.log_error("[Movement] Pathfinding failed: " .. (err or "unknown"))
            self:_set_state(S_FAILED)
            if self._callback then
                self._callback(false, err or "Pathfinding failed")
                self._callback = nil
            end
            return
        end

        if not data.waypoints or #data.waypoints == 0 then
            core.log_error("[Movement] Empty path received")
            self:_set_state(S_FAILED)
            if self._callback then
                self._callback(false, "Empty path")
                self._callback = nil
            end
            return
        end

        if data.partial and not self._config.allow_partial then
            core.log_warning("[Movement] Partial path — destination unreachable")
            self:_set_state(S_FAILED)
            if self._callback then
                self._callback(false, "Destination unreachable (partial path)")
                self._callback = nil
            end
            return
        end

        -- Track whether this path is partial (destination not fully reachable)
        self._partial_path = data.partial or false
        if self._partial_path then
            core.log_warning("[Movement] Partial path accepted — destination not fully reachable ("
                .. #data.waypoints .. " waypoints, "
                .. string.format("%.1f", data.distance or 0) .. " yd)")
        end

        -- Store corridor data and adjust tolerance for indoor paths
        if use_corridor and data.corridor_widths then
            self._corridor_widths = data.corridor_widths
            local min_width = self:_compute_min_corridor_width()
            if min_width and min_width < self._config.waypoint_tolerance then
                local indoor_tolerance = math.max(1.0, min_width * 0.4)
                simple_movement:set_threshold(indoor_tolerance)
                simple_movement:set_final_threshold(math.min(self._config.final_tolerance, indoor_tolerance))
                self:_verbose("Corridor: min width " .. string.format("%.1f", min_width)
                    .. " yd, tolerance -> " .. string.format("%.1f", indoor_tolerance))
            end
        else
            self._corridor_widths = nil
        end

        local label = use_corridor and "Corridor path" or "Path"
        self:_verbose(label .. " received: " .. #data.waypoints .. " waypoints, "
            .. string.format("%.1f", data.distance or 0) .. " yards")

        self:_start_movement(data.waypoints)
    end

    -- Gather avoidance zones (used by both corridor and regular paths)
    local zones = self._obstacle_module
        and self._obstacle_module:get_avoidance_zones()
        or {}

    if use_corridor then
        self._nav_client:find_path_corridor(start_pos, target, on_path,
            self:_build_corridor_opts({ map_id = opts.map_id, avoid_zones = zones }))
    else
        if #zones > 0 then
            self._nav_client:find_path_avoid(start_pos, target, zones, on_path,
                self:_build_path_opts({ map_id = opts.map_id }))
        else
            self._nav_client:find_path(start_pos, target, on_path,
                self:_build_path_opts({ map_id = opts.map_id }))
        end
    end
end

---Move directly to target without pathfinding (short range / emergency)
---@param target vec3
---@param callback? fun(success: boolean, reason: string|nil)
function Movement:move_direct(target, callback)
    self:move_to(target, callback, { use_navmesh = false })
end

---Follow a pre-computed waypoint path without requesting pathfinding.
---@param waypoints vec3[] Pre-computed path waypoints
---@param callback? fun(success: boolean, reason: string|nil)
function Movement:follow_path(waypoints, callback)
    if not waypoints or #waypoints == 0 then
        core.log_error("[Movement] follow_path: no waypoints")
        if callback then callback(false, "No waypoints") end
        return
    end
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() or player:is_dead() then
        core.log_error("[Movement] follow_path: player not available")
        if callback then callback(false, "Player not available") end
        return
    end
    self._destination = waypoints[#waypoints]
    self._callback = callback
    self._route_data = nil
    self._partial_path = false
    self._corridor_widths = nil
    self._stuck_count = 0
    self._last_stuck_time = core.time()
    self._last_stuck_pos = player:get_position()
    self._path_check_time = core.time()
    self._obstacle_lookahead_time = 0
    self._last_deviation_check = 0
    self._last_repath_time = 0
    self._deviation_repath_count = 0
    self._unstuck_phase = nil
    self:_start_movement(waypoints)
end

---Start movement with a given waypoint list
---@param waypoints vec3[]
function Movement:_start_movement(waypoints)
    if not waypoints or #waypoints == 0 then
        core.log_error("[Movement] _start_movement: empty waypoints")
        self:_set_state(S_FAILED)
        if self._callback then
            self._callback(false, "Empty waypoints")
            self._callback = nil
        end
        return
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        self:_set_state(S_FAILED)
        if self._callback then
            self._callback(false, "Player not available")
            self._callback = nil
        end
        return
    end

    -- Re-defer if still casting
    if player:is_casting_spell() or player:is_channelling_spell() then
        self:_verbose("Player still casting, re-deferring")
        self._pending_move = {
            target = self._destination,
            callback = self._callback,
            opts = { use_navmesh = true },
        }
        -- Store waypoints so deferred path uses them directly
        self._current_path = waypoints
        return
    end

    self._current_path = waypoints
    self:_set_state(S_MOVING)
    simple_movement:navigate(waypoints)
    self:_verbose("Navigating " .. #waypoints .. " waypoints")
end

---Handle arrival at destination
function Movement:_on_arrival()
    simple_movement:stop()

    -- Route mode: fire leg/route callbacks
    if self._route_data then
        local rd = self._route_data
        core.log("[Movement] Route complete (" .. rd.total_legs .. " legs)")
        self:_set_state(S_ARRIVED)
        if self._callback then
            self._callback(true, { type = "route_complete" })
        end
    else
        if self._partial_path then
            core.log_warning("[Movement] Partial path endpoint reached — destination unreachable")
            self:_set_state(S_FAILED)
            if self._callback then
                self._callback(false, "Destination unreachable (partial)")
                self._callback = nil
            end
            self._route_data = nil
            self._corridor_widths = nil
            self._last_applied_speed = 0
            simple_movement:set_threshold(self._config.waypoint_tolerance)
            simple_movement:set_final_threshold(self._config.final_tolerance)
            return
        end

        core.log("[Movement] Arrived at destination")
        self:_set_state(S_ARRIVED)
        if self._callback then
            self._callback(true, nil)
        end
    end

    -- Clean up
    self._callback = nil
    self._route_data = nil
    self._corridor_widths = nil
    self._last_applied_speed = 0
    simple_movement:set_threshold(self._config.waypoint_tolerance)
    simple_movement:set_final_threshold(self._config.final_tolerance)
end

-- Stuck detection & recovery ---------------------------------------------

---Proactively scan upcoming waypoint segments for doodad obstacles.
---Runs on a throttled interval during S_MOVING.
function Movement:_check_proactive_obstacles()
    if not self._config.proactive_obstacle_check then return end
    if not self._obstacle_module then return end

    local now = core.time()
    if now - self._obstacle_lookahead_time < self._config.proactive_obstacle_interval then
        return
    end
    self._obstacle_lookahead_time = now

    local remaining = simple_movement:get_remaining_waypoints()
    if not remaining or #remaining < 2 then return end

    local hit_pos, seg_idx = self._obstacle_module:probe_path_ahead(remaining)
    if not hit_pos then return end

    core.log_warning("[Movement] Proactive: obstacle on segment "
        .. tostring(seg_idx) .. ", adding zone and repathing")

    local player = core.object_manager.get_local_player()
    if player and player:is_valid() then
        self._obstacle_module:prune(player:get_position())
    end

    self._obstacle_module:add_zone(hit_pos)
    self:_unstuck_repath()
end

---Check if player is stuck (called on interval while moving)
---@param player game_object
function Movement:_check_stuck(player)
    -- Don't check while a timed recovery action (strafe/backward) is running
    if self._unstuck_phase then return end

    local now = core.time()
    if now - self._last_stuck_time < self._config.stuck_check_interval then return end
    self._last_stuck_time = now

    local pos = player:get_position()

    if not self._last_stuck_pos then
        self._last_stuck_pos = pos
        return
    end

    local moved = pos:dist_to(self._last_stuck_pos)

    -- Scale expected distance by speed ratio — at mount speed, expect proportionally more movement
    local expected_dist = self._config.stuck_distance_min
    if self._config.dynamic_speed then
        local speed = player:get_movement_speed()
        if speed and speed > 0.1 then
            expected_dist = expected_dist * math.min(3.0, speed / BASE_RUN_SPEED)
        end
    end
    expected_dist = math.min(expected_dist, 3.0)
    if simple_movement:is_moving() and moved < expected_dist then
        self._stuck_count = self._stuck_count + 1
        local moved_2d = pos:dist_to_ignore_z(self._last_stuck_pos)
        local dz = math.abs(pos.z - self._last_stuck_pos.z)
        core.log_warning("[Movement] Stuck #" .. self._stuck_count
            .. " (3D=" .. string.format("%.2f", moved)
            .. " 2D=" .. string.format("%.2f", moved_2d)
            .. " dZ=" .. string.format("%.2f", dz) .. ")")
        self:_handle_stuck()
    else
        if self._stuck_count > 0 then
            self:_verbose("Unstuck (3D=" .. string.format("%.2f", moved) .. " yards)")
        end
        self._stuck_count = 0
    end

    self._last_stuck_pos = pos
end

---Apply recovery strategy based on stuck count
function Movement:_handle_stuck()
    -- Don't attempt recovery while casting (would desync state)
    local player = core.object_manager.get_local_player()
    if player and (player:is_casting_spell() or player:is_channelling_spell()) then
        self:_verbose("Unstuck: deferring — player is casting")
        return
    end

    if self._stuck_count >= self._config.max_stuck_attempts then
        core.log_error("[Movement] Max stuck attempts reached, failing")
        self:_set_state(S_FAILED)
        if self._callback then
            self._callback(false, "Stuck — max attempts exceeded")
            self._callback = nil
        end
        return
    end

    if self._stuck_count == 1 then
        self:_unstuck_jump()
    elseif self._stuck_count == 2 then
        -- Reactive obstacle probe: check if a doodad is blocking
        self:_unstuck_probe_and_repath()
    elseif self._stuck_count == 3 then
        self:_unstuck_strafe()
    elseif self._stuck_count == 4 then
        self:_unstuck_backward()
    else
        self:_unstuck_zone_and_repath()
    end
end

---Strategy 1: Jump
function Movement:_unstuck_jump()
    self:_verbose("Unstuck: jump")
    core.input.jump()
end

---Strategy 2: Probe forward for doodad collision, add avoidance zone + repath
function Movement:_unstuck_probe_and_repath()
    if not self._obstacle_module or not self._destination then
        -- No obstacle module wired — fall back to strafe
        self:_verbose("Unstuck: no obstacle module, falling back to strafe")
        self:_unstuck_strafe()
        return
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end

    local player_pos = player:get_position()

    -- Determine probe target: next waypoint or final destination
    local remaining = simple_movement:get_remaining_waypoints()
    local probe_target = self._destination
    if remaining and #remaining > 0 then
        probe_target = remaining[1]
    end

    -- Prune old zones while we're here
    self._obstacle_module:prune(player_pos)

    -- Probe ahead with trace_line (DoodadCollision)
    local hit_pos = self._obstacle_module:probe_forward(player_pos, probe_target)

    if hit_pos then
        -- Found a collision — add avoidance zone and repath around it
        self._obstacle_module:add_zone(hit_pos)
        self:_verbose("Unstuck: doodad detected, repathing with avoidance")
        self:_unstuck_repath()
    else
        -- No collision detected — fall back to strafe
        self:_verbose("Unstuck: no doodad collision, falling back to strafe")
        self:_unstuck_strafe()
    end
end

---Strategy 3 (fallback from probe): Random strafe + jump
function Movement:_unstuck_strafe()
    local dir = math.random() > 0.5 and "left" or "right"
    self:_verbose("Unstuck: strafe " .. dir)
    self._unstuck_phase = "strafe"
    self._unstuck_timer = core.time()
    simple_movement:strafe(dir)
end

---Strategy 4: Backward + jump
function Movement:_unstuck_backward()
    self:_verbose("Unstuck: backward")
    self._unstuck_phase = "backward"
    self._unstuck_timer = core.time()
    core.input.move_backward_start()
end

---Strategy 5: Request fresh path from current position
function Movement:_unstuck_repath()
    if not self._destination then
        core.log_warning("[Movement] No destination for repath")
        return
    end

    -- If already on a partial path and stuck, don't re-request the same
    -- unreachable destination — it will just produce another partial path
    if self._partial_path then
        core.log_warning("[Movement] Stuck on partial path — failing (destination unreachable)")
        simple_movement:stop()
        self._unstuck_phase = nil
        self:_set_state(S_FAILED)
        if self._callback then
            self._callback(false, "Stuck on partial path")
            self._callback = nil
        end
        return
    end

    self:_verbose("Unstuck: repath")
    self._validity_repath_pending = false
    simple_movement:stop()
    self._unstuck_phase = nil
    self:_set_state(S_REQUESTING)

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end

    local pos = player:get_position()

    local function on_repath(ok, data, err)
        if not ok or not data or not data.waypoints or #data.waypoints == 0 then
            core.log_error("[Movement] Repath failed: " .. (err or "empty path"))
            return
        end
        if data.corridor_widths then
            self._corridor_widths = data.corridor_widths
        end
        self._partial_path = data.partial or false
        self:_verbose("Repath OK: " .. #data.waypoints .. " waypoints"
            .. (self._partial_path and " (partial)" or ""))
        self._stuck_count = 0
        self._last_stuck_time = core.time()
        self._last_stuck_pos = nil
        self._last_deviation_check = core.time()
        self._last_repath_time = core.time()
        self:_start_movement(data.waypoints)
    end

    local zones = self._obstacle_module
        and self._obstacle_module:get_avoidance_zones()
        or {}

    if self:_should_use_corridor() then
        self._nav_client:find_path_corridor(pos, self._destination, on_repath,
            self:_build_corridor_opts({ avoid_zones = zones }))
    else
        if #zones > 0 then
            self._nav_client:find_path_avoid(pos, self._destination, zones, on_repath,
                self:_build_path_opts())
        else
            self._nav_client:find_path(pos, self._destination, on_repath,
                self:_build_path_opts())
        end
    end
end

---Strategy 5: Add avoidance zone at stuck position + repath around it
function Movement:_unstuck_zone_and_repath()
    if self._obstacle_module then
        local player = core.object_manager.get_local_player()
        if player and player:is_valid() then
            local pos = player:get_position()
            self._obstacle_module:add_zone(pos)
            self:_verbose("Unstuck: added avoidance zone at stuck position, repathing")
        end
    end
    self:_unstuck_repath()
end

---Process timed unstuck actions (called in update)
function Movement:_process_unstuck_action()
    local elapsed = core.time() - self._unstuck_timer

    if self._unstuck_phase == "strafe" then
        if elapsed >= 0.5 then
            simple_movement:strafe(nil)
            core.input.jump()
            self._unstuck_phase = nil
        end
    elseif self._unstuck_phase == "backward" then
        if elapsed >= 1.0 then
            core.input.move_backward_stop()
            core.input.jump()
            self._unstuck_phase = nil
        end
    end
end

-- Route mode (TSP) -------------------------------------------------------

---Plan and execute a TSP-optimized route through nodes
---@param nodes vec3[] At least 2 node positions
---@param callback? fun(success: boolean, data: table|nil)
---@param opts? table { map_id?, return_to_start? }
function Movement:plan_route(nodes, callback, opts)
    if not nodes or #nodes < 2 then
        core.log_error("[Movement] plan_route: need at least 2 nodes")
        if callback then callback(false, { error = "Need at least 2 nodes" }) end
        return
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        if callback then callback(false, { error = "Player not available" }) end
        return
    end

    opts = opts or {}
    self._destination = nodes[#nodes]
    self._callback = callback
    self._stuck_count = 0
    self._unstuck_phase = nil
    self._last_stuck_time = core.time()
    self._last_stuck_pos = player:get_position()
    self._path_check_time = core.time()

    self:_set_state(S_REQUESTING)

    local zones = self._obstacle_module
        and self._obstacle_module:get_avoidance_zones()
        or {}
    local tsp_opts = self:_build_path_opts({
        map_id = opts.map_id,
        start_pos = player:get_position(),
        return_to_start = opts.return_to_start,
        avoid_zones = zones,
    })
    self._nav_client:find_route_tsp(nodes, function(ok, data, err)
        if self._state ~= S_REQUESTING then
            core.log_warning("[Movement] Route received but state is " .. self._state .. ", ignoring")
            return
        end

        if not ok or not data or not data.waypoints or #data.waypoints == 0 then
            core.log_error("[Movement] Route planning failed: " .. (err or "empty route"))
            self:_set_state(S_FAILED)
            if self._callback then
                self._callback(false, { error = err or "Route planning failed" })
            end
            return
        end

        core.log("[Movement] Route planned: " .. #data.waypoints .. " waypoints, "
            .. string.format("%.1f", data.total_distance or 0) .. " yards")

        self._route_data = {
            nodes = nodes,
            visit_order = data.visit_order,
            leg_boundaries = data.leg_boundaries,
            leg_distances = data.leg_distances,
            current_leg = 1,
            total_legs = #(data.leg_boundaries or {}),
        }

        self:_start_movement(data.waypoints)
    end, tsp_opts)
end

---Check if we've crossed into a new route leg
function Movement:_check_route_progress()
    if not self._route_data then return end

    local idx = simple_movement:get_current_index()
    local rd = self._route_data
    local boundaries = rd.leg_boundaries

    if not boundaries or rd.current_leg >= #boundaries then return end

    -- Check if current path index crossed next leg boundary
    local next_boundary = boundaries[rd.current_leg + 1]
    if next_boundary and idx >= next_boundary then
        local prev_leg = rd.current_leg
        rd.current_leg = rd.current_leg + 1
        self:_verbose("Route leg " .. prev_leg .. "/" .. rd.total_legs .. " completed")

        if self._callback then
            self._callback(true, {
                type = "leg_complete",
                leg = prev_leg,
                total = rd.total_legs,
            })
        end
    end
end

---Replan route with remaining unvisited nodes
---@param reason? string Why we're replanning
function Movement:replan(reason)
    if not self._route_data then
        core.log_warning("[Movement] No route to replan")
        return
    end

    core.log("[Movement] Replanning route" .. (reason and (": " .. reason) or ""))

    local rd = self._route_data
    local remaining_nodes = {}

    -- Collect nodes from current_leg onward
    if rd.visit_order and rd.nodes then
        for i = rd.current_leg, #rd.visit_order do
            local node_idx = rd.visit_order[i]
            if node_idx and rd.nodes[node_idx] then
                remaining_nodes[#remaining_nodes + 1] = rd.nodes[node_idx]
            end
        end
    end

    local cb = self._callback
    self:stop()

    if #remaining_nodes >= 2 then
        self:plan_route(remaining_nodes, cb)
    else
        core.log_warning("[Movement] Too few remaining nodes to replan")
        if cb then cb(false, { error = "Too few nodes to replan" }) end
    end
end

-- Path validation --------------------------------------------------------

---Periodically check if the current path is still valid
---@param player game_object
function Movement:_check_path_validity(player)
    local now = core.time()
    if now - self._path_check_time < self._config.path_check_interval then return end
    self._path_check_time = now

    if self._validity_repath_pending then return end

    local remaining = simple_movement:get_remaining_waypoints()
    if not remaining or #remaining < 3 then return end

    local pos = player:get_position()
    self._nav_client:check_path(pos, remaining, function(ok, data, err)
        if not ok then return end
        if data and not data.valid and self._destination then
            core.log_warning("[Movement] Path invalid at segment "
                .. tostring(data.first_invalid_segment) .. ", repathing")
            self:_soft_repath()
        end
    end)
end

---Request a fresh path without stopping movement (used by path validity check).
---The character keeps walking the current path while the new one is fetched.
function Movement:_soft_repath()
    if not self._destination then return end
    if self._route_data then
        self:_unstuck_repath()
        return
    end
    if self._partial_path then
        self:_unstuck_repath()
        return
    end

    self:_verbose("Soft repath (no stop)")
    self._validity_repath_pending = true

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        self._validity_repath_pending = false
        return
    end

    local pos = player:get_position()

    local function on_repath(ok, data, err)
        self._validity_repath_pending = false
        if self._state ~= S_MOVING then return end

        if not ok or not data or not data.waypoints or #data.waypoints == 0 then
            core.log_error("[Movement] Soft repath failed: " .. (err or "empty path"))
            return
        end
        if data.corridor_widths then
            self._corridor_widths = data.corridor_widths
        end
        self._partial_path = data.partial or false
        self:_verbose("Soft repath OK: " .. #data.waypoints .. " waypoints"
            .. (self._partial_path and " (partial)" or ""))
        self._stuck_count = 0
        self._last_stuck_time = core.time()
        self._last_stuck_pos = nil
        self._last_deviation_check = core.time()
        self._last_repath_time = core.time()
        self._current_path = data.waypoints
        self._path_index = 1
        simple_movement:navigate(data.waypoints, false, true)
        self:_verbose("Navigating " .. #data.waypoints .. " waypoints")
    end

    local zones = self._obstacle_module
        and self._obstacle_module:get_avoidance_zones()
        or {}

    if self:_should_use_corridor() then
        self._nav_client:find_path_corridor(pos, self._destination, on_repath,
            self:_build_corridor_opts({ avoid_zones = zones }))
    else
        if #zones > 0 then
            self._nav_client:find_path_avoid(pos, self._destination, zones, on_repath,
                self:_build_path_opts())
        else
            self._nav_client:find_path(pos, self._destination, on_repath,
                self:_build_path_opts())
        end
    end
end

-- Deviation monitoring --------------------------------------------------------

---Periodically check if player has deviated from path; repath if outside corridor.
---Uses adaptive corridor-width threshold when available, fixed threshold otherwise.
---Also checks vertical deviation separately (wrong floor/level detection).
---@param player game_object
function Movement:_check_deviation(player)
    -- Don't check while a timed recovery action is running
    if self._unstuck_phase then return end

    local now = core.time()
    if now - self._last_deviation_check < self._config.deviation_check_interval then
        return
    end
    self._last_deviation_check = now

    -- Need a valid current path with at least 2 waypoints traversed
    local idx = self._path_index or 1
    if idx < 2 or not self._current_path or idx > #self._current_path then return end

    -- Respect repath cooldown
    if now - self._last_repath_time < self._config.repath_cooldown then return end

    -- Guard against infinite repath loops
    if self._deviation_repath_count >= self._config.max_deviation_repaths then return end

    local pos = player:get_position()

    -- Search backwards from _path_index to find the closest segment
    -- (_path_index runs ahead due to waypoint_tolerance > waypoint spacing
    --  with dense Chaikin-smoothed paths)
    local best_dist = math.huge
    local best_t = 0
    local best_seg = idx
    local search_start = math.max(2, idx - 60)
    for i = search_start, idx do
        local seg_a = self._current_path[i - 1]
        local seg_b = self._current_path[i]
        if seg_a and seg_b then
            local d, seg_t = Helpers.point_to_segment_distance(
                pos.x, pos.y, pos.z,
                seg_a.x, seg_a.y, seg_a.z,
                seg_b.x, seg_b.y, seg_b.z
            )
            if d < best_dist then
                best_dist = d
                best_t = seg_t
                best_seg = i
            end
            if d < 1.0 then break end  -- Close enough, stop searching
        end
    end

    local drift = best_dist
    local t = best_t
    local a = self._current_path[best_seg - 1]
    local b = self._current_path[best_seg]
    if not a or not b then return end

    self:_verbose(string.format(
        "DevCheck: seg=%d (idx=%d), drift=%.1f, t=%.2f",
        best_seg, idx, drift, t
    ))

    -- Check 1: Vertical deviation (wrong floor/level)
    local expected_z = a.z + t * (b.z - a.z)
    local vertical_drift = math.abs(pos.z - expected_z)
    if vertical_drift > self._config.deviation_vertical_threshold then
        self:_verbose(string.format(
            "Vertical deviation: %.1f yd (threshold %.1f), repathing",
            vertical_drift, self._config.deviation_vertical_threshold
        ))
        self._last_repath_time = now
        self._deviation_repath_count = self._deviation_repath_count + 1
        self:_unstuck_repath()
        return
    end

    -- Check 2: Lateral deviation (off-path drift)
    local threshold = self._config.deviation_threshold
    if self._corridor_widths then
        local w1 = self._corridor_widths[best_seg - 1]
        local w2 = self._corridor_widths[best_seg]
        if w1 and w2 then
            local corridor_width = w1 + t * (w2 - w1)
            threshold = corridor_width * self._config.deviation_corridor_factor
            threshold = math.max(2.0, threshold)
        end
    end

    if drift > threshold then
        self:_verbose(string.format(
            "Deviation: %.1f yd > threshold %.1f yd%s, repathing",
            drift, threshold,
            self._corridor_widths and " (adaptive)" or " (fixed)"
        ))
        self._last_repath_time = now
        self._deviation_repath_count = self._deviation_repath_count + 1
        self:_unstuck_repath()
    end
end

-- Destination validation ---------------------------------------------------

---Pre-validate that a target is reachable via navmesh without starting movement
---@param target vec3|table Target position (must have x, y, z)
---@param callback fun(reachable: boolean, reason: string|nil, distance: number|nil)
function Movement:validate_destination_reachable(target, callback)
    if not callback then return end
    if not target or not target.x then
        callback(false, "Invalid target", nil)
        return
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        callback(false, "Player not available", nil)
        return
    end

    local dest = vec3.new(target.x, target.y, target.z)
    local start = player:get_position()

    self._nav_client:find_path(start, dest, function(success, data, err)
        if not success or not data then
            callback(false, err or "Pathfinding failed", nil)
            return
        end
        if not data.waypoints or #data.waypoints == 0 then
            callback(false, "No path found", nil)
            return
        end
        callback(true, nil, data.distance or 0)
    end, self:_build_path_opts())
end

return Movement

