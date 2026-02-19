-- IsDeviated.lua
-- BT Condition: returns SUCCESS if player has deviated from path.
-- Requires a PathValidationService instance passed to factory.
local BT = require("lib.BehaviorTree")

--- Factory: returns a BT.Condition node that checks path deviation.
---@param validation_service table PathValidationService instance
---@return table BT.Condition node
return function(validation_service)
    return BT.Condition:new("IsDeviated", function(bb)
        local pos = bb:get("player.position")
        local waypoints = bb:get("path.waypoints")
        local index = bb:get("path.index", 1)
        local widths = bb:get("path.corridor_widths")
        if not pos or not waypoints or #waypoints == 0 then return false end

        local result = validation_service:check_deviation(pos, waypoints, index, widths)
        if result.deviated then
            bb:set("deviation.last_drift", result.drift)
        end
        return result.deviated
    end)
end
