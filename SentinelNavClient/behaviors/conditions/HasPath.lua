-- HasPath.lua
-- BT Condition: returns SUCCESS if path.waypoints exists and has entries
local BT = require("lib.BehaviorTree")

--- Factory: returns a BT.Condition node that checks if a valid path exists.
---@return table BT.Condition node
return function()
    return BT.Condition:new("HasPath", function(bb)
        local waypoints = bb:get("path.waypoints")
        return waypoints ~= nil and #waypoints > 0
    end)
end
