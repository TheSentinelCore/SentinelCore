-- ApplyDynamicSpeed.lua
-- BT Action: applies dynamic speed scaling. Always succeeds.
local BT = require("lib/BehaviorTree")

---@param movement_service table MovementService instance
return function(movement_service)
    return BT.Action:new(function(bb, dt)
        movement_service:apply_dynamic_speed(bb)
        return BT.SUCCESS
    end, "ApplyDynamicSpeed")
end
