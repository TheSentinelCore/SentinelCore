-- NavLibFacade.lua
-- Single entry-point facade for NavLib: creates, wires, and drives all modules.

local NavigationClient = require("NavigationClient")
local MovementModule   = require("MovementModule")
local ObstacleModule   = require("ObstacleModule")

---@class NavLibFacade
---@field nav_client NavigationClient   Escape-hatch: raw HTTP client
---@field movement   MovementModule     Escape-hatch: path-following module
---@field obstacle   ObstacleModule     Escape-hatch: obstacle detection module
local NavLibFacade = {}
NavLibFacade.__index = NavLibFacade

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

---Create a fully-wired NavLib instance.
---@param config? table { navigation?, movement?, obstacles? }
---@return NavLibFacade
function NavLibFacade:new(config)
    config = config or {}
    local o = setmetatable({}, NavLibFacade)

    -- 1. Create modules
    o.nav_client = NavigationClient:new(config.navigation)
    o.movement   = MovementModule:new(o.nav_client, config.movement)
    o.obstacle   = ObstacleModule:new(config.obstacles)

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
function NavLibFacade:update()
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
-- Movement (delegates to MovementModule)
--------------------------------------------------------------------------------

---Move to a target position using navmesh pathfinding.
---@param target vec3
---@param callback? fun(success: boolean, reason: string|nil)
---@param opts? table
function NavLibFacade:move_to(target, callback, opts)
    self.movement:move_to(target, callback, opts)
end

---Move directly without pathfinding (short range / emergency).
---@param target vec3
---@param callback? fun(success: boolean, reason: string|nil)
function NavLibFacade:move_direct(target, callback)
    self.movement:move_direct(target, callback)
end

---Plan an optimized multi-node route (TSP).
---@param nodes vec3[]
---@param callback? fun(success: boolean, data: table)
---@param opts? table
function NavLibFacade:plan_route(nodes, callback, opts)
    self.movement:plan_route(nodes, callback, opts)
end

---Re-request path from current position to current destination.
---@param reason? string
function NavLibFacade:replan(reason)
    self.movement:replan(reason)
end

---Pre-validate whether a destination is reachable.
---@param target vec3
---@param callback fun(reachable: boolean, reason: string|nil, distance: number|nil)
function NavLibFacade:validate_destination(target, callback)
    self.movement:validate_destination_reachable(target, callback)
end

---Stop all movement and reset to idle.
function NavLibFacade:stop()
    self.movement:stop()
end

---Stop movement, clear obstacle zones, nil references.
function NavLibFacade:destroy()
    self.movement:stop()
    self.obstacle:clear()
    self._listeners = {}
end

--------------------------------------------------------------------------------
-- State queries (delegates to MovementModule)
--------------------------------------------------------------------------------

---@return string
function NavLibFacade:get_state()
    return self.movement:get_state()
end

---@return boolean
function NavLibFacade:is_moving()
    return self.movement:is_moving()
end

---@return vec3|nil
function NavLibFacade:get_destination()
    return self.movement:get_destination()
end

---@return vec3[]|nil
function NavLibFacade:get_current_path()
    return self.movement:get_current_path()
end

---@return number
function NavLibFacade:get_path_index()
    return self.movement:get_path_index()
end

---@return table
function NavLibFacade:get_progress()
    return self.movement:get_progress()
end

---@return number[]|nil
function NavLibFacade:get_corridor_widths()
    return self.movement:get_corridor_widths()
end

--------------------------------------------------------------------------------
-- Server queries (delegates to NavigationClient)
--------------------------------------------------------------------------------

---@return boolean
function NavLibFacade:is_server_available()
    return self.nav_client:is_available()
end

---@param callback fun(ok: boolean, data: table|nil, err: string|nil)
function NavLibFacade:health_check(callback)
    self.nav_client:health_check(callback)
end

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

---Distribute config updates to underlying modules.
---@param overrides table { movement?: table, obstacles?: table }
function NavLibFacade:update_config(overrides)
    if not overrides then return end
    if overrides.movement then
        self.movement:update_config(overrides.movement)
    end
    if overrides.obstacles then
        self.obstacle:update_config(overrides.obstacles)
    end
end

--------------------------------------------------------------------------------
-- Event system
--------------------------------------------------------------------------------

---Register a listener for an event.
---Events: "state_change", "arrived", "stuck", "failed"
---@param event string
---@param callback function
function NavLibFacade:on(event, callback)
    if not self._listeners[event] then
        self._listeners[event] = {}
    end
    local list = self._listeners[event]
    list[#list + 1] = callback
end

---Remove a listener.
---@param event string
---@param callback function
function NavLibFacade:off(event, callback)
    local list = self._listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
        end
    end
end

---@private
function NavLibFacade:_fire(event, data)
    local list = self._listeners[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], data)
        if not ok then
            core.log_error("[NavLib] Event '" .. event .. "' handler error: " .. tostring(err))
        end
    end
end

return NavLibFacade
