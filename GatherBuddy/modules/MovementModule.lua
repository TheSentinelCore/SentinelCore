-- MovementModule.lua
-- Path following and stuck recovery for GatherBuddy
-- Uses NavigationClient for pathfinding, simple_movement for locomotion

local vec3 = require("common/geometry/vector_3")
local simple_movement = require("common/utility/simple_movement")

-- State constants
local S_IDLE = "idle"
local S_REQUESTING = "requesting_path"
local S_MOVING = "moving"
local S_STUCK = "stuck"
local S_ARRIVED = "arrived"
local S_FAILED = "failed"

-- Default configuration
local DEFAULT_CONFIG = {
    waypoint_tolerance   = 3.0,
    final_tolerance      = 1.5,
    stuck_check_interval = 2.0,
    stuck_distance_min   = 1.0,
    max_stuck_attempts   = 5,
    path_check_interval  = 8.0,
    smoothing            = "chaikin",
    optimize             = true,
    anti_detection       = false,
    max_deviation        = 3.0,
    allow_partial        = true,
    smooth_iterations    = 2,
    smooth_samples       = 10,
    smooth_ratio         = 0.75,
    min_corner_angle     = 0,
    keep_originals       = false,
    filter_ground        = 1.0,
    filter_water         = 10.0,
    filter_lava          = 100.0,
    use_corridor_indoor  = true,
    corridor_probe_dist  = 15.0,
    wall_clearance       = 0,
}

-- Class ------------------------------------------------------------------

---@class MovementModule
---@field private _nav_client NavigationClient
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
---@field _path_index number
local MovementModule = {}
MovementModule.__index = MovementModule

---Create a new MovementModule
---@param nav_client NavigationClient Navigation client instance
---@param config? table Override default config values
---@return MovementModule
function MovementModule:new(nav_client, config)
    if not nav_client then
        error("MovementModule requires a NavigationClient instance")
    end

    local o = setmetatable({}, MovementModule)

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

    -- Route mode
    o._route_data = nil

    -- Corridor data
    o._corridor_widths = nil

    -- Compatibility: consumers read _path_index directly
    o._path_index = 1

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
function MovementModule:_set_state(new_state)
    if self._state == new_state then return end
    core.log("[Movement] State: " .. self._state .. " -> " .. new_state)
    self._state = new_state
end

---Get current state
---@return string
function MovementModule:get_state()
    return self._state
end

---Check if actively moving or requesting a path
---@return boolean
function MovementModule:is_moving()
    return self._state == S_MOVING or self._state == S_REQUESTING
end

---Get current waypoint path
---@return vec3[]|nil
function MovementModule:get_current_path()
    return self._current_path
end

---Get current movement destination
---@return vec3|nil
function MovementModule:get_destination()
    return self._destination
end

---Update config values at runtime (e.g., from UI settings)
---@param overrides table Key-value pairs to merge into config
function MovementModule:update_config(overrides)
    if not overrides then return end
    for k, v in pairs(overrides) do
        self._config[k] = v
    end
end

---Build opts table for find_path from current config
---@param extra? table Additional opts to merge (e.g., map_id from caller)
---@return table
function MovementModule:_build_path_opts(extra)
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
function MovementModule:_build_corridor_opts(extra)
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
function MovementModule:_should_use_corridor()
    if not self._config.use_corridor_indoor then return false end
    local NavClient = require("modules/NavigationClient")
    return NavClient.is_indoor()
end

---Compute the minimum corridor width from stored corridor data
---@return number|nil min_width Minimum width in yards, or nil if no data
function MovementModule:_compute_min_corridor_width()
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
function MovementModule:get_corridor_widths()
    return self._corridor_widths
end

---Get progress information
---@return table { state, destination?, distance_remaining?, path_index?, path_count?, current_leg?, total_legs?, route_mode? }
function MovementModule:get_progress()
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
function MovementModule:stop()
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
    self._path_index = 1
    simple_movement:set_threshold(self._config.waypoint_tolerance)
    simple_movement:set_final_threshold(self._config.final_tolerance)
end

-- Update loop ------------------------------------------------------------

---Call every frame to drive movement
function MovementModule:update()
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
function MovementModule:move_to(target, callback, opts)
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

    -- Reset stuck detection
    self._stuck_count = 0
    self._last_stuck_time = core.time()
    self._last_stuck_pos = player:get_position()
    self._path_check_time = core.time()
    self._unstuck_phase = nil

    -- Defer if casting
    if player:is_casting_spell() or player:is_channelling_spell() then
        core.log("[Movement] Player casting, deferring movement")
        self:_set_state(S_REQUESTING)
        self._pending_move = { target = target, callback = callback, opts = opts }
        return
    end

    -- Direct movement (no pathfinding)
    if opts.use_navmesh == false then
        self:_start_movement({ target })
        return
    end

    -- Request path from NavBuddy
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

        -- Store corridor data and adjust tolerance for indoor paths
        if use_corridor and data.corridor_widths then
            self._corridor_widths = data.corridor_widths
            local min_width = self:_compute_min_corridor_width()
            if min_width and min_width < self._config.waypoint_tolerance then
                local indoor_tolerance = math.max(1.0, min_width * 0.4)
                simple_movement:set_threshold(indoor_tolerance)
                simple_movement:set_final_threshold(math.min(self._config.final_tolerance, indoor_tolerance))
                core.log("[Movement] Corridor: min width " .. string.format("%.1f", min_width)
                    .. " yd, tolerance -> " .. string.format("%.1f", indoor_tolerance))
            end
        else
            self._corridor_widths = nil
        end

        local label = use_corridor and "Corridor path" or "Path"
        core.log("[Movement] " .. label .. " received: " .. #data.waypoints .. " waypoints, "
            .. string.format("%.1f", data.distance or 0) .. " yards")

        self:_start_movement(data.waypoints)
    end

    if use_corridor then
        self._nav_client:find_path_corridor(start_pos, target, on_path,
            self:_build_corridor_opts({ map_id = opts.map_id }))
    else
        self._nav_client:find_path(start_pos, target, on_path,
            self:_build_path_opts({ map_id = opts.map_id }))
    end
end

---Move directly to target without pathfinding (short range / emergency)
---@param target vec3
---@param callback? fun(success: boolean, reason: string|nil)
function MovementModule:move_direct(target, callback)
    self:move_to(target, callback, { use_navmesh = false })
end

---Start movement with a given waypoint list
---@param waypoints vec3[]
function MovementModule:_start_movement(waypoints)
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
        core.log("[Movement] Player still casting, re-deferring")
        self._pending_move = {
            target = self._destination,
            callback = self._callback,
            opts = { use_navmesh = false },
        }
        -- Store waypoints so deferred path uses them directly
        self._current_path = waypoints
        return
    end

    self._current_path = waypoints
    self:_set_state(S_MOVING)
    simple_movement:navigate(waypoints)
    core.log("[Movement] Navigating " .. #waypoints .. " waypoints")
end

---Handle arrival at destination
function MovementModule:_on_arrival()
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
    simple_movement:set_threshold(self._config.waypoint_tolerance)
    simple_movement:set_final_threshold(self._config.final_tolerance)
    self:_set_state(S_IDLE)
end

-- Stuck detection & recovery ---------------------------------------------

---Check if player is stuck (called on interval while moving)
---@param player game_object
function MovementModule:_check_stuck(player)
    local now = core.time()
    if now - self._last_stuck_time < self._config.stuck_check_interval then return end
    self._last_stuck_time = now

    local pos = player:get_position()

    if not self._last_stuck_pos then
        self._last_stuck_pos = pos
        return
    end

    local moved = pos:dist_to(self._last_stuck_pos)

    if simple_movement:is_moving() and moved < self._config.stuck_distance_min then
        self._stuck_count = self._stuck_count + 1
        core.log_warning("[Movement] Stuck #" .. self._stuck_count
            .. " (moved " .. string.format("%.2f", moved) .. " yards)")
        self:_handle_stuck()
    else
        if self._stuck_count > 0 then
            core.log("[Movement] Unstuck (moved " .. string.format("%.2f", moved) .. " yards)")
        end
        self._stuck_count = 0
    end

    self._last_stuck_pos = pos
end

---Apply recovery strategy based on stuck count
function MovementModule:_handle_stuck()
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
        self:_unstuck_strafe()
    elseif self._stuck_count == 3 then
        self:_unstuck_backward()
    else
        self:_unstuck_repath()
    end
end

---Strategy 1: Jump
function MovementModule:_unstuck_jump()
    core.log("[Movement] Unstuck: jump")
    core.input.jump()
end

---Strategy 2: Random strafe + jump
function MovementModule:_unstuck_strafe()
    local dir = math.random() > 0.5 and "left" or "right"
    core.log("[Movement] Unstuck: strafe " .. dir)
    self._unstuck_phase = "strafe"
    self._unstuck_timer = core.time()
    simple_movement:strafe(dir)
end

---Strategy 3: Backward + jump
function MovementModule:_unstuck_backward()
    core.log("[Movement] Unstuck: backward")
    self._unstuck_phase = "backward"
    self._unstuck_timer = core.time()
    core.input.move_backward_start()
end

---Strategy 4: Request fresh path from current position
function MovementModule:_unstuck_repath()
    if not self._destination then
        core.log_warning("[Movement] No destination for repath")
        return
    end
    core.log("[Movement] Unstuck: repath")
    simple_movement:stop()

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
        core.log("[Movement] Repath OK: " .. #data.waypoints .. " waypoints")
        self._stuck_count = 0
        self:_start_movement(data.waypoints)
    end

    if self:_should_use_corridor() then
        self._nav_client:find_path_corridor(pos, self._destination, on_repath,
            self:_build_corridor_opts())
    else
        self._nav_client:find_path(pos, self._destination, on_repath,
            self:_build_path_opts())
    end
end

---Process timed unstuck actions (called in update)
function MovementModule:_process_unstuck_action()
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
function MovementModule:plan_route(nodes, callback, opts)
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
    end, {
        map_id = opts.map_id,
        start_pos = player:get_position(),
        return_to_start = opts.return_to_start,
    })
end

---Check if we've crossed into a new route leg
function MovementModule:_check_route_progress()
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
        core.log("[Movement] Route leg " .. prev_leg .. "/" .. rd.total_legs .. " completed")

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
function MovementModule:replan(reason)
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
function MovementModule:_check_path_validity(player)
    local now = core.time()
    if now - self._path_check_time < self._config.path_check_interval then return end
    self._path_check_time = now

    local remaining = simple_movement:get_remaining_waypoints()
    if not remaining or #remaining < 3 then return end

    local pos = player:get_position()
    self._nav_client:check_path(pos, remaining, function(ok, data, err)
        if not ok then return end
        if data and not data.valid and self._destination then
            core.log_warning("[Movement] Path invalid at segment "
                .. tostring(data.first_invalid_segment) .. ", repathing")
            self:_unstuck_repath()
        end
    end)
end

-- Destination validation ---------------------------------------------------

---Pre-validate that a target is reachable via navmesh without starting movement
---@param target vec3|table Target position (must have x, y, z)
---@param callback fun(reachable: boolean, reason: string|nil, distance: number|nil)
function MovementModule:validate_destination_reachable(target, callback)
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

return MovementModule
