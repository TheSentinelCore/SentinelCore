-- AddAvoidanceZone.lua
-- BT Action: adds an avoidance zone at last hit or player position.
local BT = require("lib.BehaviorTree")

---@param obstacle_service table ObstacleService instance
return function(obstacle_service)
    return BT.Action:new("AddAvoidanceZone", function(bb, dt)
        local pos = bb:get("obstacles.last_hit")
        if not pos then
            pos = bb:get("player.position")
        end
        if not pos then return BT.FAILURE end

        obstacle_service:add_zone(pos)
        return BT.SUCCESS
    end)
end
