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

-- ================================================================================
-- NAV IS A CONSUMER OF THE MOVEMENT CHANNEL, NOT A SECOND ARBITER OVER IT
-- ================================================================================
-- B4 gave this adapter its own owner/preemption mechanism, and the comment it shipped with
-- describes the case exactly: "combat holds ownership (chase_controller preempted a questing
-- Travel)". That is a BAND-ORDERED PREEMPTION, and the kernel's ControlBroker was built to
-- express precisely that -- with a resolved priority, a TTL, a generation stamp, and a
-- revocation that force-releases the keys AND stops navigation (ADR 08 §2.8, §6.1).
--
-- Two arbiters over one resource is what the broker exists to end. They disagree in the
-- direction that matters: the private gate could hand combat the client while the broker still
-- believed questing held MOVEMENT, so the intent path and the nav path were arbitrating the
-- same character against two different books.
--
-- WHAT THE BROKER REPLACES, CALLER BY CALLER:
--   * "unowned caller rejected by an owner"  -> a lower band cannot take a held channel
--     (`_plan_channel` returns "channel_held"; ties go to the incumbent).
--   * `preempt = true`                        -> COMBAT (50) outranks GOAL (30). Note this is
--     NOT a same-tick handover: the broker revokes the loser immediately -- safety cannot wait
--     to STOP something -- but withholds the grant for a cool-down tick to break the livelock
--     two retrying callers would otherwise sustain. Callers re-enter every tick, so they
--     converge one tick later than the private gate did.
--   * `release(owner)`                        -> hands the channel back so the next caller is
--     not rejected forever.
--   * `stop(reason)` with no owner            -> the holder stopping its own navigation.
--
-- ================================================================================
-- WHY `can_claim` SURVIVES AS A FALLBACK RATHER THAN BEING DELETED
-- ================================================================================
-- SentinelNavClient and the questing module both predate the kernel and run in configurations
-- where `_G.Sentinel` was never built. Deleting the private gate outright would leave those
-- callers with NO arbitration at all -- strictly worse than the second arbiter it replaces.
-- So: when a broker is reachable it is the ONLY arbiter consulted, and `can_claim` is dead
-- code; when none is, the old gate still holds the line. Exactly one arbiter is ever active.
--
-- THIS IS A PARTIAL RETIREMENT AND IT IS PARTIAL ON PURPOSE. The full one needs
-- chase_controller and combat/module.lua to acquire their own leases and stop passing
-- `owner`/`preempt` down here; until then those two callers still speak the old vocabulary and
-- this adapter still has to answer it.
local function can_claim(current_owner, new_owner, preempt)
    if current_owner == nil then
        return true
    end
    if current_owner == new_owner then
        return true
    end
    return preempt == true
end

--- Whoever drives navigation without naming themselves. Questing's `ctx.nav:move_to(pos, {})`
--- passes no owner at all, and a lease needs one, so the channel gets a name for it rather than
--- refusing the call.
local NAV_LEASE_OWNER = "sentinel.nav"

--- Two ticks: one to act, one of grace. The adapter renews on every `poll()` (which app.lua
--- registers in SENSE, every tick) and on every re-dispatch, so a lease only reaches expiry when
--- its driver has genuinely stopped watching -- a module unloaded mid-path, a faulted handler,
--- an activity popped off the stack. §6.1: "A plugin that faults mid-tick cannot permanently
--- hold MOVEMENT." With nav under the broker that sentence finally covers navigation, and the
--- expiry's force-release is what actually halts the character.
local NAV_LEASE_TTL_TICKS = 2

--- Map a legacy call onto a band. `opts.band` is the honest way to ask; the `preempt` shim is
--- there because chase_controller and combat/module.lua still speak B4's vocabulary and neither
--- is in this change's scope to edit.
local function band_for(opts)
    if type(opts.band) == "string" then
        return opts.band
    end
    if opts.preempt == true then
        return "COMBAT"
    end
    return "GOAL"
end

--- The adapter's ONE resolution of the live broker, mirroring `movement_release.live_input`.
---
--- `rawget` and a pcall'd read because `_G.Sentinel` is a read-only surface built by
--- `kernel/api.lua` whose fields resolve through `__index` at ACCESS time -- reaching for
--- `.control` before the kernel finished standing up must return nil, not throw on the nav path.
function NavAdapter:_broker()
    if self._broker_override ~= nil then
        return self._broker_override
    end
    local api = rawget(_G, "Sentinel")
    if api == nil then
        return nil
    end
    local ok, broker = pcall(function() return api.control end)
    if ok then
        return broker
    end
    return nil
end

---Inject a broker explicitly. Per-INSTANCE rather than a module-level static: a static would
---leak one test's arbiter into the next, and `get_shared` already hands distinct buses distinct
---adapters precisely so they stay isolated.
function NavAdapter:set_broker(broker)
    self._broker_override = broker
end

---Acquire (or renew) the MOVEMENT lease that authorises driving navigation.
---
---FAILS OPEN WITH NO BROKER, and that is the riskiest line in this change, so here is the
---reasoning. Failing closed would mean "no kernel" implies "no movement at all" -- a certain,
---total regression for every configuration that predates the kernel. The safety property this
---track exists to deliver (a revoked MOVEMENT lease stops navigation) is carried by
---`MovementRelease.release_all`, which needs no lease and enforces unconditionally. Absence of
---an arbiter is not the same as an arbiter's refusal.
---@return boolean claimed, string|nil reason
function NavAdapter:_claim_movement(opts)
    opts = opts or {}
    local broker = self:_broker()

    if broker == nil then
        if not can_claim(self._owner, opts.owner, opts.preempt) then
            return false, "owned_by_other"
        end
        self._owner = opts.owner
        return true
    end

    local request = {
        channel = "MOVEMENT",
        owner = opts.owner or NAV_LEASE_OWNER,
        band = band_for(opts),
        offset = tonumber(opts.offset) or 0,
        ttl_ticks = NAV_LEASE_TTL_TICKS,
        on_revoke = function(reason) self:_on_movement_revoked(reason) end,
    }

    local ok, caretaker, reason = pcall(function()
        return broker:acquire(request)
    end)
    if not ok then
        -- A throwing broker must not take navigation down with it: degrade to the same
        -- fail-open posture as no broker at all rather than wedging every caller.
        return true
    end
    if caretaker == nil then
        return false, reason or "movement_unavailable"
    end

    self._lease = caretaker
    self._lease_request = request
    self._owner = opts.owner
    return true
end

---The broker tore the lease away. It has already stopped the real client (§2.8's force-release
---now stops navigation, not just keys), so this only has to stop the adapter BELIEVING it is
---still navigating -- a stale `_active` is what makes an executor wait forever on a path that
---no longer exists.
function NavAdapter:_on_movement_revoked(reason)
    self._lease = nil
    self._lease_request = nil
    self._owner = nil
    self._last_dispatch = nil
    if self._active then
        self._active.state = "idle"
        self._active.stop_reason = "movement_revoked:" .. tostring(reason)
    end
end

---Hand the MOVEMENT channel back. Idempotent: a second call finds no lease and does nothing,
---which matters because `stop()` releases and chase_controller calls `stop` then `release`.
function NavAdapter:_release_movement()
    local lease = self._lease
    self._lease = nil
    self._lease_request = nil
    if lease == nil then
        return
    end
    local broker = self:_broker()
    if broker == nil then
        return
    end
    pcall(function() broker:release(lease) end)
end

---Renew the lease behind an in-flight navigation. Called from `poll()`, which is the one thing
---guaranteed to run every tick while a path is live.
---
---A renewal that FAILS is not a no-op: it means the channel went somewhere else, so the adapter
---must stop believing it is driving. It does not stop the client here -- whatever took MOVEMENT
---away already did, through the revocation path.
function NavAdapter:_renew_movement()
    if self._lease_request == nil then
        return
    end
    local broker = self:_broker()
    if broker == nil then
        return
    end
    local ok, caretaker = pcall(function()
        return broker:acquire(self._lease_request)
    end)
    if not ok then
        return
    end
    if caretaker == nil then
        self._lease = nil
        self._lease_request = nil
        return
    end
    self._lease = caretaker
end

-- Minimum seconds between identical move_to dispatches to the real client. The executor
-- re-enters its Travel handler every tick; without this window a silently-failing client
-- was re-commanded per FRAME to the same target, restarting its HSM faster than any async
-- path response could land (live-caught: 17k+ spin events at one waypoint). stop() clears
-- the window so stuck-recovery's stop→move_to genuinely re-dispatches.
local REDISPATCH_WINDOW = 2.0

local function same_target(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

function NavAdapter:move_to(target, opts)
    -- The claim happens BEFORE the debounce window below, deliberately: an executor re-entering
    -- its Travel handler every tick is exactly what renews the lease, and skipping the renewal
    -- on a debounced tick would let the TTL expire underneath a navigation that is fine.
    local claimed, claim_err = self:_claim_movement(opts)
    if not claimed then
        return false, claim_err
    end
    local now = (core and core.time and core.time()) or nil
    if now and self._last_dispatch
        and same_target(self._last_dispatch.target, target)
        and (now - self._last_dispatch.at) < REDISPATCH_WINDOW then
        -- Same command, still inside the window: treat as in flight, do not re-command
        -- the client's state machine.
        return true, nil
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
    -- The client reports the OUTCOME of a move only through this callback (ok=false with
    -- reason "unreachable" etc.) — see docs/SylvannasAPI/dev/api/sentinel-navigation.md.
    -- Passing nil silently discarded every pathfinding failure: the client dropped to
    -- idle, the adapter still claimed requesting_path, and the executor re-dispatched
    -- forever with no error visible anywhere (live-caught at op 37).
    local this_command = self._active
    local on_done = function(ok_result, reason)
        if ok_result then
            this_command.state = "arrived"
        else
            this_command.state = "failed"
            this_command.failures = (this_command.failures or 0) + 1
            self._last_error = {
                command = "move_to",
                reason = tostring(reason or "unknown"),
                at = (core and core.time and core.time()) or 0,
                target = { x = target.x, y = target.y, z = target.z },
            }
        end
    end
    local ok = select(1, invoke(client, "move_to", target, on_done, opts or {}))
    if not ok then
        self._active.state = "failed"
        return false, "move_to_dispatch_failed"
    end
    if now then
        self._last_dispatch = { target = { x = target.x, y = target.y, z = target.z }, at = now }
    end
    return true, nil
end

--- Most recent navigation failure reported by the client's completion callback, or nil.
--- { command, reason, at, target } — surfaced so the cockpit and the executor's blocked
--- reason can say WHY movement is failing instead of silently standing still.
function NavAdapter:get_last_error()
    return self._last_error
end

function NavAdapter:follow_path(nodes, opts)
    local claimed, claim_err = self:_claim_movement(opts)
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
    local claimed, claim_err = self:_claim_movement(opts)
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

-- Owner-scoped stop -- a caller that does not hold navigation cannot stop another caller's
-- motion. Under the broker this reads as "you must hold the lease to stop what it authorises":
-- questing arriving at a stale waypoint cannot halt combat's chase out from under it.
--
-- ================================================================================
-- THIS IS NOT THE KERNEL'S PATH, AND MUST NOT BECOME IT
-- ================================================================================
-- The scoping below is the reason `MovementRelease.release_all` resolves and calls the nav
-- client DIRECTLY instead of coming through here. A revocation arrives from the BROKER, which
-- is never `self._owner`, so a kernel force-release routed through this method would take the
-- early return, never touch the real client, and leave the character running -- while every
-- test that only watched key presses stayed green. `tests/kernel/test_nav_under_broker.lua`
-- holds an adapter under a foreign owner and demands the kernel's stop land anyway.
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
    -- An explicit stop invalidates the debounce window: whoever stops navigation is
    -- allowed to immediately re-dispatch the same target (stuck recovery does exactly
    -- stop → move_to).
    self._last_dispatch = nil
    -- Not navigating means not holding MOVEMENT. Squatting a channel it is no longer using is
    -- how this adapter blocked callers for whole seconds at a time before the broker existed.
    -- Idempotent, so the repeated `ctx.nav:stop("arrived")` an executor issues while parked on
    -- a waypoint costs one release and then nothing.
    self:_release_movement()
    return true
end

-- Release navigation. Only the current owner can clear it -- this is what lets the next tick's
-- questing Travel (or any other caller) take over after combat is done chasing. The MOVEMENT
-- lease goes back to the broker with it, because a channel held by nobody in particular is the
-- state the whole arbiter exists to avoid.
function NavAdapter:release(owner)
    if self._owner ~= owner then
        return false, "owned_by_other"
    end
    self:_release_movement()
    self._owner = nil
    return true
end

function NavAdapter:get_owner()
    return self._owner
end

---Which owner currently holds the MOVEMENT lease behind this adapter, per the BROKER rather
---than per this adapter's own bookkeeping. Nil when no broker is reachable or the channel is
---free. Exposed so a diagnostic can tell "the adapter thinks it owns nav" apart from "the
---arbiter agrees", which is precisely the disagreement the second arbiter used to hide.
function NavAdapter:get_movement_holder()
    local broker = self:_broker()
    if broker == nil then
        return nil
    end
    local ok, holder = pcall(function() return broker:who_owns("MOVEMENT") end)
    if not ok then
        return nil
    end
    return holder
end

function NavAdapter:poll()
    -- ADR 08 §7 registers this in SENSE, every tick, and it is the one thing guaranteed to run
    -- for as long as anybody is watching a path. That makes it the renewal point: a navigation
    -- still being polled must not have MOVEMENT expire underneath it, and one that stopped
    -- being polled SHOULD expire -- that is the whole value of a TTL on this channel.
    self:_renew_movement()

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
        -- A callback-reported failure is terminal for this command: the client drops
        -- to "idle" right after failing, and letting that poll overwrite the mark
        -- turned every pathfinding failure back into a silent no-op. Only a new
        -- dispatch (fresh _active) or an explicit stop() clears it.
        if self._active.state == "failed" then
            return "failed", progress
        end
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
