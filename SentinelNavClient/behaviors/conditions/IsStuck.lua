-- IsStuck.lua
-- BT Condition: returns SUCCESS if stuck.count > 0
local BT = require("lib/BehaviorTree")

--- Factory: returns a BT.Condition node that checks if the player is stuck.
---@return table BT.Condition node
return function()
    return BT.Condition:new(function(bb)
        local substate = bb:get("hsm.substate")
        if substate ~= "following_path" and substate ~= "recovering" then
            return false
        end
        return bb:get("stuck.count", 0) > 0
    end, "IsStuck")
end
