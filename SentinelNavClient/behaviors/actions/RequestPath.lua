-- RequestPath.lua
-- BT Action: async HTTP path request. Returns RUNNING while waiting.
local BT = require("lib/BehaviorTree")
local Events = require("events/Events")
local REQUEST_OWNER_SEQ = 0

local function classify_failure_reason(err)
    local msg = string.lower(tostring(err or ""))
    if msg:find("timeout", 1, true) then
        return "server_timeout"
    end
    if msg:find("http 0", 1, true) then
        return "server_timeout"
    end
    if msg:find("http 5", 1, true) then
        return "server_timeout"
    end
    return "unreachable"
end

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

local function merge_avoid_zones(primary, secondary)
    local merged = nil

    local function append(list)
        if not list then return end
        for i = 1, #list do
            local zone = list[i]
            if zone then
                if not merged then
                    merged = {}
                end
                merged[#merged + 1] = {
                    x = zone.x,
                    y = zone.y,
                    z = zone.z,
                    radius = zone.radius,
                    cost = zone.cost,
                }
            end
        end
    end

    append(primary)
    append(secondary)
    return merged
end

---@param nav_service table NavigationService instance
---@param movement_service table MovementService instance
---@param event_bus table EventBus instance
return function(nav_service, movement_service, event_bus)
    REQUEST_OWNER_SEQ = REQUEST_OWNER_SEQ + 1
    local owner_id = "request_path:" .. tostring(REQUEST_OWNER_SEQ)

    return BT.Action:new(function(bb, dt)
        local now = bb:get("_time", 0)

        -- Check for pending response
        if bb:get("request.pending") then
            if bb:get("request.active_kind") ~= "path" then
                return BT.RUNNING
            end
            if bb:get("request.active_owner") ~= owner_id then
                return BT.RUNNING
            end

            local result = bb:get("request.result")
            local err = bb:get("request.error")
            if result then
                bb:set("path.waypoints", result.waypoints)
                bb:set("path.index", 1)
                bb:set("path.is_partial", result.partial or false)
                bb:set("path.total_distance", result.distance or 0)
                bb:set("path.corridor_widths", result.corridor_widths)
                bb:set("request.pending", false)
                bb:clear("request.retry_at")
                bb:clear("request.result")
                bb:clear("request.error")
                bb:clear("request.active_id")
                bb:clear("request.active_kind")
                bb:clear("request.active_owner")
                bb:set("request.path_failures", 0)
                bb:clear("nav.fail_reason")
                bb:clear("nav.fail_detail")
                bb:clear("deviation.last_repath_pos")
                bb:set("deviation.progress_since_repath", 0)
                bb:clear("deviation.last_check")
                bb:clear("deviation.last_raw_result")
                bb:clear("deviation.last_result")
                bb:clear("deviation.consecutive_count")
                bb:clear("deviation.confirmed_prev")
                -- Start movement — simple_movement needs navigate() before process() works
                if not movement_service:navigate(result.waypoints) then
                    bb:set("nav.fail_reason", "unreachable")
                    bb:set("nav.fail_detail", "movement service unavailable: navigate() failed")
                    event_bus:emit(Events.PATH_FAILED, {
                        error = "movement service unavailable: navigate() failed",
                        start = bb:get("player.position"),
                        destination = bb:get("path.destination"),
                        retrying = false,
                        fatal = true,
                    })
                    return BT.FAILURE
                end

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
                bb:clear("request.active_id")
                bb:clear("request.active_kind")
                bb:clear("request.active_owner")

                local failures = bb:get("request.path_failures", 0) + 1
                bb:set("request.path_failures", failures)
                local max_retries = bb:get("config.path_request_max_retries", 2)

                if failures <= max_retries then
                    local base_delay = bb:get("config.path_request_retry_base", 0.5)
                    local delay_secs = base_delay * (2 ^ (failures - 1))
                    bb:set("request.retry_at", now + delay_secs)

                    event_bus:emit(Events.PATH_FAILED, {
                        error = err or "path request failed",
                        start = bb:get("player.position"),
                        destination = bb:get("path.destination"),
                        retrying = true,
                        attempt = failures,
                        max_retries = max_retries,
                        next_retry_in = delay_secs,
                    })
                    return BT.RUNNING
                end

                local reason = classify_failure_reason(err)
                bb:set("nav.fail_reason", reason)
                bb:set("nav.fail_detail", err or "path request failed")
                event_bus:emit(Events.PATH_FAILED, {
                    error = err or "path request failed",
                    start = bb:get("player.position"),
                    destination = bb:get("path.destination"),
                    retrying = false,
                    fatal = true,
                    attempt = failures,
                })
                return BT.FAILURE
            end
            return BT.RUNNING
        end

        local retry_at = bb:get("request.retry_at")
        if retry_at and now < retry_at then
            return BT.RUNNING
        end

        -- Issue new request
        local start = bb:get("player.position")
        local dest = bb:get("path.destination")
        if not start or not dest then
            bb:set("nav.fail_reason", "unreachable")
            bb:set("nav.fail_detail", "missing start or destination")
            event_bus:emit(Events.PATH_FAILED, {
                error = "missing start or destination",
                start = start,
                destination = dest,
                fatal = true,
            })
            return BT.FAILURE
        end

        local session_id = bb:get("nav.session_id", 0)
        local request_id = next_request_id(bb)
        bb:set("request.pending", true)
        bb:set("request.active_id", request_id)
        bb:set("request.active_kind", "path")
        bb:set("request.active_owner", owner_id)
        bb:clear("request.retry_at")
        bb:clear("request.result")
        bb:clear("request.error")

        event_bus:emit(Events.PATH_REQUESTED, {
            start = start,
            destination = dest,
            request_id = request_id,
        })

        local opts = merge_opts(
            bb:get("config._path_opts") or {},
            bb:get("path.command_opts")
        )
        local zones = merge_avoid_zones(opts.avoid_zones, bb:get("obstacles.zones"))
        local has_zones = zones and #zones > 0
        opts.avoid_zones = nil
        local use_corridor = bb:get("config.use_corridor_indoor", true)
            and nav_service.is_indoor
            and nav_service.is_indoor()
        if use_corridor then
            opts.probe_distance = bb:get("config.corridor_probe_dist", 15.0)
            if has_zones then
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
            if bb:get("request.active_owner") ~= owner_id then
                return
            end
            if ok and data and data.waypoints and #data.waypoints > 0 then
                bb:set("request.result", data)
            else
                bb:set("request.error", err or "empty path")
            end
        end

        if use_corridor then
            nav_service:find_path_corridor(start, dest, callback, opts)
        elseif has_zones then
            nav_service:find_path_avoid(start, dest, zones, callback, opts)
        else
            nav_service:find_path(start, dest, callback, opts)
        end

        return BT.RUNNING
    end, "RequestPath")
end
