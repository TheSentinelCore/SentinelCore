-- AdvanceWaypoint.lua
-- BT Action: processes movement, advances waypoint index, emits events.
local BT = require("lib/BehaviorTree")
local Events = require("events/Events")

---@param movement_service table MovementService instance
---@param event_bus table EventBus instance
return function(movement_service, event_bus)
    return BT.Action:new(function(bb, dt)
        local reached_end = movement_service:process()
        if reached_end then
            return BT.SUCCESS -- all waypoints done
        end

        local new_index = movement_service:get_current_index()
        local old_index = bb:get("path.index", 1)
        if new_index ~= old_index then
            bb:set("path.index", new_index)
            local waypoints = bb:get("path.waypoints")
            event_bus:emit(Events.WAYPOINT_REACHED, {
                index = new_index,
                total = waypoints and #waypoints or 0,
                position = waypoints and waypoints[new_index],
            })
        end

        return BT.RUNNING -- still following
    end, "AdvanceWaypoint")
end
