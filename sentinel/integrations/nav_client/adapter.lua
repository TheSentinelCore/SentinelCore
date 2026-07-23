local Geometry = require("core/geometry")

local NavAdapter = {}
NavAdapter.__index = NavAdapter

local function num(value)
    return tonumber(value) or 0
end

local function invoke(owner, method, ...)
    if not owner or type(owner[method]) ~= "function" then
        return false, nil, nil
    end
    -- Try method call (obj:method(...))
    local ok, a, b = pcall(owner[method], owner, ...)
    if ok then
        return true, a, b
    end
    -- Silently fail - method exists but threw an error
    -- This is intentional: the method call itself failed
    return false, nil, nil
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
    o._owner = nil -- B4: whichever caller (e.g. "combat") currently holds this adapter
    return o
end

-- B4: three call sites (app.lua, combat/init.lua, runtime_profile.lua) each used to
-- construct their own private NavAdapter wrapping the single _G.SentinelNavClient.client,
-- so each kept its own belief about whether nav was active and questing/combat stole the
-- client from each other silently. All three now share ONE adapter instance per EventBus:
-- production always threads the same event_bus down from SentinelApp, so this collapses
-- them onto a single adapter without changing any constructor signatures. Distinct
-- EventBus instances (as most offline tests construct) naturally get distinct adapters,
-- so tests stay isolated. The cache is keyed weakly so unreferenced buses can be GC'd.
local _shared_by_bus = setmetatable({}, { __mode = "k" })

function NavAdapter.get_shared(event_bus)
    if event_bus == nil then
        -- No bus to key on -- caller gets its own private instance (matches old behavior).
        return NavAdapter:new(event_bus)
    end
    local existing = _shared_by_bus[event_bus]
    if existing then
        return existing
    end
    local instance = NavAdapter:new(event_bus)
    _shared_by_bus[event_bus] = instance
    return instance
end

function NavAdapter:_client()
    local root = rawget(_G, "SentinelNavClient")
    return root and root.client or nil
end

-- B4: ownership gate shared by move_to/follow_path/plan_route. `nil` means "unowned" --
-- once a caller claims the adapter with `opts.owner`, every other caller (including one
-- that passes no owner at all) is rejected until the owner calls `release`, unless the
-- new caller sets `opts.preempt` (e.g. combat interrupting an in-flight questing Travel).
-- VERIFY-IN-GAME: with a live SentinelNavClient, confirm that while combat holds
-- ownership (chase_controller preempted a questing Travel), a subsequent unowned
-- questing move_to (ctx.nav:move_to in runtime_action.lua / runtime_profile.lua) is
-- rejected at the ADAPTER level (returns false, "owned_by_other") *and* the underlying
-- client:move_to is never dispatched -- i.e. combat's in-flight path is not silently
-- overwritten by questing re-issuing its Travel mid-chase.
local function can_claim(current_owner, new_owner, preempt)
    if current_owner == nil then
        return true
    end
    if current_owner == new_owner then
        return true
    end
    return preempt == true
end

function NavAdapter:_claim_or_reject(opts)
    opts = opts or {}
    if not can_claim(self._owner, opts.owner, opts.preempt) then
        return false, "owned_by_other"
    end
    self._owner = opts.owner
    return true
end

function NavAdapter:move_to(target, opts)
    local claimed, claim_err = self:_claim_or_reject(opts)
    if not claimed then
        return false, claim_err
    end
    local client = self:_client()
    self._active = {
        command = "move_to",
        target = target,
        opts = opts or {},
        state = "requesting_path",
        started = false,
        failures = 0,
        owner = self._owner,
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
    local claimed, claim_err = self:_claim_or_reject(opts)
    if not claimed then
        return false, claim_err
    end
    local client = self:_client()
    self._active = {
        command = "follow_path",
        nodes = nodes,
        opts = opts or {},
        state = "requesting_path",
        started = false,
        failures = 0,
        owner = self._owner,
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
    local claimed, claim_err = self:_claim_or_reject(opts)
    if not claimed then
        return false, claim_err
    end
    local client = self:_client()
    self._active = {
        command = "plan_route",
        nodes = nodes,
        opts = opts or {},
        state = "requesting_path",
        started = false,
        failures = 0,
        owner = self._owner,
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

-- B4: owner-scoped stop -- a non-owner cannot stop another owner's motion. `owner` is
-- optional for backward compatibility: when nobody currently owns the adapter, any
-- caller may stop it (matches pre-B4 behavior for callers that never declare an owner).
-- VERIFY-IN-GAME: with a live client, confirm that while combat owns the adapter, a
-- questing `ctx.nav:stop(reason)` call (no owner arg, so `owner == nil ~= "combat"`)
-- returns false and does NOT call the real client's stop() -- i.e. questing arriving
-- at a stale waypoint cannot halt combat's chase movement out from under it.
function NavAdapter:stop(reason, owner)
    if self._owner ~= nil and self._owner ~= owner then
        return false, "owned_by_other"
    end
    local client = self:_client()
    invoke(client, "stop")
    if self._active then
        self._active.state = "idle"
        self._active.stop_reason = reason or "stop"
    end
    return true
end

-- B4: release ownership. Only the current owner can clear it -- this is what lets the
-- next tick's questing Travel (or any other caller) re-claim the adapter after combat
-- is done chasing.
function NavAdapter:release(owner)
    if self._owner ~= owner then
        return false, "owned_by_other"
    end
    self._owner = nil
    return true
end

function NavAdapter:get_owner()
    return self._owner
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
                    progress.distance_remaining = Geometry.distance(player_pos, progress.destination)
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
