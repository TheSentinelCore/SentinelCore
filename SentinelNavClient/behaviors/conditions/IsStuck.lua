-- IsStuck.lua
-- BT Condition: returns SUCCESS if stuck.count > 0
local BT = require("lib.BehaviorTree")

--- Factory: returns a BT.Condition node that checks if the player is stuck.
---@return table BT.Condition node
return function()
    return BT.Condition:new("IsStuck", function(bb)
        return bb:get("stuck.count", 0) > 0
    end)
end
