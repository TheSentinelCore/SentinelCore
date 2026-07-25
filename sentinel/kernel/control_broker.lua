-- kernel/control_broker.lua
-- The arbiter. ADR 08 §6.
--
-- ================================================================================
-- THE OBJECT-CAPABILITY SHAPE (ADR 08 §6.1)
-- ================================================================================
-- "All game-affecting calls hang off the lease, not off a global. Unauthorised action
--  becomes STRUCTURALLY IMPOSSIBLE rather than merely discouraged. This is the
--  object-capability pattern: authority travels with the reference, no ambient authority."
--
-- Two objects, deliberately distinct:
--
--   LEASE      Kernel-private. Holds the channels, the owner, the resolved priority, the
--              expiry tick, the generation and the on_revoke callback. A plugin never sees
--              one. If it could, it could re-arm its own expiry or forge a generation.
--
--   CARETAKER  What a plugin receives. PER-TICK: the kernel invalidates every caretaker at
--              tick end, so a stashed reference goes INERT rather than merely impolite
--              (§6.1). Its methods are closures over the lease; the table itself holds no
--              path to it.
--
-- ================================================================================
-- WHY PREEMPTION DOES NOT HAND OVER IN THE SAME TICK
-- ================================================================================
-- A holder that renews every tick and a preemptor that retries every tick can livelock: the
-- preemptor revokes, the loser re-acquires first on the next attempt, and the cycle repeats
-- forever while the character stutters. Two guards, both tick-denominated:
--
--   * CHANNEL COOL-DOWN. After a preemption the channel is unavailable to EVERYONE for
--     `cooldown_ticks`. `acquire` returns nil, "preemption_pending" -- the revocation and
--     force-release happen immediately (safety cannot wait), but the grant does not.
--   * PREEMPTED-OWNER BACKOFF. The specific loser is barred one tick longer than the general
--     cool-down, so it cannot win the handover race and restart the cycle. Without this the
--     cool-down alone does not converge when the loser asks first.
--
-- ================================================================================
-- TTL IS IN TICKS, NOT MILLISECONDS
-- ================================================================================
-- Deliberate. The real tick cadence is still unmeasured (ADR 08 §13 q7, and Phase 1's
-- TickClock is the instrument), so a millisecond TTL would be denominated in a unit whose
-- relationship to the tick loop nobody can yet state. "Two ticks" is exact regardless of
-- cadence; "32 ms" is two ticks or twenty depending on an answer we do not have.
--
-- ================================================================================
-- BANDS ARE NAMED
-- ================================================================================
-- ADR §6.1's sample sketches `priority = 60`, but §6.2 is the more specific statement: "the
-- manifest declares { band = "COMBAT", offset = 0 }" and bare integers are the documented
-- failure mode. So `acquire` takes band+offset and REFUSES a raw `priority`; the resolved
-- integer lives on the lease, which is what §6.1's sample was really describing.

local Bands = require("kernel/bands")
local MovementRelease = require("kernel/movement_release")

local ControlBroker = {}
ControlBroker.__index = ControlBroker

-- ADR 08 §2.2. Seven channels -- but NOT ADR-000's seven: CAMERA is deleted (§2.1, no camera
-- API exists anywhere in the SDK docs) and MODAL_UI is added (§2.2, vendor/bank/mail/trainer/
-- gossip/profession frames are modal and block movement, and reading a profession's skill
-- rank requires OPENING its window -- a sensor read that needs a control claim).
ControlBroker.CHANNELS = {
    "MOVEMENT",
    "FACING",
    "CASTING",
    "TARGETING",
    "INTERACTION",
    "ITEMS",
    "MODAL_UI",
}

ControlBroker.Channel = {}
local CHANNEL_SET = {}
for _, name in ipairs(ControlBroker.CHANNELS) do
    ControlBroker.Channel[name] = name
    CHANNEL_SET[name] = true
end

--- One tick of dead air after a preemption. Short enough that safety-band handover costs a
--- single frame; long enough to break the thrash cycle.
local DEFAULT_COOLDOWN_TICKS = 1

---@param opts table|nil { event_bus, input, cooldown_ticks, intent_queue }
function ControlBroker:new(opts)
    opts = opts or {}
    local o = setmetatable({}, ControlBroker)
    o._event_bus = opts.event_bus
    o._input = opts.input                    -- injected core.input double in tests
    o._intent_queue = opts.intent_queue
    o._cooldown_ticks = opts.cooldown_ticks or DEFAULT_COOLDOWN_TICKS

    o._held = {}                 -- channel -> lease
    o._cooling_until = {}        -- channel -> tick before which nobody may acquire
    o._preempted_until = {}      -- channel -> { owner -> tick before which THAT owner may not }
    o._live_caretakers = {}      -- caretakers issued this tick, invalidated at end_tick
    o._next_generation = 0
    o._tick_index = 0
    return o
end

function ControlBroker:set_intent_queue(queue)
    self._intent_queue = queue
end

function ControlBroker:_publish(event, payload)
    if not self._event_bus then return end
    pcall(function() self._event_bus:publish(event, payload) end)
end

-- ---------------------------------------------------------------------------
-- Revocation -- the safety-critical path (ADR 08 §2.8)
-- ---------------------------------------------------------------------------

--- Tear a lease down. `on_revoke` gets a chance to cooperate; the kernel then enforces the
--- outcome whether it cooperated, threw, declined, or was never provided.
---
--- ORDER MATTERS: notify, then unhook, then force-release. The force-release is last so it
--- is the final word -- if on_revoke pressed a key on its way out, the release still lands
--- after it.
function ControlBroker:_revoke(lease, reason)
    if lease._revoked then return false end
    lease._revoked = true

    -- 1. Ask. Inside pcall: a plugin's callback is third-party code on the safety path, and
    --    a throw here must not stop step 3.
    if type(lease.on_revoke) == "function" then
        pcall(lease.on_revoke, reason)
    end

    -- 2. Unhook, so nothing can re-enter through who_owns/is_generation_valid mid-teardown.
    local held_movement = false
    for _, channel in ipairs(lease.channels) do
        if self._held[channel] == lease then
            self._held[channel] = nil
        end
        if channel == ControlBroker.Channel.MOVEMENT then
            held_movement = true
        end
    end

    -- 3. ENFORCE. ADR 08 §2.8: movement is key-based start/stop, so a revoked MOVEMENT lease
    --    whose holder did not let go leaves the character RUNNING. The kernel does not ask;
    --    it releases. Unconditionally, regardless of what step 1 did.
    local release_report = nil
    if held_movement then
        release_report = MovementRelease.release_all(self._input)
    end

    self:_publish("control:revoked", {
        owner = lease.owner,
        channels = lease.channels,
        priority = lease.priority,
        band = lease.band,
        generation = lease.generation,
        reason = reason,
        movement_released = held_movement,
        release_errors = release_report and release_report.errors or 0,
    })

    return true
end

-- ---------------------------------------------------------------------------
-- Caretaker (ADR 08 §6.1)
-- ---------------------------------------------------------------------------

--- Build the per-tick wrapper a plugin receives.
---
--- The lease is captured in closures ONLY. The returned table's fields are all functions, so
--- `pairs(caretaker)` reveals no path to the lease -- "if a plugin can reach the lease, the
--- capability model is already broken."
---
--- Note what is deliberately ABSENT: any movement or cast verb. In Phase 2 the kernel's
--- force-release is the single `core.input.*` call site, so a caretaker that could press a
--- key would be a second one -- ambient authority handed straight back. Plugins act by
--- submitting intents, which the commit stage gates.
function ControlBroker:_issue_caretaker(lease)
    local broker = self
    local issued_tick = self._tick_index
    local stale = false

    local function valid()
        return not stale
            and not lease._revoked
            and issued_tick == broker._tick_index
    end

    local caretaker
    caretaker = {
        is_valid = function() return valid() end,
        owner = function() return lease.owner end,
        priority = function() return lease.priority end,
        band = function() return lease.band end,
        generation = function() return lease.generation end,
        channels = function()
            local out = {}
            for i, c in ipairs(lease.channels) do out[i] = c end
            return out
        end,
        has = function(_self, channel)
            -- Tolerate both call conventions; `channel` arrives as the sole arg when called
            -- with a dot rather than a colon.
            local wanted = channel or _self
            for _, c in ipairs(lease.channels) do
                if c == wanted then return true end
            end
            return false
        end,
        --- Emit an intent under this lease's authority. The generation stamp is what lets the
        --- commit stage reject an intent whose lease died later in the same tick (§6.1).
        submit = function(_self, intent)
            local payload = intent
            if payload == nil or type(payload) ~= "table" then payload = _self end
            if not valid() then return false, "caretaker_stale" end
            if not broker._intent_queue then return false, "no_intent_queue" end
            payload.owner = lease.owner
            payload.band = lease.priority
            payload.generation = lease.generation
            return broker._intent_queue:submit(payload)
        end,
        release = function() return broker:release(caretaker) end,
        renew = function(_self, ttl_ticks)
            if not valid() then return nil, "caretaker_stale" end
            return broker:acquire({
                channels = lease.channels,
                owner = lease.owner,
                band = lease.band,
                offset = lease.offset,
                ttl_ticks = ttl_ticks or lease.ttl_ticks,
                on_revoke = lease.on_revoke,
            })
        end,
        --- Kernel-internal: how end_tick makes a stashed reference inert.
        _invalidate = function() stale = true end,
    }

    self._caretaker_leases = self._caretaker_leases or setmetatable({}, { __mode = "k" })
    self._caretaker_leases[caretaker] = lease
    self._live_caretakers[#self._live_caretakers + 1] = caretaker
    return caretaker
end

-- ---------------------------------------------------------------------------
-- Acquisition
-- ---------------------------------------------------------------------------

local PLAN_FREE, PLAN_RENEW, PLAN_PREEMPT = "free", "renew", "preempt"

--- Decide what would happen on one channel, without doing it.
function ControlBroker:_plan_channel(channel, owner, priority)
    if self._cooling_until[channel] and self._tick_index < self._cooling_until[channel] then
        return nil, "channel_cooling"
    end

    local backoff = self._preempted_until[channel]
    if backoff and backoff[owner] and self._tick_index < backoff[owner] then
        return nil, "preempted_backoff"
    end

    local incumbent = self._held[channel]
    if incumbent == nil then
        return PLAN_FREE, nil
    end
    if incumbent.owner == owner then
        -- ADR 08 §6.1: "Re-acquire by the same owner is a RENEWAL, not a conflict."
        return PLAN_RENEW, nil
    end
    if priority > incumbent.priority then
        return PLAN_PREEMPT, nil
    end
    -- Ties go to the incumbent, which is what stops two same-band plugins trading a channel
    -- every tick.
    return nil, "channel_held"
end

---Acquire a lease.
---@param request table {
---   channel = "MOVEMENT" | channels = { ... },
---   owner = "sentinel.rotation.frost_mage",
---   band = "COMBAT", offset = 0, tier = "rotation"?,
---   ttl_ticks = 2,
---   on_revoke = function(reason) end,
--- }
---@return table|nil caretaker, string|nil reason
function ControlBroker:acquire(request)
    if type(request) ~= "table" then return nil, "invalid_request" end
    if type(request.owner) ~= "string" or request.owner == "" then return nil, "missing_owner" end
    if request.priority ~= nil then
        -- §6.2 -- bands are named. Accepting a raw integer here reintroduces the magic
        -- numbers the band table exists to abolish.
        return nil, "band_must_be_named"
    end
    if type(request.ttl_ticks) ~= "number" or request.ttl_ticks < 1 then
        -- Every lease expires. §6.1: "A plugin that faults mid-tick cannot permanently hold
        -- MOVEMENT."
        return nil, "missing_ttl_ticks"
    end

    local channels = {}
    if request.channels ~= nil then
        if type(request.channels) ~= "table" or #request.channels == 0 then
            return nil, "invalid_channels"
        end
        local seen = {}
        for _, channel in ipairs(request.channels) do
            if not CHANNEL_SET[channel] then return nil, "unknown_channel" end
            if not seen[channel] then
                seen[channel] = true
                channels[#channels + 1] = channel
            end
        end
    elseif request.channel ~= nil then
        if not CHANNEL_SET[request.channel] then return nil, "unknown_channel" end
        channels[1] = request.channel
    else
        return nil, "missing_channel"
    end

    local priority, band_reason = Bands.resolve({
        band = request.band, offset = request.offset, tier = request.tier,
    })
    if priority == nil then
        return nil, band_reason
    end

    -- PLAN EVERY CHANNEL BEFORE TOUCHING ANY. ADR 08's all-or-nothing rule: "Partial
    -- acquisition is how you get two plugins each holding one channel and deadlocking on the
    -- other." A revocation is a side effect, so a request that will fail must produce none.
    local plan = {}
    local needs_preemption = false
    for _, channel in ipairs(channels) do
        local outcome, reason = self:_plan_channel(channel, request.owner, priority)
        if outcome == nil then
            return nil, reason
        end
        plan[channel] = outcome
        if outcome == PLAN_PREEMPT then needs_preemption = true end
    end

    if needs_preemption then
        -- Revoke now -- safety cannot wait a tick to STOP something -- but do not grant.
        for _, channel in ipairs(channels) do
            if plan[channel] == PLAN_PREEMPT then
                local incumbent = self._held[channel]
                if incumbent then
                    local loser = incumbent.owner
                    self:_revoke(incumbent, "preempted")
                    self._cooling_until[channel] = self._tick_index + self._cooldown_ticks
                    self._preempted_until[channel] = self._preempted_until[channel] or {}
                    -- One tick longer than the general cool-down: otherwise the loser can win
                    -- the handover race and restart the preemption cycle.
                    self._preempted_until[channel][loser] =
                        self._tick_index + self._cooldown_ticks + 1
                end
            end
        end
        return nil, "preemption_pending"
    end

    -- Renewal: same grant, same generation. Keeping the generation is what stops a renewal
    -- from invalidating intents the owner already emitted this tick.
    local existing = nil
    for _, channel in ipairs(channels) do
        if plan[channel] == PLAN_RENEW then
            existing = self._held[channel]
            break
        end
    end

    if existing then
        existing.expires_at_tick = self._tick_index + request.ttl_ticks
        existing.ttl_ticks = request.ttl_ticks
        if request.on_revoke ~= nil then existing.on_revoke = request.on_revoke end
        -- Add any newly requested channels to the SAME lease, and leave channels it already
        -- held alone: renewing a subset must not quietly hand the rest back.
        for _, channel in ipairs(channels) do
            if self._held[channel] == nil then
                self._held[channel] = existing
                local already = false
                for _, c in ipairs(existing.channels) do
                    if c == channel then already = true break end
                end
                if not already then existing.channels[#existing.channels + 1] = channel end
            end
        end
        return self:_issue_caretaker(existing)
    end

    self._next_generation = self._next_generation + 1
    local lease = {
        owner = request.owner,
        channels = channels,
        priority = priority,
        band = request.band,
        offset = request.offset or 0,
        ttl_ticks = request.ttl_ticks,
        expires_at_tick = self._tick_index + request.ttl_ticks,
        generation = self._next_generation,
        on_revoke = request.on_revoke,
        _revoked = false,
    }
    for _, channel in ipairs(channels) do
        self._held[channel] = lease
    end

    self:_publish("control:granted", {
        owner = lease.owner, channels = channels, priority = priority,
        band = lease.band, generation = lease.generation,
    })
    return self:_issue_caretaker(lease)
end

---Voluntarily give a lease back.
---@return boolean released
function ControlBroker:release(caretaker)
    if type(caretaker) ~= "table" then return false end
    local lease = self._caretaker_leases and self._caretaker_leases[caretaker] or nil
    if lease == nil or lease._revoked then return false end

    lease._revoked = true
    local held_movement = false
    for _, channel in ipairs(lease.channels) do
        if self._held[channel] == lease then self._held[channel] = nil end
        if channel == ControlBroker.Channel.MOVEMENT then held_movement = true end
    end

    -- A voluntary release is cooperation, so on_revoke does NOT fire -- but the keys still
    -- come up. The kernel cannot verify that a releasing holder actually let go, and a lease
    -- that no longer exists must not be able to leave the character running.
    if held_movement then
        MovementRelease.release_all(self._input)
    end

    self:_publish("control:released", {
        owner = lease.owner, channels = lease.channels, generation = lease.generation,
    })
    return true
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

---@return string|nil owner, number|nil priority
function ControlBroker:who_owns(channel)
    local lease = self._held[channel]
    if lease == nil then return nil end
    return lease.owner, lease.priority
end

---@return table channel -> { owner, priority, band, generation, expires_at_tick }
function ControlBroker:holdings()
    local out = {}
    for channel, lease in pairs(self._held) do
        out[channel] = {
            owner = lease.owner,
            priority = lease.priority,
            band = lease.band,
            generation = lease.generation,
            expires_at_tick = lease.expires_at_tick,
        }
    end
    return out
end

---The ControlBroker half of ADR 08 §6.1's generation check, wired into
---`IntentQueue:set_generation_validator`.
---
---"Every lease carries a monotonic generation, re-checked at the commit point. This closes
--- the revocation race where an intent emitted under a now-dead lease still commits."
---
---An intent with no generation is INVALID, not exempt: no lease means no authority, and an
---exemption here would be the ambient-authority hole the whole design exists to close.
---@return boolean
function ControlBroker:is_generation_valid(intent)
    if type(intent) ~= "table" then return false end
    if type(intent.generation) ~= "number" then return false end
    for _, lease in pairs(self._held) do
        if lease.generation == intent.generation and not lease._revoked then
            -- A generation is not a bearer token: it must match the owner that was granted it.
            return lease.owner == intent.owner
        end
    end
    return false
end

---Hand one channel from its current holder to a service, under the holder's authority
---(ADR 08 §6.4's `control:delegate`).
---
---Lease surgery, so it lives here rather than in the ActivityStack: the channel is detached
---from the delegator's lease and a NEW lease is granted to the service at the SAME priority.
---Same priority because the service acts under the delegator's authority, not its own -- a
---combat service invoked by a GOAL activity must not outrank that activity.
---
---The delegator keeps every other channel on its lease. That is the whole point: §6.4's
---"delegates CASTING+TARGETING, keeps MOVEMENT".
---@return table|nil caretaker, string|nil reason
function ControlBroker:delegate(channel, from_owner, to_owner, policy)
    if not CHANNEL_SET[channel] then return nil, "unknown_channel" end
    if type(to_owner) ~= "string" or to_owner == "" then return nil, "missing_service_id" end

    local lease = self._held[channel]
    if lease == nil or lease.owner ~= from_owner then
        return nil, "channel_not_held_by_delegator"
    end
    if to_owner == from_owner then return nil, "cannot_delegate_to_self" end

    -- Detach the channel from the delegator's lease, leaving its other channels intact.
    for i, c in ipairs(lease.channels) do
        if c == channel then
            table.remove(lease.channels, i)
            break
        end
    end
    self._held[channel] = nil

    -- MOVEMENT changes hands with the keys UP. The kernel cannot know that the incoming
    -- holder wants the same keys down, and a key held across a change of authority is exactly
    -- the ambiguity ADR 08 §2.8 warns about. The new holder presses what it needs.
    if channel == ControlBroker.Channel.MOVEMENT then
        MovementRelease.release_all(self._input)
    end

    self._next_generation = self._next_generation + 1
    local delegated = {
        owner = to_owner,
        channels = { channel },
        priority = lease.priority,
        band = lease.band,
        offset = lease.offset,
        ttl_ticks = lease.ttl_ticks,
        expires_at_tick = lease.expires_at_tick,
        generation = self._next_generation,
        on_revoke = nil,
        delegated_from = from_owner,
        policy = policy,
        _revoked = false,
    }
    self._held[channel] = delegated

    self:_publish("control:delegated", {
        channel = channel, from = from_owner, to = to_owner,
        priority = delegated.priority, generation = delegated.generation,
    })
    return self:_issue_caretaker(delegated)
end

---Revoke every lease held by `owner`. Used when an activity leaves the stack: its
---delegations must not outlive it.
---@return number revoked count
function ControlBroker:revoke_owner(owner, reason)
    local doomed = {}
    for _, lease in pairs(self._held) do
        if lease.owner == owner and not lease._revoked then doomed[lease] = true end
    end
    local count = 0
    for lease in pairs(doomed) do
        if self:_revoke(lease, reason or "owner_revoked") then count = count + 1 end
    end
    return count
end

---Revoke every lease delegated FROM `owner`, wherever it now sits.
---@return number revoked count
function ControlBroker:revoke_delegations_from(owner, reason)
    local doomed = {}
    for _, lease in pairs(self._held) do
        if lease.delegated_from == owner and not lease._revoked then doomed[lease] = true end
    end
    local count = 0
    for lease in pairs(doomed) do
        if self:_revoke(lease, reason or "delegator_gone") then count = count + 1 end
    end
    return count
end

---Revoke every lease strictly below `priority`. This is what an ActivityStack push at band
---90 needs (ADR 08 §6.4: "death pushes at band 90, revokes everything").
---@return number revoked count
function ControlBroker:revoke_below(priority, reason)
    local doomed = {}
    for _, lease in pairs(self._held) do
        if lease.priority < priority and not lease._revoked then
            doomed[lease] = true
        end
    end
    local count = 0
    for lease in pairs(doomed) do
        if self:_revoke(lease, reason or "revoked_below") then count = count + 1 end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Tick lifecycle
-- ---------------------------------------------------------------------------

---The ARBITRATE stage (ADR 08 §7 step 4): "ControlBroker resolves leases, fires revocations,
---force-releases keys." In that order -- expiry is decided first over a stable view, then
---each expired lease is torn down (which is what fires on_revoke and forces the key release).
---@param tick_index number
---Publish the current tick index to the broker.
---
---Called at the TOP of the tick, before INTERRUPT. ADR 08 §7 puts INTERRUPT (step 3) ahead of
---ARBITRATE (step 4), and a safety evaluator running at step 3 may acquire -- which consults
---cool-downs and backoffs, both tick-denominated. If the index only advanced at step 4 those
---windows would be evaluated one tick stale for the whole INTERRUPT stage.
---
---This does no arbitration. Expiry, revocation and key release all stay in `arbitrate()`,
---where §7 says they belong.
function ControlBroker:begin_tick(tick_index)
    if type(tick_index) == "number" then
        self._tick_index = tick_index
    end
end

function ControlBroker:arbitrate(tick_index)
    self._tick_index = tick_index or (self._tick_index + 1)

    -- 1. RESOLVE: collect expiries against a stable snapshot of holdings, so a revocation's
    --    side effects cannot perturb the set being iterated.
    local expired = {}
    for _, lease in pairs(self._held) do
        if not lease._revoked and self._tick_index >= lease.expires_at_tick then
            expired[lease] = true
        end
    end

    -- 2. FIRE REVOCATIONS + 3. FORCE-RELEASE KEYS (both inside _revoke, in that order).
    local count = 0
    for lease in pairs(expired) do
        if self:_revoke(lease, "ttl_expired") then count = count + 1 end
    end

    -- 4. Retire cool-downs that have run out, so the tables do not grow forever.
    for channel, until_tick in pairs(self._cooling_until) do
        if self._tick_index >= until_tick then self._cooling_until[channel] = nil end
    end
    for channel, owners in pairs(self._preempted_until) do
        for owner, until_tick in pairs(owners) do
            if self._tick_index >= until_tick then owners[owner] = nil end
        end
        if next(owners) == nil then self._preempted_until[channel] = nil end
    end

    return count
end

---Invalidate every caretaker issued this tick (ADR 08 §6.1: "the kernel flips its `revoked`
---flag at TICK END, not the lease itself"). Runs in ACCOUNT -- after COMMIT -- so intents
---emitted this tick still validate against their live leases.
---
---The LEASES survive. Only the plugin-facing wrappers go stale, which is why a renewal on the
---next tick returns a fresh caretaker over the same grant and the same generation.
function ControlBroker:end_tick()
    for _, caretaker in ipairs(self._live_caretakers) do
        caretaker._invalidate()
    end
    self._live_caretakers = {}
end

function ControlBroker:tick_index()
    return self._tick_index
end

return ControlBroker
