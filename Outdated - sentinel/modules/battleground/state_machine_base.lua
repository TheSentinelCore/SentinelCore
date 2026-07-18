local Events = require("modules/battleground/events")

local Base = {}
Base.__index = Base

function Base:new(event_bus, blackboard, bg_key, side)
    local o = setmetatable({}, self)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._bg_key = bg_key
    o._side = side or "ALLIANCE"
    o._state = "SPAWN"
    o._objective_id = nil
    o._route_nodes = nil
    o._route_id = nil
    o._nav_target = nil
    return o
end

function Base:get_current_state()
    return self._state
end

function Base:get_nav_target()
    return self._nav_target
end

function Base:get_route_nodes()
    return self._route_nodes
end

function Base:get_route_id()
    return self._route_id
end

function Base:get_objective_data()
    return self._nav_target
end

function Base:should_use_plan_route()
    return type(self._route_nodes) == "table" and #self._route_nodes >= 2
end

function Base:should_follow_path()
    return type(self._route_nodes) == "table" and #self._route_nodes >= 2
end

function Base:should_engage()
    return self._state ~= "RETREAT" and self._state ~= "REGROUP"
end

function Base:get_objective_id()
    return self._objective_id
end

function Base:_set_state(next_state, reason)
    if self._state == next_state then
        return
    end
    local previous = self._state
    self._state = next_state
    self._blackboard:set("bg.state", next_state)
    self._event_bus:publish(Events.STATE_CHANGED, {
        bg_key = self._bg_key,
        from = previous,
        to = next_state,
        objective_id = self._objective_id,
        reason = reason or "state_change",
    })
end

function Base:_set_objective(objective_id, nav_target, route_nodes, route_id)
    self._objective_id = objective_id
    self._nav_target = nav_target
    self._route_nodes = route_nodes
    self._route_id = route_id
    self._blackboard:set("bg.objective_id", objective_id)
    self._blackboard:set("bg.nav_target", nav_target)
    self._blackboard:set("bg.route_id", route_id)
    self._event_bus:publish(Events.OBJECTIVE_SELECTED, {
        bg_key = self._bg_key,
        objective_id = objective_id,
        lane_id = route_id or (route_nodes and objective_id or nil),
        target = nav_target,
    })
end

function Base:_consume_nav_result()
    local result = self._blackboard:get("bg.nav_result")
    if result then
        self._blackboard:clear("bg.nav_result")
    end
    return result
end

return Base
