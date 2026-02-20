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
        -- Check if ValidatePath flagged the path as invalid on the navmesh
        if bb:get("deviation.needs_repath") then
            bb:clear("deviation.needs_repath")
            return true
        end

        local now = bb:get("_time", 0)
        local interval = bb:get("config.deviation_check_interval", 1.0)
        local last_check = bb:get("deviation.last_check", 0)

        if now - last_check < interval then
            return bb:get("deviation.last_result", false)
        end

        bb:set("deviation.last_check", now)

        local pos = bb:get("player.position")
        local waypoints = bb:get("path.waypoints")
        local index = bb:get("path.index", 1)
        local widths = bb:get("path.corridor_widths")
        if not pos or not waypoints or #waypoints == 0 then return false end

        local result = validation_service:check_deviation(pos, waypoints, index, widths)
        bb:set("deviation.last_result", result.deviated)

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
