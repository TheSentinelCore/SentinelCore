local ErrorCodes = require("events/ErrorCodes")
local Events = require("events/Events")
local get_now = require("lib/TimeHelper").get_now

---@class NavigationAdapter
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _client table|nil
---@field private _last_health_ok boolean
---@field private _height_cache table
local NavigationAdapter = {}
NavigationAdapter.__index = NavigationAdapter

---@param event_bus EventBus
---@param blackboard Blackboard
---@return NavigationAdapter
function NavigationAdapter:new(event_bus, blackboard, logger)
    local o = setmetatable({}, NavigationAdapter)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._client = nil
    o._last_health_ok = false
    o._height_cache = {}
    o._log = logger or { debug=function()end, info=function()end, warn=function()end, error=function()end }
    -- D4: Stuck detection state
    o._stuck_check_pos = nil
    o._stuck_check_at = 0
    o._stuck_duration = 0
    o._stuck_phase = 0
    o._stuck_backward_until = 0
    o._stuck_current_dest = nil
    o._stuck_stopped_at = 0
    return o
end

---@private
function NavigationAdapter:_resolve_client()
    local global_client = _G and _G.SentinelNavClient and _G.SentinelNavClient.client or nil
    if global_client ~= self._client then
        self._client = global_client
    end
    return self._client
end

---@return table|nil
function NavigationAdapter:get_client()
    return self:_resolve_client()
end

---@return boolean
---@return string|nil
function NavigationAdapter:is_available()
    local client = self:_resolve_client()
    if not client then
        self._log:warn("NavClient unavailable")
        return false, ErrorCodes.DEP_NAVCLIENT_MISSING
    end
    return true, nil
end

---@return boolean
function NavigationAdapter:is_server_available()
    local client = self:_resolve_client()
    if not client or type(client.is_server_available) ~= "function" then
        return false
    end

    local ok, value = pcall(client.is_server_available, client)
    if not ok then
        return false
    end
    return value == true
end

---@param callback fun(ok: boolean, error_code: string|nil)
function NavigationAdapter:health_check(callback)
    local client = self:_resolve_client()
    if not client or type(client.health_check) ~= "function" then
        callback(false, ErrorCodes.DEP_NAVCLIENT_MISSING)
        return
    end

    client:health_check(function(ok)
        self._last_health_ok = ok == true
        if not ok then
            callback(false, ErrorCodes.DEP_NAVCLIENT_UNHEALTHY)
            return
        end
        callback(true, nil)
    end)
end

---@param destination vec3
---@param callback? fun(ok: boolean, error_code: string|nil, detail: table|nil)
---@param opts? table
function NavigationAdapter:move_to(destination, callback, opts)
    self._log:debug("move_to (%.1f, %.1f, %.1f)",
        tonumber(destination and destination.x) or 0,
        tonumber(destination and destination.y) or 0,
        tonumber(destination and destination.z) or 0)
    local client = self:_resolve_client()
    if not client or type(client.move_to) ~= "function" then
        self._log:warn("move_to failed: NavClient unavailable")
        if callback then
            callback(false, ErrorCodes.DEP_NAVCLIENT_MISSING, nil)
        end
        return
    end

    -- D4: Track current destination for stuck detection.
    self._stuck_current_dest = {
        x = tonumber(destination and destination.x) or 0,
        y = tonumber(destination and destination.y) or 0,
        z = tonumber(destination and destination.z) or 0,
    }
    -- Reset stuck state on a fresh move_to.
    self._stuck_check_pos = nil
    self._stuck_check_at = 0
    self._stuck_duration = 0
    self._stuck_phase = 0

    client:move_to(destination, function(ok, reason, detail)
        if ok then
            -- D4: Arrived — reset stuck state.
            self._stuck_duration = 0
            self._stuck_phase = 0
            self._stuck_current_dest = nil
        end
        if callback then
            if ok then
                callback(true, nil, detail)
            else
                callback(false, reason or ErrorCodes.NAV_MOVE_FAILED, detail)
            end
        end
    end, opts)
end

---@return boolean|nil
function NavigationAdapter:is_moving()
    local client = self:_resolve_client()
    if not client or type(client.is_moving) ~= "function" then
        return nil
    end
    local ok, moving = pcall(client.is_moving, client)
    if not ok then
        return nil
    end
    return moving == true
end

---@return string|nil
function NavigationAdapter:get_full_state()
    local client = self:_resolve_client()
    if not client or type(client.get_full_state) ~= "function" then
        return nil
    end
    local ok, state = pcall(client.get_full_state, client)
    if not ok or type(state) ~= "string" then
        return nil
    end
    return state
end

---@private
---@param client table
---@param opts table|nil
---@return table|nil
local function merge_path_opts(client, opts)
    local merged = {}
    local has_any = false

    if type(client.get_path_opts) == "function" then
        local ok, base_opts = pcall(client.get_path_opts, client)
        if ok and type(base_opts) == "table" then
            for key, value in pairs(base_opts) do
                merged[key] = value
                has_any = true
            end
        end
    end

    if type(opts) == "table" then
        for key, value in pairs(opts) do
            merged[key] = value
            has_any = true
        end
    end

    if not has_any then
        return nil
    end
    return merged
end

---@param destination vec3
---@param callback? fun(ok: boolean, error_code: string|nil, detail: table|nil)
---@param opts? table
---@return boolean
function NavigationAdapter:soft_repath(destination, callback, opts)
    local client = self:_resolve_client()
    if not client then
        if callback then
            callback(false, ErrorCodes.DEP_NAVCLIENT_MISSING, nil)
        end
        return false
    end

    local nav_client = client.nav_client
    local movement = client.movement
    if not nav_client
        or type(nav_client.find_path) ~= "function"
        or not movement
        or type(movement.navigate) ~= "function"
        or type(client.get_blackboard) ~= "function" then
        if callback then
            callback(false, ErrorCodes.DEP_NAVCLIENT_UNHEALTHY, nil)
        end
        return false
    end

    local ok_bb, blackboard = pcall(client.get_blackboard, client)
    if not ok_bb or type(blackboard) ~= "table" or type(blackboard.get) ~= "function" then
        if callback then
            callback(false, ErrorCodes.DEP_NAVCLIENT_UNHEALTHY, nil)
        end
        return false
    end

    local start = blackboard:get("player.position")
    if type(start) ~= "table" and core and core.object_manager and core.object_manager.get_local_player then
        local player = core.object_manager.get_local_player()
        if player and player.is_valid and player:is_valid() and player.get_position then
            start = player:get_position()
        end
    end
    if type(start) ~= "table" then
        if callback then
            callback(false, ErrorCodes.NAV_MOVE_FAILED, nil)
        end
        return false
    end

    local path_opts = merge_path_opts(client, opts)
    nav_client:find_path(start, destination, function(ok, data, err)
        if not ok or type(data) ~= "table" or type(data.waypoints) ~= "table" or #data.waypoints <= 0 then
            if callback then
                callback(false, err or ErrorCodes.NAV_MOVE_FAILED, nil)
            end
            return
        end

        if type(blackboard.set) == "function" then
            blackboard:set("path.destination", destination)
            blackboard:set("path.waypoints", data.waypoints)
            blackboard:set("path.index", 1)
        end

        local ok_nav, navigate = pcall(movement.navigate, movement, data.waypoints)
        if not ok_nav or navigate == false then
            if callback then
                callback(false, ErrorCodes.NAV_MOVE_FAILED, nil)
            end
            return
        end

        if callback then
            callback(true, nil, {
                mode = "soft_repath",
                waypoint_count = #data.waypoints,
                distance = tonumber(data.distance),
            })
        end
    end, path_opts)

    return true
end

function NavigationAdapter:stop()
    local client = self:_resolve_client()
    if client and type(client.stop) == "function" then
        pcall(client.stop, client)
    end
    -- D4: Reset stuck state on explicit stop.
    self._stuck_check_pos = nil
    self._stuck_check_at = 0
    self._stuck_duration = 0
    self._stuck_phase = 0
    self._stuck_backward_until = 0
    self._stuck_current_dest = nil
    self._stuck_stopped_at = 0
end

---@param target vec3
---@param callback fun(reachable: boolean, error_code: string|nil, distance: number|nil)
function NavigationAdapter:validate_destination(target, callback)
    local client = self:_resolve_client()
    if not client then
        callback(false, ErrorCodes.DEP_NAVCLIENT_MISSING, nil)
        return
    end

    if type(client.validate_destination) == "function" then
        client:validate_destination(target, function(reachable, reason, distance)
            if reachable then
                callback(true, nil, distance)
            else
                callback(false, reason or ErrorCodes.NAV_MOVE_FAILED, nil)
            end
        end)
        return
    end

    callback(false, ErrorCodes.DEP_NAVCLIENT_UNHEALTHY, nil)
end

---@param from vec3
---@param to vec3
---@param callback fun(ok: boolean, cost: number|nil, error_code: string|nil)
function NavigationAdapter:estimate_path_cost(from, to, callback)
    local client = self:_resolve_client()
    if not client then
        callback(false, nil, ErrorCodes.DEP_NAVCLIENT_MISSING)
        return
    end

    if client.nav_client and type(client.nav_client.find_path) == "function" then
        client.nav_client:find_path(from, to, function(ok, data, err)
            if ok and data and data.waypoints and #data.waypoints > 0 then
                callback(true, tonumber(data.distance) or 0, nil)
            else
                callback(false, nil, err or ErrorCodes.NAV_MOVE_FAILED)
            end
        end)
        return
    end

    -- Fallback: validation API gives best-effort distance.
    self:validate_destination(to, function(reachable, reason, distance)
        if reachable then
            callback(true, tonumber(distance) or 0, nil)
        else
            callback(false, nil, reason or ErrorCodes.NAV_MOVE_FAILED)
        end
    end)
end

---@return boolean
function NavigationAdapter:get_last_health_status()
    return self._last_health_ok == true
end

---@private
---@param pos vec3
---@return string
local function _height_cache_key(pos)
    -- Quantize to 2-yard grid to share nearby lookups
    local qx = math.floor((tonumber(pos.x) or 0) / 2.0)
    local qy = math.floor((tonumber(pos.y) or 0) / 2.0)
    local qz = math.floor((tonumber(pos.z) or 0) / 2.0)
    return tostring(qx) .. ":" .. tostring(qy) .. ":" .. tostring(qz)
end

---Query the NavServer height endpoint for a position (async).
---Stores the result in _height_cache (keyed by quantized position, max 20 entries).
---@param pos vec3
---@param callback fun(height: number|nil)
function NavigationAdapter:get_position_height(pos, callback)
    if type(pos) ~= "table" then
        if callback then callback(nil) end
        return
    end

    local client = self:_resolve_client()
    if not client or type(client.get_height) ~= "function" then
        if callback then callback(nil) end
        return
    end

    -- Check cache first
    local key = _height_cache_key(pos)
    local cached = self._height_cache[key]
    if cached ~= nil then
        if callback then callback(cached) end
        return
    end

    pcall(function()
        client:get_height(pos, function(ok, data, err)
            local height = nil
            if ok and type(data) == "table" then
                height = tonumber(data.height)
            end

            -- Store in cache, evict oldest entry if over limit
            if height ~= nil then
                local cache_max = 20
                local count = 0
                for _ in pairs(self._height_cache) do
                    count = count + 1
                end
                if count >= cache_max then
                    -- Remove an arbitrary entry to make room
                    local first_key = next(self._height_cache)
                    if first_key then
                        self._height_cache[first_key] = nil
                    end
                end
                self._height_cache[key] = height
            end

            if callback then
                local ok_cb, cb_err = pcall(callback, height)
                if not ok_cb then
                    self._log:warn("get_position_height callback error: %s", tostring(cb_err))
                end
            end
        end)
    end)
end

---Synchronous height validation using the cached height value.
---Returns true if height data is unavailable (fail-open) or height > -1000.
---Returns false only when a cached height confirms the position is invalid terrain.
---@param pos vec3
---@return boolean
function NavigationAdapter:validate_position(pos)
    if type(pos) ~= "table" then
        return true  -- fail-open
    end

    local key = _height_cache_key(pos)
    local cached = self._height_cache[key]
    if cached == nil then
        -- No data yet — kick off async fetch, fail-open for now
        self:get_position_height(pos, nil)
        return true
    end

    -- height <= -1000 indicates underwater/void terrain
    return cached > -1000
end

---D4: Stuck detection and escalation.
---Called every frame from update(). Compares player position every 1.0s and
---escalates through recovery phases when position hasn't changed while moving.
---@param player_pos vec3|nil
---@param now number
function NavigationAdapter:check_stuck(player_pos, now)
    -- Phase 5 post-stop check: if phase 4 stopped nav and 5s has elapsed, emit
    -- the unrecoverable event regardless of current movement state.
    if (tonumber(self._stuck_phase) or 0) == 4 then
        local stopped_at = tonumber(self._stuck_stopped_at) or 0
        if stopped_at > 0 and (now - stopped_at) >= 5.0 then
            self._stuck_phase = 5
            self._log:warn("stuck phase 5 — NAV_STUCK_UNRECOVERABLE")
            if self._event_bus and type(self._event_bus.emit) == "function" then
                pcall(self._event_bus.emit, self._event_bus, Events.COMBAT_FAILED, {
                    timestamp = now,
                    error_code = "NAV_STUCK_UNRECOVERABLE",
                })
            end
            -- Full reset after emitting.
            self._stuck_duration = 0
            self._stuck_phase = 0
            self._stuck_current_dest = nil
            self._stuck_stopped_at = 0
        end
        return
    end

    -- Stop backward movement when the timer expires. This must run before any
    -- early-return gates so it fires even when NavClient has stopped navigating
    -- (e.g. path expired or NavServer error during phase 3), preventing the player
    -- from running backward indefinitely.
    if (tonumber(self._stuck_backward_until) or 0) > 0 and now >= self._stuck_backward_until then
        self._stuck_backward_until = 0
        if core and core.input and type(core.input.move_backward_stop) == "function" then
            pcall(core.input.move_backward_stop)
        end
    end

    -- Only check stuck when we have an active destination and NavClient says we
    -- are moving. If is_moving() == nil (NavClient down) skip the check entirely.
    local moving = self:is_moving()
    if moving ~= true or not self._stuck_current_dest then
        -- Not moving or no destination — reset stuck timer.
        if self._stuck_duration > 0 then
            self._stuck_duration = 0
            self._stuck_phase = 0
        end
        return
    end

    if not player_pos then return end

    local check_interval = 1.0
    if (now - (tonumber(self._stuck_check_at) or 0)) < check_interval then
        return  -- Not time to check yet
    end
    self._stuck_check_at = now

    local prev = self._stuck_check_pos
    if prev then
        local dx = (player_pos.x or 0) - (prev.x or 0)
        local dy = (player_pos.y or 0) - (prev.y or 0)
        local dz = (player_pos.z or 0) - (prev.z or 0)
        local moved = math.sqrt(dx * dx + dy * dy + dz * dz)

        if moved > 5.0 then
            -- Large movement: definitely not stuck — reset everything.
            self._stuck_duration = 0
            self._stuck_phase = 0
        elseif moved > 1.0 then
            -- Some movement: reset stuck duration but keep phase.
            self._stuck_duration = 0
        else
            -- Less than 1m moved while is_moving() == true: likely stuck.
            self._stuck_duration = (tonumber(self._stuck_duration) or 0) + check_interval

            local dest = self._stuck_current_dest
            local phase = tonumber(self._stuck_phase) or 0

            -- Phase 1 (3s): soft_repath to request a new path.
            if self._stuck_duration >= 3.0 and phase < 1 then
                self._stuck_phase = 1
                self._log:debug("stuck phase 1 (%.0fs) — soft_repath", self._stuck_duration)
                if dest then
                    pcall(function() self:soft_repath(dest) end)
                end

            -- Phase 2 (6s): jump.
            elseif self._stuck_duration >= 6.0 and phase < 2 then
                self._stuck_phase = 2
                self._log:debug("stuck phase 2 (%.0fs) — jump", self._stuck_duration)
                if core and core.input then
                    if type(core.input.jump) == "function" then
                        pcall(core.input.jump)
                    elseif type(core.input.set_movement) == "function" then
                        pcall(core.input.set_movement, "jump")
                    end
                end

            -- Phase 3 (9s): move backward briefly.
            elseif self._stuck_duration >= 9.0 and phase < 3 then
                self._stuck_phase = 3
                self._log:debug("stuck phase 3 (%.0fs) — move backward", self._stuck_duration)
                self._stuck_backward_until = now + 0.8
                if core and core.input and type(core.input.move_backward_start) == "function" then
                    pcall(core.input.move_backward_start)
                end

            -- Phase 4 (13s): stop navigation and record time for phase 5 check.
            -- Use the client stop directly to avoid resetting stuck state (phase 5
            -- is checked in a separate post-stop block at the top of check_stuck).
            elseif self._stuck_duration >= 13.0 and phase < 4 then
                self._stuck_phase = 4
                self._stuck_stopped_at = now
                self._log:warn("stuck phase 4 (%.0fs) — stopping nav", self._stuck_duration)
                local client_p4 = self:_resolve_client()
                if client_p4 and type(client_p4.stop) == "function" then
                    pcall(client_p4.stop, client_p4)
                end

            end
        end
    end

    -- Update the reference position for the next check.
    self._stuck_check_pos = {
        x = tonumber(player_pos.x) or 0,
        y = tonumber(player_pos.y) or 0,
        z = tonumber(player_pos.z) or 0,
    }

    -- If we requested backward movement, stop it when the timer expires.
    if (tonumber(self._stuck_backward_until) or 0) > 0 and now >= self._stuck_backward_until then
        self._stuck_backward_until = 0
        if core and core.input and type(core.input.move_backward_stop) == "function" then
            pcall(core.input.move_backward_stop)
        end
    end
end

---D5: Request a NavServer tactical flee position.
---Calls GET /api/v1/tactical/flee via the NavClient NavigationService layer.
---@param from_pos vec3
---@param threat_positions table|table[]  A single position or array of positions.
---@param callback fun(flee_pos: table|nil)  Called with {x,y,z} first waypoint or nil on failure.
---@param opts? table  Optional: flee_distance, map_id, avoid_zones, etc.
function NavigationAdapter:get_flee_position(from_pos, threat_positions, callback, opts)
    if not from_pos or not callback then
        if callback then callback(nil) end
        return
    end

    -- Normalise threat_positions to an array.
    local threats
    if type(threat_positions) == "table" then
        if threat_positions.x ~= nil then
            -- Single position table: wrap in array.
            threats = { threat_positions }
        else
            threats = threat_positions
        end
    else
        callback(nil)
        return
    end

    if #threats == 0 then
        callback(nil)
        return
    end

    -- Access NavigationService via the NavClient.
    local client = self:_resolve_client()
    local nav_svc = client and client.nav_client or nil
    if not nav_svc or type(nav_svc.flee) ~= "function" then
        -- NavServer flee unavailable: fail gracefully.
        callback(nil)
        return
    end

    opts = opts or {}
    local ok_call, call_err = pcall(function()
        nav_svc:flee(from_pos, threats, function(ok_flee, data, _err)
            if not ok_flee or type(data) ~= "table" then
                callback(nil)
                return
            end
            local waypoints = data.waypoints
            if type(waypoints) ~= "table" or #waypoints == 0 then
                callback(nil)
                return
            end
            -- Return the first waypoint (closest to player on the flee path).
            local wp = waypoints[1]
            if type(wp) == "table" and wp.x ~= nil then
                callback({ x = tonumber(wp.x) or 0, y = tonumber(wp.y) or 0, z = tonumber(wp.z) or 0 })
            else
                callback(nil)
            end
        end, opts)
    end)
    if not ok_call then
        self._log:warn("get_flee_position: error: %s", tostring(call_err))
        callback(nil)
    end
    -- Note: callback is invoked asynchronously by nav_svc:flee when the HTTP
    -- response arrives. The ok_call check above only guards the synchronous
    -- dispatch step.
end

function NavigationAdapter:update()
    self:_resolve_client()
    self._blackboard:set("deps.nav.available", self._client ~= nil)
    self._blackboard:set("deps.nav.server_available", self:is_server_available())
    -- D4: Run stuck detection each frame.
    local player_pos = self._blackboard:get("player.position")
    local now = get_now()
    self:check_stuck(player_pos, now)
end

return NavigationAdapter
