-- NavAdapter.lua — Wraps _G.SentinelNavClient.client for duo use.
-- Requires SentinelNavClient to be loaded before SentinelDuoFarm.

local NavAdapter = {}
NavAdapter.__index = NavAdapter

local function num(value)
    return tonumber(value) or 0
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return 0 end
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
    if ok then return true, a, b end
    return pcall(fn, ...)
end

local function normalize_state(state, full_state)
    local top  = tostring(state or "idle")
    local full = tostring(full_state or "")
    if top ~= "navigating" then return top end
    if full:find("awaiting_path", 1, true) or full:find("repathing", 1, true) or full:find("deferred", 1, true) then
        return "requesting_path"
    end
    if full:find("recovering", 1, true) then return "stuck" end
    return "moving"
end

---@return NavAdapter
function NavAdapter:new()
    return setmetatable({
        _active         = nil,
        _last_state     = "idle",
        _last_progress  = nil,
        _last_full_state = "idle",
    }, NavAdapter)
end

function NavAdapter:_client()
    local root = rawget(_G, "SentinelNavClient")
    return root and root.client or nil
end

---@param target table  vec3
---@param opts table|nil
---@return boolean, string|nil
function NavAdapter:move_to(target, opts)
    local client = self:_client()
    self._active = {
        command = "move_to",
        target  = target,
        opts    = opts or {},
        state   = "requesting_path",
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

---@param nodes table  array of vec3
---@param opts table|nil
---@return boolean, string|nil
function NavAdapter:follow_path(nodes, opts)
    local client = self:_client()
    self._active = {
        command  = "follow_path",
        nodes    = nodes,
        opts     = opts or {},
        state    = "requesting_path",
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

---@param reason string|nil
function NavAdapter:stop(reason)
    local client = self:_client()
    invoke(client, "stop")
    if self._active then
        self._active.state = "idle"
        self._active.stop_reason = reason or "stop"
    end
end

---@return string, table  normalized_state, progress
function NavAdapter:poll()
    local client     = self:_client()
    local state      = "idle"
    local full_state = "idle"
    local progress   = {}

    if client then
        local ok_s, raw_s = invoke(client, "get_state")
        if ok_s and type(raw_s) == "string" then state = raw_s end

        local ok_f, raw_f = invoke(client, "get_full_state")
        if ok_f and type(raw_f) == "string" then full_state = raw_f end

        local ok_p, raw_p = invoke(client, "get_progress")
        if ok_p and type(raw_p) == "table" then progress = raw_p end

        local ok_d, dest = invoke(client, "get_destination")
        if ok_d and type(dest) == "table" then progress.destination = dest end

        local ok_i, path_idx = invoke(client, "get_path_index")
        if ok_i and tonumber(path_idx) then
            progress.path_index = tonumber(path_idx)
        else
            progress.path_index = tonumber(progress.current_index) or 1
        end

        local ok_path, path = invoke(client, "get_current_path")
        if ok_path and type(path) == "table" then
            progress.path_count = #path
        else
            progress.path_count = tonumber(progress.total_waypoints) or 0
        end

        if progress.destination then
            local ok_pl, player = pcall(core.object_manager.get_local_player)
            if ok_pl and player and type(player.get_position) == "function" then
                local ok_pos, pos = pcall(player.get_position, player)
                if ok_pos and type(pos) == "table" then
                    progress.distance_remaining = distance(pos, progress.destination)
                end
            end
        end
    elseif self._active then
        state      = "failed"
        full_state = "failed"
    end

    local norm = normalize_state(state, full_state)
    progress.state      = norm
    progress.route_mode = progress.route_mode == true

    self._last_state      = norm
    self._last_full_state = full_state
    self._last_progress   = progress

    if self._active then
        self._active.state    = norm
        self._active.progress = progress
        if norm == "failed" then
            self._active.failures = (self._active.failures or 0) + 1
        end
    end

    return norm, progress
end

---@return boolean
function NavAdapter:is_active()
    if not self._active then return false end
    local s = self._active.state or self._last_state
    return s == "requesting_path" or s == "moving" or s == "stuck"
end

---@return string
function NavAdapter:get_state()
    if self._active then
        return self._active.state or self._last_state
    end
    return self._last_state
end

return NavAdapter
