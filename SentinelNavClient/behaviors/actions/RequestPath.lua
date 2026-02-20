-- RequestPath.lua
-- BT Action: async HTTP path request. Returns RUNNING while waiting.
local BT = require("lib/BehaviorTree")
local Events = require("events/Events")

---@param nav_service table NavigationService instance
---@param movement_service table MovementService instance
---@param event_bus table EventBus instance
return function(nav_service, movement_service, event_bus)
    return BT.Action:new(function(bb, dt)
        -- Check for pending response
        if bb:get("request.pending") then
            local result = bb:get("request.result")
            local err = bb:get("request.error")
            if result then
                bb:set("path.waypoints", result.waypoints)
                bb:set("path.index", 1)
                bb:set("path.is_partial", result.partial or false)
                bb:set("path.total_distance", result.distance or 0)
                bb:set("path.corridor_widths", result.corridor_widths)
                bb:set("request.pending", false)
                bb:clear("request.result")
                bb:clear("request.error")
                -- Start movement — simple_movement needs navigate() before process() works
                movement_service:navigate(result.waypoints)

                event_bus:emit(Events.PATH_RECEIVED, {
                    waypoint_count = #result.waypoints,
                    distance = result.distance,
                    partial = result.partial,
                })
                return BT.SUCCESS
            elseif err then
                bb:set("request.pending", false)
                bb:clear("request.result")
                bb:clear("request.error")
                event_bus:emit(Events.PATH_FAILED, {
                    error = err or "path request failed",
                    start = bb:get("player.position"),
                    destination = bb:get("path.destination"),
                })
                return BT.FAILURE
            end
            return BT.RUNNING
        end

        -- Issue new request
        local start = bb:get("player.position")
        local dest = bb:get("path.destination")
        if not start or not dest then
            event_bus:emit(Events.PATH_FAILED, {
                error = "missing start or destination",
                start = start,
                destination = dest,
            })
            return BT.FAILURE
        end

        bb:set("request.pending", true)
        bb:clear("request.result")
        bb:clear("request.error")

        event_bus:emit(Events.PATH_REQUESTED, { start = start, destination = dest })

        local zones = bb:get("obstacles.zones")
        local has_zones = zones and #zones > 0
        local opts = bb:get("config._path_opts") or {}

        local callback = function(ok, data, err)
            if ok and data and data.waypoints and #data.waypoints > 0 then
                bb:set("request.result", data)
            else
                bb:set("request.error", err or "empty path")
            end
        end

        if has_zones then
            nav_service:find_path_avoid(start, dest, zones, callback, opts)
        else
            nav_service:find_path(start, dest, callback, opts)
        end

        return BT.RUNNING
    end, "RequestPath")
end
