-- Facade.lua
-- Single entry-point facade for NavLib: creates, wires, and drives all modules.

local Navigation = require("core/Navigation")
local Movement   = require("core/Movement")
local Obstacle   = require("core/Obstacle")

---@class Facade
---@field nav_client Navigation   Escape-hatch: raw HTTP client
---@field movement   Movement     Escape-hatch: path-following module
---@field obstacle   Obstacle     Escape-hatch: obstacle detection module
local Facade = {}
Facade.__index = Facade

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

---Create a fully-wired NavLib instance.
---@param config? table { navigation?, movement?, obstacles? }
---@return Facade
function Facade:new(config)
    config = config or {}
    local o = setmetatable({}, Facade)

    -- 1. Create modules
    o.nav_client = Navigation:new(config.navigation)
    o.movement   = Movement:new(o.nav_client, config.movement)
    o.obstacle   = Obstacle:new(config.obstacles)

    -- 2. Wire obstacle into movement (the step consumers always forget)
    o.movement:set_obstacle_module(o.obstacle)

    -- 3. Event system
    o._listeners  = {}
    o._last_state = "idle"

    return o
end

--------------------------------------------------------------------------------
-- Update loop
--------------------------------------------------------------------------------

---Drive all modules. Call once per frame.
function Facade:update()
    self.obstacle:update()
    self.movement:update()

    -- Detect state transitions and fire events
    local new_state = self.movement:get_state()
    if new_state ~= self._last_state then
        self:_fire("state_change", { from = self._last_state, to = new_state })
        if new_state == "arrived" then
            self:_fire("arrived")
        elseif new_state == "stuck" then
            self:_fire("stuck")
        elseif new_state == "failed" then
            self:_fire("failed")
        end
        self._last_state = new_state
    end
end

--------------------------------------------------------------------------------
-- Movement (delegates to Movement)
--------------------------------------------------------------------------------

---Move to a target position using navmesh pathfinding.
---@param target vec3
---@param callback? fun(success: boolean, reason: string|nil)
---@param opts? table
function Facade:move_to(target, callback, opts)
    self.movement:move_to(target, callback, opts)
end

---Move directly without pathfinding (short range / emergency).
---@param target vec3
---@param callback? fun(success: boolean, reason: string|nil)
function Facade:move_direct(target, callback)
    self.movement:move_direct(target, callback)
end

---Plan an optimized multi-node route (TSP).
---@param nodes vec3[]
---@param callback? fun(success: boolean, data: table)
---@param opts? table
function Facade:plan_route(nodes, callback, opts)
    self.movement:plan_route(nodes, callback, opts)
end

---Follow a pre-computed waypoint path (no pathfinding request).
---@param waypoints vec3[]
---@param callback? fun(success: boolean, reason: string|nil)
function Facade:follow_path(waypoints, callback)
    self.movement:follow_path(waypoints, callback)
end

---Re-request path from current position to current destination.
---@param reason? string
function Facade:replan(reason)
    self.movement:replan(reason)
end

---Pre-validate whether a destination is reachable.
---@param target vec3
---@param callback fun(reachable: boolean, reason: string|nil, distance: number|nil)
function Facade:validate_destination(target, callback)
    self.movement:validate_destination_reachable(target, callback)
end

---Stop all movement and reset to idle.
function Facade:stop()
    self.movement:stop()
end

---Stop movement, clear obstacle zones, nil references.
function Facade:destroy()
    self.movement:stop()
    self.obstacle:clear()
    self._listeners = {}
end

--------------------------------------------------------------------------------
-- State queries (delegates to Movement)
--------------------------------------------------------------------------------

---@return string
function Facade:get_state()
    return self.movement:get_state()
end

---@return boolean
function Facade:is_moving()
    return self.movement:is_moving()
end

---@return vec3|nil
function Facade:get_destination()
    return self.movement:get_destination()
end

---@return vec3[]|nil
function Facade:get_current_path()
    return self.movement:get_current_path()
end

---@return number
function Facade:get_path_index()
    return self.movement:get_path_index()
end

---@return table
function Facade:get_progress()
    return self.movement:get_progress()
end

---@return number[]|nil
function Facade:get_corridor_widths()
    return self.movement:get_corridor_widths()
end

--------------------------------------------------------------------------------
-- Server queries (delegates to Navigation)
--------------------------------------------------------------------------------

---@return boolean
function Facade:is_server_available()
    return self.nav_client:is_available()
end

---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
function Facade:health_check(callback)
    self.nav_client:health_check(callback)
end

---Get navmesh height at a specific position.
---@param pos vec3
---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
function Facade:get_height(pos, callback)
    self.nav_client:get_height(pos, callback)
end

---Get navmesh height at the local player's current position.
---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
function Facade:get_player_height(callback)
    local me = core.object_manager.get_local_player()
    if not me then
        if callback then callback(false, nil, "No local player") end
        return
    end
    self.nav_client:get_height(me:get_position(), callback)
end

---Get all navmesh heights at a specific XY position (multi-level structures).
---@param pos vec3
---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
---@param opts? table { filter_unreachable?, from_pos?, xy_extent?, z_extent?, max_polys?, cluster_tolerance? }
function Facade:get_all_heights(pos, callback, opts)
    self.nav_client:get_all_heights(pos, callback, opts)
end

---Get all navmesh heights at the local player's current position.
---When opts.filter_unreachable is true, automatically sets from_pos to player position.
---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
---@param opts? table { filter_unreachable?, xy_extent?, z_extent?, max_polys?, cluster_tolerance? }
function Facade:get_player_all_heights(callback, opts)
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

---Get current pathfinding options from config (for callers that bypass Movement).
---@param extra? table Additional opts to merge
---@return table
function Facade:get_path_opts(extra)
    return self.movement:_build_path_opts(extra)
end

---Get current corridor pathfinding options from config.
---@param extra? table Additional opts to merge
---@return table
function Facade:get_corridor_opts(extra)
    return self.movement:_build_corridor_opts(extra)
end

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

---Distribute config updates to underlying modules.
---@param overrides table { movement?: table, obstacles?: table, navigation?: table }
function Facade:update_config(overrides)
    if not overrides then return end
    if overrides.movement then
        self.movement:update_config(overrides.movement)
    end
    if overrides.obstacles then
        self.obstacle:update_config(overrides.obstacles)
    end
    if overrides.navigation then
        self.nav_client:update_config(overrides.navigation)
    end
end

--------------------------------------------------------------------------------
-- Event system
--------------------------------------------------------------------------------

---Register a listener for an event.
---Events: "state_change", "arrived", "stuck", "failed"
---@param event string
---@param callback function
function Facade:on(event, callback)
    if not self._listeners[event] then
        self._listeners[event] = {}
    end
    local list = self._listeners[event]
    list[#list + 1] = callback
end

---Remove a listener.
---@param event string
---@param callback function
function Facade:off(event, callback)
    local list = self._listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
        end
    end
end

---@private
function Facade:_fire(event, data)
    local list = self._listeners[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], data)
        if not ok then
            core.log_error("[NavLib] Event '" .. event .. "' handler error: " .. tostring(err))
        end
    end
end

return Facade
