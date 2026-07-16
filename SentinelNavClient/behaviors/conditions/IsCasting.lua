-- IsCasting.lua
-- BT Condition: returns SUCCESS if the player is currently casting or channelling.
local BT = require("lib/BehaviorTree")

--- Factory: returns a BT.Condition node that checks if the player is casting.
---@return table BT.Condition node
return function()
    return BT.Condition:new(function(bb)
        return bb:get("player.is_casting", false)
    end, "IsCasting")
end
