-- kernel/activity_stack.lua
-- One active Activity; interrupts push and pop. ADR 08 §6.4.
--
--   [ Grind ]                     <- base activity, holds all channels
--   [ Grind -> Combat(policy) ]   <- delegates CASTING+TARGETING, keeps MOVEMENT
--   [ Grind -> Recover ]          <- death pushes at band 90, revokes everything below
--
-- ================================================================================
-- WHY A STACK RATHER THAN A PRIORITY LIST
-- ================================================================================
-- ADR 08 §3.1: combat "is not a goal -- it is an INTERRUPTION to a goal". The current
-- module_registry runs combat and questing as peers at fixed priorities 10 and 50, which
-- cannot express "the thing that was running is still what we are trying to do". A stack can:
-- the interrupted activity stays on the stack, suspended, and resumes when the interrupt pops.
--
-- ================================================================================
-- WHAT A PUSH REVOKES, AND WHAT IT DOES NOT
-- ================================================================================
-- A push revokes every lease STRICTLY BELOW the incoming activity's priority (§6.4: "death
-- pushes at band 90, revokes everything"). It does not touch leases at or above its own
-- priority: a push is an interrupt, not a reset, and revoking the safety net because a goal
-- activity started would invert the bands.
--
-- Resumption does NOT restore leases. Leases are TTL-bounded (§6.1) and would have expired
-- during any interrupt worth having, so a resumed activity re-acquires what it needs. Pretending
-- to hand a lease back across a suspension would be handing back an expired one.

local Bands = require("kernel/bands")

local ActivityStack = {}
ActivityStack.__index = ActivityStack

---@param opts table { broker, event_bus }
function ActivityStack:new(opts)
    opts = opts or {}
    local o = setmetatable({}, ActivityStack)
    o._broker = opts.broker
    o._event_bus = opts.event_bus
    o._stack = {}
    o._evaluators = {}
    o._delegations = {} -- channel -> { service_id, policy, delegator }
    return o
end

function ActivityStack:broker()
    return self._broker
end

function ActivityStack:_publish(event, payload)
    if not self._event_bus then return end
    pcall(function() self._event_bus:publish(event, payload) end)
end

-- ---------------------------------------------------------------------------
-- Stack
-- ---------------------------------------------------------------------------

---@return table|nil the active activity
function ActivityStack:current()
    return self._stack[#self._stack]
end

function ActivityStack:depth()
    return #self._stack
end

---Push an activity, suspending whatever was running.
---@param activity table { id, band, offset?, tier?, on_suspend?, on_resume? }
---@return table|nil activity, string|nil reason
function ActivityStack:push(activity)
    if type(activity) ~= "table" then return nil, "invalid_activity" end
    if type(activity.id) ~= "string" or activity.id == "" then return nil, "missing_id" end
    if activity.priority ~= nil then
        -- ADR 08 §6.2 -- named bands only. See kernel/bands.lua.
        return nil, "band_must_be_named"
    end

    local priority, reason = Bands.resolve({
        band = activity.band, offset = activity.offset, tier = activity.tier,
    })
    if priority == nil then return nil, reason end

    local previous = self:current()
    if previous and type(previous.on_suspend) == "function" then
        -- Third-party code on the interrupt path: a throwing on_suspend must not prevent the
        -- interrupt from taking over. A corpse run cannot be blocked by a buggy grind loop.
        pcall(previous.on_suspend, previous)
    end

    activity.priority = priority
    self._stack[#self._stack + 1] = activity

    -- §6.4 -- clear the channels held below us so the incoming activity can claim them.
    local revoked = 0
    if self._broker then
        revoked = self._broker:revoke_below(priority, "activity_push")
    end

    self:_publish("activity:pushed", {
        id = activity.id, priority = priority, band = activity.band,
        depth = #self._stack, revoked = revoked,
    })
    return activity
end

---Pop the active activity and resume the one beneath it.
---@return table|nil the popped activity
function ActivityStack:pop()
    local popped = table.remove(self._stack)
    if popped == nil then return nil end

    if self._broker then
        -- A delegation is authority lent by this activity. It cannot outlive the lender.
        self._broker:revoke_delegations_from(popped.id, "delegator_popped")
        self._broker:revoke_owner(popped.id, "activity_popped")
    end
    for channel, delegation in pairs(self._delegations) do
        if delegation.delegator == popped.id then
            self._delegations[channel] = nil
        end
    end

    local resumed = self:current()
    if resumed and type(resumed.on_resume) == "function" then
        pcall(resumed.on_resume, resumed)
    end

    self:_publish("activity:popped", {
        id = popped.id, depth = #self._stack,
        resumed = resumed and resumed.id or nil,
    })
    return popped
end

-- ---------------------------------------------------------------------------
-- Delegation (ADR 08 §6.4)
-- ---------------------------------------------------------------------------

---Hand a channel to a service under the active activity's authority.
---
---    ctx.control:delegate(Channel.CASTING, "service.combat",
---                         { policy = "objective", leash = 30, allow_adds = false })
---
---This is how "combat is a service invoked with a policy" (§3.1) becomes concrete: the
---activity decides the stance, the service executes it, and the activity keeps every channel
---it did not hand over.
---@return table|nil service caretaker, string|nil reason
function ActivityStack:delegate(channel, service_id, policy)
    local activity = self:current()
    if activity == nil then return nil, "no_active_activity" end
    if not self._broker then return nil, "no_broker" end

    local caretaker, reason = self._broker:delegate(channel, activity.id, service_id, policy)
    if caretaker == nil then
        if reason == "channel_not_held_by_delegator" then
            -- Named from the caller's point of view: the activity cannot lend what it never had.
            return nil, "channel_not_held_by_activity"
        end
        return nil, reason
    end

    self._delegations[channel] = {
        service_id = service_id,
        policy = policy or {},
        delegator = activity.id,
    }
    return caretaker
end

---@return table|nil { service_id, policy, delegator }
function ActivityStack:delegation(channel)
    return self._delegations[channel]
end

-- ---------------------------------------------------------------------------
-- INTERRUPT stage (ADR 08 §7 step 3)
-- ---------------------------------------------------------------------------

---Register a safety evaluator. Called with `(ctx, stack)` so it can push or pop.
function ActivityStack:register_evaluator(name, fn)
    if type(name) ~= "string" or name == "" then error("an evaluator must be named", 0) end
    if type(fn) ~= "function" then error("evaluator '" .. name .. "' must be a function", 0) end
    self._evaluators[#self._evaluators + 1] = { name = name, fn = fn }
    return self
end

---Run every evaluator. "Safety evaluators may push/pop the ActivityStack" (§7 step 3).
---
---Each is isolated: an evaluator IS the trigger for a safety net, so one that throws must not
---disarm the ones after it. Faults are counted and returned rather than swallowed.
---@return table report { evaluated, faults, errors }
function ActivityStack:evaluate(ctx)
    local report = { evaluated = 0, faults = 0, errors = {} }
    for _, evaluator in ipairs(self._evaluators) do
        report.evaluated = report.evaluated + 1
        local ok, err = pcall(evaluator.fn, ctx, self)
        if not ok then
            report.faults = report.faults + 1
            report.errors[#report.errors + 1] = { name = evaluator.name, error = tostring(err) }
            self:_publish("activity:evaluator_fault", {
                name = evaluator.name, error = tostring(err),
            })
        end
    end
    return report
end

return ActivityStack
