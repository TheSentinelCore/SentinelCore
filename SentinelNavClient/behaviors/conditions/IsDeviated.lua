-- IsDeviated.lua
-- BT Condition: returns SUCCESS if player has deviated from path.
-- Requires a PathValidationService instance and EventBus passed to factory.
local BT = require("lib/BehaviorTree")
local Events = require("events/Events")

--- Factory: returns a BT.Condition node that checks path deviation.
---@param validation_service table PathValidationService instance
---@param event_bus table EventBus instance
---@return table BT.Condition node
return function(validation_service, event_bus)
    return BT.Condition:new(function(bb)
        local pos = bb:get("player.position")
        local waypoints = bb:get("path.waypoints")
        local index = bb:get("path.index", 1)
        local widths = bb:get("path.corridor_widths")
        if not pos or not waypoints or #waypoints == 0 then return false end

        local result = validation_service:check_deviation(pos, waypoints, index, widths)
        if result.deviated then
            bb:set("deviation.last_drift", result.drift)
            event_bus:emit(Events.DEVIATION_DETECTED, {
                drift = result.drift,
                position = pos,
                path_index = index,
            })
        end
        return result.deviated
    end, "IsDeviated")
end
