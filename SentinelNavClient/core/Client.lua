-- Client.lua
-- Single entry-point facade for SentinelNavClient.
-- Wires HSM + BT + Blackboard + EventBus + Services.

local EventBus             = require("events/EventBus")
local Blackboard           = require("core/Blackboard")
local ConsoleLogger        = require("core/ConsoleLogger")
local StateMachine         = require("core/StateMachine")
local Sensors              = require("core/Sensors")
local Defaults             = require("core/Defaults")
local Helpers              = require("lib/Helpers")
local NavigationService    = require("services/NavigationService")
local MovementService      = require("services/MovementService")
local ObstacleService      = require("services/ObstacleService")
local PathValidationService = require("services/PathValidationService")
local NavigationTree       = require("behaviors/trees/NavigationTree")
local Events               = require("events/Events")

local STATES         = StateMachine.STATES
local NAV_SUBSTATES  = StateMachine.NAV_SUBSTATES
local FAIL_REASONS   = StateMachine.FAIL_REASONS

---@class Client
---@field nav_client NavigationService   HTTP client for SentinelNavServer
---@field movement MovementService       Movement service (simple_movement wrapper)
---@field obstacle ObstacleService       Obstacle detection and avoidance zones
local Client = {}
Client.__index = Client

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

---Create a fully-wired SentinelNavClient instance.
---@param config? table { navigation?, movement?, obstacles? }
---@return Client
function Client:new(config)
    config = config or {}
    local o = setmetatable({}, Client)

    -- Core systems
    o._event_bus  = EventBus:new()
    o._blackboard = Blackboard:new(o._event_bus)
    o._logger     = ConsoleLogger:new(o._event_bus, o._blackboard)
    o._hsm        = StateMachine:new(o._event_bus)
    o._sensors    = Sensors:new(o._blackboard)

    -- Load default config into Blackboard
    local movement_defaults  = Defaults.flat(Defaults.movement)
    local obstacle_defaults  = Defaults.flat(Defaults.obstacles)
    for k, v in pairs(movement_defaults) do
        o._blackboard:set("config." .. k, v)
    end
    for k, v in pairs(obstacle_defaults) do
        o._blackboard:set("config." .. k, v)
    end

    -- Pre-seed path options to avoid empty opts on first tick
    o._blackboard:set("config._path_opts", o:get_path_opts())
    o._blackboard:set("nav.session_id", 0)
    o._blackboard:set("request.next_id", 0)
    o._blackboard:set("request.pending", false)
    o._blackboard:set("request.path_failures", 0)
    o._blackboard:set("repath.failures", 0)
    o._blackboard:clear("path.command_opts")
    o._blackboard:clear("nav.fail_reason")
    o._blackboard:clear("nav.fail_detail")

    -- Services
    o.nav_client  = NavigationService:new(o._event_bus, o._blackboard, config.navigation)
    o.movement    = MovementService:new(o._blackboard, config.movement)
    o.obstacle    = ObstacleService:new(o._event_bus, o._blackboard, config.obstacles)
    o._validation = PathValidationService:new(o._blackboard, config.movement)

    -- Behavior Tree
    o._nav_tree = NavigationTree.create({
        navigation = o.nav_client,
        movement   = o.movement,
        obstacle   = o.obstacle,
        validation = o._validation,
        event_bus  = o._event_bus,
    })

    -- Sync HSM state to Blackboard for BT guards
    o._blackboard:set("hsm.state", "idle")
    o._blackboard:set("hsm.substate", nil)
    o._event_bus:on(Events.STATE_CHANGED, function(data)
        o._blackboard:set("hsm.state", data.to)
        o._blackboard:set("hsm.substate", data.substate_to)
    end)
    o._event_bus:on(Events.WAYPOINT_REACHED, function(data)
        o:_on_waypoint_reached(data)
    end, { owner = o })

    -- Callback for current move_to
    o._callback = nil
    o._route_session = nil
    o._route_plan_token = 0

    -- Old-style event listeners (backward compat)
    o._listeners  = {}
    o._last_state_for_compat = "idle"
    o._stuck_event_fired = false

    return o
end

--------------------------------------------------------------------------------
-- Update loop
--------------------------------------------------------------------------------

---Drive all systems. Call once per frame.
function Client:update()
    -- 1. Poll player state into Blackboard
    self._sensors:update()

    -- 2. If navigating, tick the BT
    if self._hsm:is_moving() then
        self._nav_tree:tick(self._blackboard, 0)
        local reason = self._blackboard:get("nav.fail_reason")
        if reason then
            self:_fail_navigation(reason, self._blackboard:get("nav.fail_detail"))
            return
        end

        -- Check stuck detection
        self:_check_stuck()

        -- Check if BT signaled arrival (all waypoints consumed)
        local waypoints = self._blackboard:get("path.waypoints")
        local index = self._blackboard:get("path.index", 1)
        if waypoints and index > #waypoints then
            self:_on_arrival()
        end

        -- Check if stuck recovery signaled max exceeded
        local max_stuck = self._blackboard:get("config.max_stuck_attempts", 6)
        if self._blackboard:get("stuck.count", 0) > max_stuck then
            self:_fail_navigation("max_stuck_exceeded", "max_stuck_exceeded")
            return
        end
    end

    -- 3. Process pending move (casting deferral resolved)
    if self._blackboard:has("pending.destination") and
       not self._blackboard:get("player.is_casting") then
        local dest = self._blackboard:get("pending.destination")
        local cb   = self._blackboard:get("pending.callback")
        local opts = self._blackboard:get("pending.options")
        self._blackboard:clear("pending.destination")
        self._blackboard:clear("pending.callback")
        self._blackboard:clear("pending.options")
        self:move_to(dest, cb, opts)
    end

    -- 4. Fire old-style events for backward compatibility
    self:_fire_compat_events()
end

--------------------------------------------------------------------------------
-- Movement API
--------------------------------------------------------------------------------

---Move to a target position using navmesh pathfinding.
---@param target vec3
---@param callback? fun(success: boolean, reason: string|nil)
---@param opts? table
function Client:move_to(target, callback, opts)
    self:_clear_route_session()

    -- Handle casting deferral
    if self._blackboard:get("player.is_casting") then
        self:_invalidate_active_requests()
        self.movement:stop()
        self._nav_tree:reset()
        self._blackboard:set("request.path_failures", 0)
        self._blackboard:set("repath.failures", 0)
        self._blackboard:clear("nav.fail_reason")
        self._blackboard:clear("nav.fail_detail")
        self._blackboard:set("pending.destination", target)
        self._blackboard:set("pending.callback", callback)
        self._blackboard:set("pending.options", opts and Helpers.deep_copy(opts) or nil)
        if self._hsm:is_idle() or self._hsm:is_terminal() then
            self._hsm:transition(STATES.NAVIGATING, NAV_SUBSTATES.DEFERRED)
        else
            self._hsm:set_substate(NAV_SUBSTATES.DEFERRED)
        end
        return
    end

    self:_invalidate_active_requests()

    -- Stop any current movement
    self.movement:stop()
    self._nav_tree:reset()

    -- Set up Blackboard state for new navigation
    self._blackboard:set("path.destination", target)
    self._blackboard:clear("path.waypoints")
    self._blackboard:set("path.index", 1)
    self._blackboard:set("stuck.count", 0)
    self._blackboard:set("deviation.count", 0)
    self._blackboard:clear("deviation.last_check")
    self._blackboard:clear("deviation.last_result")
    self._blackboard:clear("stuck.last_position")
    self._blackboard:clear("stuck.last_check")
    self._blackboard:clear("deviation.needs_repath")
    self._blackboard:clear("deviation.eval_tick")
    self._blackboard:clear("deviation.eval_result")
    self._blackboard:set("request.path_failures", 0)
    self._blackboard:set("repath.failures", 0)
    self._blackboard:clear("nav.fail_reason")
    self._blackboard:clear("nav.fail_detail")
    self._blackboard:set("path.command_opts", opts and Helpers.deep_copy(opts) or nil)
    self._callback = callback

    -- Transition HSM
    if self._hsm:is_idle() or self._hsm:is_terminal() then
        self._hsm:transition(STATES.NAVIGATING, NAV_SUBSTATES.AWAITING_PATH)
    else
        -- Already navigating — repath
        self._hsm:set_substate(NAV_SUBSTATES.AWAITING_PATH)
    end
end

---Move directly without pathfinding (short range / emergency).
---@param target vec3
---@param callback? fun(success: boolean, reason: string|nil)
function Client:move_direct(target, callback)
    self:_clear_route_session()
    self:_invalidate_active_requests()
    self.movement:stop()
    self._nav_tree:reset()

    -- Set waypoints directly (single waypoint)
    local waypoints = { target }
    self._blackboard:set("path.destination", target)
    self._blackboard:set("path.waypoints", waypoints)
    self._blackboard:set("path.index", 1)
    self._blackboard:set("stuck.count", 0)
    self._blackboard:set("deviation.count", 0)
    self._blackboard:clear("deviation.last_check")
    self._blackboard:clear("deviation.last_result")
    self._blackboard:clear("deviation.needs_repath")
    self._blackboard:clear("deviation.eval_tick")
    self._blackboard:clear("deviation.eval_result")
    self._blackboard:set("request.path_failures", 0)
    self._blackboard:set("repath.failures", 0)
    self._blackboard:clear("nav.fail_reason")
    self._blackboard:clear("nav.fail_detail")
    self._blackboard:clear("path.command_opts")
    self._callback = callback

    -- Start movement immediately
    self.movement:navigate(waypoints)

    if self._hsm:is_idle() or self._hsm:is_terminal() then
        self._hsm:transition(STATES.NAVIGATING, NAV_SUBSTATES.FOLLOWING_PATH)
    else
        self._hsm:set_substate(NAV_SUBSTATES.FOLLOWING_PATH)
    end
end

---Plan an optimized multi-node route (TSP).
---@param nodes vec3[]
---@param callback? fun(success: boolean, data: table)
---@param opts? table
function Client:plan_route(nodes, callback, opts)
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        if callback then callback(false, nil) end
        return
    end

    self.nav_client:find_route_tsp(nodes, function(ok, data, err)
        if callback then
            if ok and data then
                callback(true, data)
            else
                callback(false, { error = err })
            end
        end
    end, opts)
end

---Plan and execute a TSP route as a tracked route session.
---Callback shape:
---  callback(true, { type = "leg_complete", leg = n, total = n })
---  callback(true, { type = "route_complete", ... })
---  callback(false, { type = "route_failed", error = "..." })
---@param nodes vec3[]
---@param callback? fun(success: boolean, data: table|nil)
---@param opts? table
function Client:start_route(nodes, callback, opts)
    self:stop()
    self._route_plan_token = self._route_plan_token + 1
    local route_plan_token = self._route_plan_token

    self:plan_route(nodes, function(success, data)
        if route_plan_token ~= self._route_plan_token then
            return
        end

        if not success or not data or not data.waypoints or #data.waypoints == 0 then
            if callback then
                callback(false, data or { type = "route_failed", error = "route planning failed" })
            end
            return
        end

        local total_legs = 0
        if data.leg_distances and #data.leg_distances > 0 then
            total_legs = #data.leg_distances
        elseif data.leg_boundaries and #data.leg_boundaries > 1 then
            total_legs = #data.leg_boundaries - 1
        elseif nodes and #nodes > 1 then
            total_legs = #nodes - 1
        end

        self._route_session = {
            active = true,
            nodes = Helpers.deep_copy(nodes),
            options = opts and Helpers.deep_copy(opts) or nil,
            callback = callback,
            visit_order = Helpers.deep_copy(data.visit_order or {}),
            leg_boundaries = Helpers.deep_copy(data.leg_boundaries or {}),
            leg_distances = Helpers.deep_copy(data.leg_distances or {}),
            current_leg = 1,
            total_legs = total_legs,
            total_distance = data.total_distance or 0,
        }
        self._blackboard:set("route.active", true)
        self._blackboard:set("route.current_leg", 1)
        self._blackboard:set("route.total_legs", total_legs)

        self:follow_path(data.waypoints, function(ok, reason)
            local route_cb = callback
            local total_distance = data.total_distance or 0
            local visit_order = data.visit_order
            self:_clear_route_session()

            if route_cb then
                if ok then
                    route_cb(true, {
                        type = "route_complete",
                        total_distance = total_distance,
                        visit_order = visit_order,
                    })
                else
                    route_cb(false, {
                        type = "route_failed",
                        error = tostring(reason or "route execution failed"),
                    })
                end
            end
        end, { preserve_route_session = true })
    end, opts)
end

---Follow a pre-computed waypoint path (no pathfinding request).
---@param waypoints vec3[]
---@param callback? fun(success: boolean, reason: string|nil)
---@param opts? table { preserve_route_session?: boolean }
function Client:follow_path(waypoints, callback, opts)
    if not waypoints or #waypoints == 0 then
        if callback then callback(false, "empty path") end
        return
    end

    opts = opts or {}
    if not opts.preserve_route_session then
        self:_clear_route_session()
    end

    self:_invalidate_active_requests()
    self.movement:stop()
    self._nav_tree:reset()

    self._blackboard:set("path.destination", waypoints[#waypoints])
    self._blackboard:set("path.waypoints", waypoints)
    self._blackboard:set("path.index", 1)
    self._blackboard:set("stuck.count", 0)
    self._blackboard:set("deviation.count", 0)
    self._blackboard:clear("deviation.last_check")
    self._blackboard:clear("deviation.last_result")
    self._blackboard:clear("deviation.needs_repath")
    self._blackboard:clear("deviation.eval_tick")
    self._blackboard:clear("deviation.eval_result")
    self._blackboard:set("request.path_failures", 0)
    self._blackboard:set("repath.failures", 0)
    self._blackboard:clear("nav.fail_reason")
    self._blackboard:clear("nav.fail_detail")
    self._blackboard:clear("path.command_opts")
    self._callback = callback

    self.movement:navigate(waypoints)

    if self._hsm:is_idle() or self._hsm:is_terminal() then
        self._hsm:transition(STATES.NAVIGATING, NAV_SUBSTATES.FOLLOWING_PATH)
    else
        self._hsm:set_substate(NAV_SUBSTATES.FOLLOWING_PATH)
    end
end

---Re-request path from current position to current destination.
---@param reason? string
function Client:replan(reason)
    if not self._hsm:is_moving() then return end
    if self._route_session and self._route_session.active then
        self:_replan_route(reason)
        return
    end

    local dest = self._blackboard:get("path.destination")
    if not dest then return end

    self:_invalidate_active_requests()

    -- Clear current path to trigger RequestPath in BT
    self._blackboard:clear("path.waypoints")
    self._blackboard:set("path.index", 1)
    self._blackboard:clear("deviation.needs_repath")
    self._blackboard:clear("nav.fail_reason")
    self._blackboard:clear("nav.fail_detail")

    -- Reset BT so HandleNavigation Sequence re-evaluates EnsurePath
    self._nav_tree:reset()

    self._hsm:set_substate(NAV_SUBSTATES.AWAITING_PATH)
end

---Pre-validate whether a destination is reachable.
---@param target vec3
---@param callback fun(reachable: boolean, reason: string|nil, distance: number|nil)
function Client:validate_destination(target, callback)
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        if callback then callback(false, "no player", nil) end
        return
    end

    self.nav_client:find_path(player:get_position(), target, function(ok, data, err)
        if ok and data and data.waypoints and #data.waypoints > 0 then
            callback(true, nil, data.distance)
        else
            callback(false, err or "unreachable", nil)
        end
    end)
end

---Stop all movement and reset to idle.
function Client:stop()
    self._route_plan_token = self._route_plan_token + 1
    self:_invalidate_active_requests()
    self.movement:stop()
    self._blackboard:clear("path.destination")
    self._blackboard:clear("path.waypoints")
    self._blackboard:clear("path.command_opts")
    self._blackboard:clear("pending.destination")
    self._blackboard:clear("pending.callback")
    self._blackboard:clear("pending.options")
    self._blackboard:set("stuck.count", 0)
    self._blackboard:clear("deviation.last_check")
    self._blackboard:clear("deviation.last_result")
    self._blackboard:clear("deviation.needs_repath")
    self._blackboard:clear("deviation.eval_tick")
    self._blackboard:clear("deviation.eval_result")
    self._blackboard:set("request.path_failures", 0)
    self._blackboard:set("repath.failures", 0)
    self._blackboard:clear("nav.fail_reason")
    self._blackboard:clear("nav.fail_detail")
    self:_clear_route_session()
    self._nav_tree:reset()

    if not self._hsm:is_idle() then
        self._hsm:reset()
    end

    self._callback = nil
end

---Stop movement, clear obstacles, nil references.
function Client:destroy()
    self:stop()
    self.obstacle:clear()
    if self._logger then
        self._logger:destroy()
        self._logger = nil
    end
    self._event_bus:clear()
    self._blackboard:clear()
    self._listeners = {}
end

--------------------------------------------------------------------------------
-- State queries
--------------------------------------------------------------------------------

---@return string "idle"|"navigating"|"arrived"|"failed"
function Client:get_state()
    return self._hsm:get_state()
end

---@return string dot-joined full state string
function Client:get_full_state()
    return self._hsm:get_full_state()
end

---@return boolean
function Client:is_moving()
    return self._hsm:is_moving()
end

---@return vec3|nil
function Client:get_destination()
    return self._blackboard:get("path.destination")
end

---@return vec3[]|nil
function Client:get_current_path()
    return self._blackboard:get("path.waypoints")
end

---@return number
function Client:get_path_index()
    return self._blackboard:get("path.index", 1)
end

---@return table
function Client:get_progress()
    local waypoints = self._blackboard:get("path.waypoints")
    local index = self._blackboard:get("path.index", 1)
    local progress
    if not waypoints or #waypoints == 0 then
        progress = { percent = 0, waypoints_remaining = 0, total_waypoints = 0, current_index = 1 }
    else
        progress = {
            percent = math.min(1, index / #waypoints),
            waypoints_remaining = math.max(0, #waypoints - index),
            total_waypoints = #waypoints,
            current_index = index,
        }
    end

    if self._route_session and self._route_session.active then
        progress.route_mode = true
        progress.current_leg = self._route_session.current_leg or 1
        progress.total_legs = self._route_session.total_legs or 0
    end
    return progress
end

---@return number[]|nil
function Client:get_corridor_widths()
    return self._blackboard:get("path.corridor_widths")
end

---@return table|nil
function Client:get_route_progress()
    if not self._route_session or not self._route_session.active then
        return nil
    end
    return {
        active = true,
        current_leg = self._route_session.current_leg or 1,
        total_legs = self._route_session.total_legs or 0,
        total_distance = self._route_session.total_distance or 0,
        visit_order = Helpers.deep_copy(self._route_session.visit_order or {}),
    }
end

--------------------------------------------------------------------------------
-- Server queries (delegates to NavigationService)
--------------------------------------------------------------------------------

---@return boolean
function Client:is_server_available()
    return self._blackboard:get("server.connected", false)
end

---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
function Client:health_check(callback)
    self.nav_client:health_check(callback)
end

---@param pos vec3
---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
function Client:get_height(pos, callback)
    self.nav_client:get_height(pos, callback)
end

---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
function Client:get_player_height(callback)
    local me = core.object_manager.get_local_player()
    if not me then
        if callback then callback(false, nil, "No local player") end
        return
    end
    self.nav_client:get_height(me:get_position(), callback)
end

---@param pos vec3
---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
---@param opts? table
function Client:get_all_heights(pos, callback, opts)
    self.nav_client:get_all_heights(pos, callback, opts)
end

---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
---@param opts? table
function Client:get_player_all_heights(callback, opts)
    local me = core.object_manager.get_local_player()
    if not me then
        if callback then callback(false, nil, "No local player") end
        return
    end
    local player_pos = me:get_position()
    opts = opts or {}
    if opts.filter_unreachable and not opts.from_pos then
        opts.from_pos = player_pos
    end
    self.nav_client:get_all_heights(player_pos, callback, opts)
end

---Get current pathfinding options from config.
---@param extra? table Additional opts to merge
---@return table
function Client:get_path_opts(extra)
    local bb = self._blackboard
    local opts = {
        optimize              = bb:get("config.optimize", true),
        allow_partial         = bb:get("config.allow_partial", true),
        anti_detection        = bb:get("config.anti_detection", false),
        max_deviation         = bb:get("config.max_deviation", 3.0),
        filter_ground         = bb:get("config.filter_ground", 1.0),
        filter_water          = bb:get("config.filter_water", 10.0),
        filter_lava           = bb:get("config.filter_lava", 100.0),
        wall_clearance        = bb:get("config.wall_clearance", 0),
        string_pull_deviation = bb:get("config.string_pull_deviation"),
        string_pull_heading   = bb:get("config.string_pull_heading"),
        string_pull_wall_dist = bb:get("config.string_pull_wall_dist"),
        densify_segment_length = bb:get("config.densify_segment_length"),
    }
    if extra then
        for k, v in pairs(extra) do
            opts[k] = v
        end
    end
    return opts
end

---Get current corridor pathfinding options from config.
---@param extra? table Additional opts to merge
---@return table
function Client:get_corridor_opts(extra)
    local bb = self._blackboard
    local opts = self:get_path_opts()
    opts.use_corridor = bb:get("config.use_corridor_indoor", true)
    opts.corridor_probe_dist = bb:get("config.corridor_probe_dist", 15.0)
    if extra then
        for k, v in pairs(extra) do
            opts[k] = v
        end
    end
    return opts
end

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

---Distribute config updates to underlying modules.
---@param overrides table { movement?: table, obstacles?: table, navigation?: table }
function Client:update_config(overrides)
    if not overrides then return end

    -- Write movement config to Blackboard for BT nodes
    if overrides.movement then
        for k, v in pairs(overrides.movement) do
            self._blackboard:set("config." .. k, v)
        end
        self.movement:update_config(overrides.movement)
        self._validation:update_config(overrides.movement)
        -- Pre-build path opts so BT actions can read them directly
        self._blackboard:set("config._path_opts", self:get_path_opts())
    end

    -- Write obstacle config to Blackboard and update service
    if overrides.obstacles then
        for k, v in pairs(overrides.obstacles) do
            self._blackboard:set("config." .. k, v)
        end
        self.obstacle:update_config(overrides.obstacles)
    end

    -- Update navigation service
    if overrides.navigation then
        self.nav_client:update_config(overrides.navigation)
    end
end

--------------------------------------------------------------------------------
-- Event system (backward-compatible old-style + new EventBus)
--------------------------------------------------------------------------------

---Register a listener for an event (backward-compatible).
---Events: "state_change", "arrived", "stuck", "failed"
---@param event string
---@param callback function
function Client:on(event, callback)
    if not self._listeners[event] then
        self._listeners[event] = {}
    end
    local list = self._listeners[event]
    list[#list + 1] = callback
end

---Remove a listener (backward-compatible).
---@param event string
---@param callback function
function Client:off(event, callback)
    local list = self._listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
        end
    end
end

---Get the EventBus for new-style subscriptions.
---@return table EventBus
function Client:get_event_bus()
    return self._event_bus
end

---Get the Blackboard for advanced access.
---@return table Blackboard
function Client:get_blackboard()
    return self._blackboard
end

--------------------------------------------------------------------------------
-- Internal: route session
--------------------------------------------------------------------------------

---@private
function Client:_clear_route_session()
    if self._route_session then
        self._route_session.active = false
    end
    self._route_session = nil
    self._blackboard:clear("route.active")
    self._blackboard:clear("route.current_leg")
    self._blackboard:clear("route.total_legs")
end

---@private
---@param data table
function Client:_on_waypoint_reached(data)
    -- Waypoint progress means deviation repaths were productive; reset streak budget.
    self._blackboard:set("deviation.count", 0)

    local rs = self._route_session
    if not rs or not rs.active then
        return
    end

    local boundaries = rs.leg_boundaries
    if not boundaries or #boundaries < 2 then
        return
    end

    local idx = tonumber(data and data.index) or self._blackboard:get("path.index", 1)
    local total_legs = rs.total_legs or math.max(0, #boundaries - 1)

    while rs.current_leg <= total_legs do
        local next_boundary = boundaries[rs.current_leg + 1]
        if not next_boundary or idx < next_boundary then
            break
        end

        local completed_leg = rs.current_leg
        rs.current_leg = completed_leg + 1
        self._blackboard:set("route.current_leg", math.min(rs.current_leg, total_legs))

        local payload = {
            leg = completed_leg,
            total = total_legs,
            waypoint_index = idx,
            distance = rs.leg_distances and rs.leg_distances[completed_leg] or nil,
        }
        self._event_bus:emit(Events.LEG_COMPLETED, payload)

        if rs.callback then
            pcall(rs.callback, true, {
                type = "leg_complete",
                leg = payload.leg,
                total = payload.total,
                distance = payload.distance,
            })
        end
    end
end

---@private
---@param reason? string
function Client:_replan_route(reason)
    local rs = self._route_session
    if not rs or not rs.active then
        return
    end

    local remaining_nodes = {}
    if rs.visit_order and #rs.visit_order > 0 and rs.nodes then
        for i = rs.current_leg, #rs.visit_order do
            local node_idx = rs.visit_order[i]
            if node_idx and rs.nodes[node_idx] then
                remaining_nodes[#remaining_nodes + 1] = rs.nodes[node_idx]
            end
        end
    elseif rs.nodes then
        for i = rs.current_leg, #rs.nodes do
            remaining_nodes[#remaining_nodes + 1] = rs.nodes[i]
        end
    end

    local route_cb = rs.callback
    local route_opts = rs.options and Helpers.deep_copy(rs.options) or nil

    self:stop()
    if #remaining_nodes >= 2 then
        self:start_route(remaining_nodes, route_cb, route_opts)
    elseif route_cb then
        route_cb(false, {
            type = "route_failed",
            error = "too few nodes remaining to replan",
        })
    end
end

--------------------------------------------------------------------------------
-- Internal: navigation failure + request lifecycle
--------------------------------------------------------------------------------

---@private
function Client:_invalidate_active_requests()
    local sid = self._blackboard:get("nav.session_id", 0) + 1
    self._blackboard:set("nav.session_id", sid)
    self._blackboard:set("request.pending", false)
    self._blackboard:clear("request.result")
    self._blackboard:clear("request.error")
    self._blackboard:clear("request.active_id")
    self._blackboard:clear("request.active_kind")
    self._blackboard:clear("request.retry_at")
end

---@private
---@param reason string|nil
---@param detail string|nil
---@return string
function Client:_normalize_fail_reason(reason, detail)
    if reason == FAIL_REASONS.UNREACHABLE
        or reason == FAIL_REASONS.SERVER_TIMEOUT
        or reason == FAIL_REASONS.MAX_STUCK_EXCEEDED
        or reason == FAIL_REASONS.MAX_REPATH_EXCEEDED then
        return reason
    end

    local msg = string.lower(tostring(detail or reason or ""))
    if msg:find("timeout", 1, true) or msg:find("http 0", 1, true) or msg:find("http 5", 1, true) then
        return FAIL_REASONS.SERVER_TIMEOUT
    end
    return FAIL_REASONS.UNREACHABLE
end

---@private
---@param reason string|nil
---@param detail string|nil
function Client:_fail_navigation(reason, detail)
    local normalized = self:_normalize_fail_reason(reason, detail)
    self._blackboard:set("nav.fail_reason", normalized)
    self._blackboard:set("nav.fail_detail", detail or normalized)
    self._blackboard:clear("path.command_opts")

    self:_invalidate_active_requests()
    self.movement:stop()

    if self._hsm:get_state() ~= STATES.FAILED then
        self._hsm:transition(STATES.FAILED, nil, {
            fail_reason = normalized,
            destination = self._blackboard:get("path.destination"),
        })
    end

    if self._callback then
        local cb = self._callback
        self._callback = nil
        pcall(cb, false, detail or normalized)
    end

    if self._route_session and self._route_session.active then
        self:_clear_route_session()
    end
end

--------------------------------------------------------------------------------
-- Internal: stuck detection
--------------------------------------------------------------------------------

---@private
function Client:_check_stuck()
    -- Don't check stuck if movement hasn't actually started yet
    if not self.movement:is_moving() then return end

    local now = self._blackboard:get("_time", 0)
    local interval = self._blackboard:get("config.stuck_check_interval", 1.0)
    local last_check = self._blackboard:get("stuck.last_check", 0)
    if now - last_check < interval then return end

    self._blackboard:set("stuck.last_check", now)

    local pos = self._blackboard:get("player.position")
    local last_pos = self._blackboard:get("stuck.last_position")

    -- First check after movement starts — seed last_position without evaluating
    if not last_pos or not pos then
        self._blackboard:set("stuck.last_position", pos)
        return
    end

    if pos then
        local dist = Helpers.distance_3d(pos, last_pos)
        local min_dist = self._blackboard:get("config.stuck_distance_min", 1.0)

        if dist < min_dist then
            local count = self._blackboard:get("stuck.count", 0) + 1
            self._blackboard:set("stuck.count", count)

            -- Transition to recovering if not already
            local substate = self._hsm:get_substate()
            if substate ~= NAV_SUBSTATES.RECOVERING then
                self._hsm:set_substate(NAV_SUBSTATES.RECOVERING)
            end

            self._event_bus:emit(Events.STUCK_DETECTED, {
                position = pos,
                attempt = count,
                max_attempts = self._blackboard:get("config.max_stuck_attempts", 6),
            })
        else
            -- Moved enough, reset stuck count
            if self._blackboard:get("stuck.count", 0) > 0 then
                self._event_bus:emit(Events.STUCK_RECOVERED, { position = pos })
                self._blackboard:set("stuck.count", 0)
                -- Return to following_path if currently recovering
                local substate = self._hsm:get_substate()
                if substate == NAV_SUBSTATES.RECOVERING then
                    self._hsm:set_substate(NAV_SUBSTATES.FOLLOWING_PATH)
                end
            end
        end
    end

    self._blackboard:set("stuck.last_position", pos)
end

--------------------------------------------------------------------------------
-- Internal: arrival handling
--------------------------------------------------------------------------------

---@private
function Client:_on_arrival()
    local dest = self._blackboard:get("path.destination")
    self.movement:stop()

    self._hsm:transition(STATES.ARRIVED, nil, {
        event_data = { destination = dest },
    })

    if self._callback then
        pcall(self._callback, true)
        self._callback = nil
    end
end

--------------------------------------------------------------------------------
-- Internal: backward-compatible event firing
--------------------------------------------------------------------------------

---@private
function Client:_fire_compat_events()
    local new_state = self._hsm:get_state()
    if new_state ~= self._last_state_for_compat then
        self:_fire("state_change", { from = self._last_state_for_compat, to = new_state })
        if new_state == "arrived" then
            self:_fire("arrived")
        elseif new_state == "failed" then
            self:_fire("failed")
        end
        self._last_state_for_compat = new_state
    end

    -- Map "recovering" substate to old "stuck" event
    local substate = self._hsm:get_substate()
    if new_state == "navigating" and substate == "recovering" then
        -- Only fire once per stuck episode
        if not self._stuck_event_fired then
            self:_fire("stuck")
            self._stuck_event_fired = true
        end
    else
        self._stuck_event_fired = false
    end
end

---@private
function Client:_fire(event, data)
    local list = self._listeners[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], data)
        if not ok then
            core.log_error("[SentinelNavClient] Event '" .. event .. "' handler error: " .. tostring(err))
        end
    end
end

return Client
