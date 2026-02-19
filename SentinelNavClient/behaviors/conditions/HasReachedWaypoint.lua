-- HasReachedWaypoint.lua
-- BT Condition: returns SUCCESS if the current path index has passed all waypoints.
local BT = require("lib.BehaviorTree")

--- Factory: returns a BT.Condition node that checks if all waypoints are reached.
---@return table BT.Condition node
return function()
    return BT.Condition:new("HasReachedWaypoint", function(bb)
        local waypoints = bb:get("path.waypoints")
        local index = bb:get("path.index", 1)
        return waypoints ~= nil and index > #waypoints
    end)
end
