-- ProbeForObstacle.lua
-- BT Action: probes path ahead for obstacles. SUCCESS = obstacle found, FAILURE = clear.
local BT = require("lib.BehaviorTree")

---@param obstacle_service table ObstacleService instance
return function(obstacle_service)
    return BT.Action:new("ProbeForObstacle", function(bb, dt)
        local pos = bb:get("player.position")
        local waypoints = bb:get("path.waypoints")
        local index = bb:get("path.index", 1)
        if not pos or not waypoints or index > #waypoints then return BT.FAILURE end

        local remaining = {}
        for i = index, #waypoints do
            remaining[#remaining + 1] = waypoints[i]
        end

        local segments = bb:get("config.lookahead_segments", 3)
        local hit, seg_index = obstacle_service:probe_path_ahead(remaining, segments)
        if hit then
            bb:set("obstacles.last_hit", hit)
            return BT.SUCCESS -- obstacle found
        end
        return BT.FAILURE -- path is clear
    end)
end
