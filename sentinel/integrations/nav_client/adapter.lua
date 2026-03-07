local NavAdapter = {}
NavAdapter.__index = NavAdapter

local function num(value)
    return tonumber(value) or 0
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 0
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function invoke(owner, method, ...)
    if not owner or type(owner[method]) ~= "function" then
        return false, nil, nil
    end
    local fn = owner[method]
    local ok, a, b = pcall(fn, owner, ...)
    if ok then
        return true, a, b
    end
    return pcall(fn, ...)
end

local function normalize_state(state, full_state)
    local top = tostring(state or "idle")
    local full = tostring(full_state or "")
    if top ~= "navigating" then
        return top
    end
    if full:find("awaiting_path", 1, true) or full:find("repathing", 1, true) or full:find("deferred", 1, true) then
        return "requesting_path"
    end
    if full:find("recovering", 1, true) then
        return "stuck"
    end
    return "moving"
end

function NavAdapter:new(event_bus)
    local o = setmetatable({}, NavAdapter)
    o._event_bus = event_bus
    o._active = nil
    o._last_state = "idle"
    o._last_progress = nil
    o._last_full_state = "idle"
    return o
end

function NavAdapter:_client()
    local root = rawget(_G, "SentinelNavClient")
    return root and root.client or nil
end

function NavAdapter:move_to(target, opts)
    local client = self:_client()
    self._active = {
        command = "move_to",
        target = target,
        opts = opts or {},
        state = "requesting_path",
        started = false,
        failures = 0,
    }
    if not client then
        self._active.state = "failed"
        return false, "client_unavailable"
    end
    local ok = select(1, invoke(client, "move_to", target, nil, opts or {}))
    if not ok then
        self._active.state = "failed"
        return false, "move_to_dispatch_failed"
    end
    return true, nil
end

function NavAdapter:follow_path(nodes, opts)
    local client = self:_client()
    self._active = {
        command = "follow_path",
        nodes = nodes,
        opts = opts or {},
        state = "requesting_path",
        started = false,
        failures = 0,
    }
    if not client then
        self._active.state = "failed"
        return false, "client_unavailable"
    end

    local ok = false
    if type(nodes) == "table" and #nodes > 0 and type(client.follow_path) == "function" then
        ok = select(1, invoke(client, "follow_path", nodes, nil, { preserve_route_session = false }))
    end

    if not ok then
        self._active.state = "failed"
        return false, "follow_path_dispatch_failed"
    end
    return true, nil
end

function NavAdapter:plan_route(nodes, opts)
    local client = self:_client()
    self._active = {
        command = "plan_route",
        nodes = nodes,
        opts = opts or {},
        state = "requesting_path",
        started = false,
        failures = 0,
    }
    if not client then
        self._active.state = "failed"
        return false, "client_unavailable"
    end

    local ok = false
    if type(nodes) == "table" and #nodes > 0 and type(client.start_route) == "function" then
        ok = select(1, invoke(client, "start_route", nodes, nil, opts or {}))
    elseif type(nodes) == "table" and #nodes > 0 and type(client.plan_route) == "function" then
        ok = select(1, invoke(client, "plan_route", nodes, nil, opts or {}))
    end

    if not ok then
        self._active.state = "failed"
        return false, "plan_route_dispatch_failed"
    end
    return true, nil
end

function NavAdapter:stop(reason)
    local client = self:_client()
    invoke(client, "stop")
    if self._active then
        self._active.state = "idle"
        self._active.stop_reason = reason or "stop"
    end
end

function NavAdapter:poll()
    local client = self:_client()
    local state = "idle"
    local full_state = "idle"
    local progress = {}

    if client then
        local ok_state, raw_state = invoke(client, "get_state")
        if ok_state and type(raw_state) == "string" then
            state = raw_state
        end

        local ok_full, raw_full_state = invoke(client, "get_full_state")
        if ok_full and type(raw_full_state) == "string" then
            full_state = raw_full_state
        end

        local ok_progress, raw_progress = invoke(client, "get_progress")
        if ok_progress and type(raw_progress) == "table" then
            progress = raw_progress
        end

        local ok_dest, destination = invoke(client, "get_destination")
        if ok_dest and type(destination) == "table" then
            progress.destination = destination
        end

        local ok_index, path_index = invoke(client, "get_path_index")
        if ok_index and tonumber(path_index) then
            progress.path_index = tonumber(path_index)
        else
            progress.path_index = tonumber(progress.current_index) or 1
        end

        local ok_path, path = invoke(client, "get_current_path")
        if ok_path and type(path) == "table" then
            progress.path_count = #path
        else
            progress.path_count = tonumber(progress.total_waypoints) or 0
        end

        if progress.destination and core and core.object_manager and type(core.object_manager.get_local_player) == "function" then
            local ok_player, player = pcall(core.object_manager.get_local_player)
            if ok_player and player and type(player.get_position) == "function" then
                local ok_pos, player_pos = pcall(player.get_position, player)
                if ok_pos and type(player_pos) == "table" then
                    progress.distance_remaining = distance(player_pos, progress.destination)
                end
            end
        end
    elseif self._active then
        state = "failed"
        full_state = "failed"
    end

    local normalized_state = normalize_state(state, full_state)
    progress.state = normalized_state
    progress.route_mode = progress.route_mode == true

    self._last_state = normalized_state
    self._last_full_state = full_state
    self._last_progress = progress
    if self._active then
        self._active.state = normalized_state
        self._active.progress = progress
        if normalized_state == "failed" then
            self._active.failures = (self._active.failures or 0) + 1
        end
    end

    return normalized_state, progress
end

function NavAdapter:is_active()
    if not self._active then
        return false
    end
    local state = self._active.state or self._last_state
    return state == "requesting_path" or state == "moving" or state == "stuck"
end

function NavAdapter:get_state()
    if self._active then
        return self._active.state or self._last_state
    end
    return self._last_state
end

function NavAdapter:get_progress()
    return self._last_progress
end

function NavAdapter:get_active_command()
    return self._active
end

return NavAdapter
