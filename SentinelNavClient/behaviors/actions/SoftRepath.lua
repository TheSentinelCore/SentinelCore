-- SoftRepath.lua
-- BT Action: repath without stopping movement — seamlessly blends new path.
-- Same as Repath but does NOT call movement_service:stop() first.
local BT = require("lib/BehaviorTree")
local Events = require("events/Events")

---@param nav_service table NavigationService instance
---@param movement_service table MovementService instance
---@param obstacle_service table ObstacleService instance
---@param event_bus table EventBus instance
return function(nav_service, movement_service, obstacle_service, event_bus)
    return BT.Action:new(function(bb, dt)
        -- Check for pending response
        if bb:get("request.pending") then
            local result = bb:get("request.result")
            local err = bb:get("request.error")
            if result then
                bb:set("path.waypoints", result.waypoints)
                bb:set("path.index", 1)
                bb:set("path.is_partial", result.partial or false)
                bb:set("path.corridor_widths", result.corridor_widths)
                bb:set("request.pending", false)
                bb:clear("request.result")
                bb:clear("request.error")
                bb:clear("deviation.last_check")
                bb:clear("deviation.last_result")
                -- Navigate without stopping — blend into new path
                movement_service:navigate(result.waypoints)
                local count = bb:get("deviation.count", 0)
                bb:set("deviation.count", count + 1)
                event_bus:emit(Events.REPATH_COMPLETED, {
                    success = true,
                    waypoint_count = #result.waypoints,
                    soft = true,
                })
                return BT.SUCCESS
            elseif err then
                bb:set("request.pending", false)
                bb:clear("request.result")
                bb:clear("request.error")
                event_bus:emit(Events.REPATH_COMPLETED, {
                    success = false,
                    soft = true,
                    error = err or "soft repath failed",
                })
                return BT.FAILURE
            end
            return BT.RUNNING
        end

        -- Start soft repath
        obstacle_service:prune(bb:get("player.position"))
        local start = bb:get("player.position")
        local dest = bb:get("path.destination")
        if not start or not dest then
            event_bus:emit(Events.REPATH_COMPLETED, {
                success = false,
                soft = true,
                error = "missing start or destination",
            })
            return BT.FAILURE
        end

        bb:set("request.pending", true)
        bb:clear("request.result")
        bb:clear("request.error")
        event_bus:emit(Events.REPATH_STARTED, { reason = "deviation", soft = true })

        local zones = obstacle_service:get_avoidance_zones()
        local opts = bb:get("config._path_opts") or {}
        local callback = function(ok, data, err)
            if ok and data and data.waypoints and #data.waypoints > 0 then
                bb:set("request.result", data)
            else
                bb:set("request.error", err or "soft repath failed")
            end
        end

        if zones and #zones > 0 then
            nav_service:find_path_avoid(start, dest, zones, callback, opts)
        else
            nav_service:find_path(start, dest, callback, opts)
        end

        return BT.RUNNING
    end, "SoftRepath")
end
