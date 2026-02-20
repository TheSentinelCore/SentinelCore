-- SoftRepath.lua
-- BT Action: repath without stopping movement — seamlessly blends new path.
-- Same as Repath but does NOT call movement_service:stop() first.
local BT = require("lib/BehaviorTree")
local Events = require("events/Events")

local function merge_opts(base_opts, override_opts)
    local merged = {}
    if base_opts then
        for k, v in pairs(base_opts) do
            merged[k] = v
        end
    end
    if override_opts then
        for k, v in pairs(override_opts) do
            merged[k] = v
        end
    end
    return merged
end

local function next_request_id(bb)
    local request_id = bb:get("request.next_id", 0) + 1
    bb:set("request.next_id", request_id)
    return request_id
end

---@param nav_service table NavigationService instance
---@param movement_service table MovementService instance
---@param obstacle_service table ObstacleService instance
---@param event_bus table EventBus instance
---@param opts? table { reason?: string, count_deviation?: boolean }
return function(nav_service, movement_service, obstacle_service, event_bus, opts)
    opts = opts or {}
    local repath_reason = opts.reason or "deviation"
    local count_deviation = opts.count_deviation == true

    return BT.Action:new(function(bb, dt)
        -- Check for pending response
        if bb:get("request.pending") then
            if bb:get("request.active_kind") ~= "soft_repath" then
                return BT.RUNNING
            end

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
                bb:clear("request.active_id")
                bb:clear("request.active_kind")
                bb:clear("deviation.last_check")
                bb:clear("deviation.last_result")
                bb:clear("deviation.needs_repath")
                bb:clear("deviation.eval_tick")
                bb:clear("deviation.eval_result")
                -- Navigate without stopping — blend into new path
                movement_service:navigate(result.waypoints)
                if count_deviation then
                    local count = bb:get("deviation.count", 0)
                    bb:set("deviation.count", count + 1)
                end
                bb:set("repath.failures", 0)
                bb:clear("nav.fail_reason")
                bb:clear("nav.fail_detail")
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
                bb:clear("request.active_id")
                bb:clear("request.active_kind")

                local failures = bb:get("repath.failures", 0) + 1
                bb:set("repath.failures", failures)
                local max_failures = bb:get("config.max_repath_failures", 3)
                local fatal = failures >= max_failures
                if fatal then
                    bb:set("nav.fail_reason", "max_repath_exceeded")
                    bb:set("nav.fail_detail", err or "soft repath failed")
                end

                event_bus:emit(Events.REPATH_COMPLETED, {
                    success = false,
                    soft = true,
                    error = err or "soft repath failed",
                    attempt = failures,
                    max_failures = max_failures,
                    fatal = fatal,
                })
                if fatal then
                    return BT.FAILURE
                end
                return BT.SUCCESS
            end
            return BT.RUNNING
        end

        -- Start soft repath
        obstacle_service:prune(bb:get("player.position"))
        local start = bb:get("player.position")
        local dest = bb:get("path.destination")
        if not start or not dest then
            bb:set("nav.fail_reason", "unreachable")
            bb:set("nav.fail_detail", "missing start or destination for soft repath")
            event_bus:emit(Events.REPATH_COMPLETED, {
                success = false,
                soft = true,
                error = "missing start or destination",
                fatal = true,
            })
            return BT.FAILURE
        end

        local session_id = bb:get("nav.session_id", 0)
        local request_id = next_request_id(bb)
        bb:set("request.pending", true)
        bb:set("request.active_id", request_id)
        bb:set("request.active_kind", "soft_repath")
        bb:clear("request.result")
        bb:clear("request.error")
        bb:clear("deviation.needs_repath")
        bb:clear("deviation.eval_tick")
        bb:clear("deviation.eval_result")
        event_bus:emit(Events.REPATH_STARTED, { reason = repath_reason, soft = true })

        local zones = obstacle_service:get_avoidance_zones()
        local opts = merge_opts(
            bb:get("config._path_opts") or {},
            bb:get("path.command_opts")
        )
        local use_corridor = bb:get("config.use_corridor_indoor", true)
            and nav_service.is_indoor
            and nav_service.is_indoor()
        if use_corridor then
            opts.probe_distance = bb:get("config.corridor_probe_dist", 15.0)
            if zones and #zones > 0 then
                opts.avoid_zones = zones
            end
        end

        local callback = function(ok, data, err)
            if bb:get("nav.session_id", 0) ~= session_id then
                return
            end
            if bb:get("request.active_id") ~= request_id then
                return
            end
            if ok and data and data.waypoints and #data.waypoints > 0 then
                bb:set("request.result", data)
            else
                bb:set("request.error", err or "soft repath failed")
            end
        end

        if use_corridor then
            nav_service:find_path_corridor(start, dest, callback, opts)
        elseif zones and #zones > 0 then
            nav_service:find_path_avoid(start, dest, zones, callback, opts)
        else
            nav_service:find_path(start, dest, callback, opts)
        end

        return BT.RUNNING
    end, "SoftRepath")
end
