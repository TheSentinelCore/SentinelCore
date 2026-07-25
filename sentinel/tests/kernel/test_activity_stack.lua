-- tests/kernel/test_activity_stack.lua
-- ADR 08 §6.4 -- one active Activity; interrupts push and pop.
--
--   [ Grind ]                     <- base activity, holds all channels
--   [ Grind -> Combat(policy) ]   <- delegates CASTING+TARGETING, keeps MOVEMENT
--   [ Grind -> Recover ]          <- death pushes at band 90, revokes everything below
--
-- The middle line is the one that justifies the whole channel design (§6.1): "This is what
-- buys kiting: the rotation holds CASTING+TARGETING while the activity keeps MOVEMENT and
-- backpedals. The current fixed-priority module design cannot express that at all."
--
-- Wired into the INTERRUPT stage (§7 step 3: "safety evaluators may push/pop the
-- ActivityStack").

local ActivityStack = require("kernel/activity_stack")
local ControlBroker = require("kernel/control_broker")
local Channel = ControlBroker.Channel
local MovementRelease = require("kernel/movement_release")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

local function make_stack()
    local stopped = {}
    local input = {}
    for _, key in ipairs(MovementRelease.KEYS) do
        input[key .. "_stop"] = function() stopped[#stopped + 1] = key end
    end
    local bus = EventBus:new(function() end)
    local broker = ControlBroker:new({ event_bus = bus, input = input })
    broker:arbitrate(1)
    local stack = ActivityStack:new({ broker = broker, event_bus = bus })
    return stack, broker, stopped, bus
end

local function activity(id, band, offset)
    local a = { id = id, band = band, offset = offset or 0, suspends = 0, resumes = 0 }
    a.on_suspend = function() a.suspends = a.suspends + 1 end
    a.on_resume = function() a.resumes = a.resumes + 1 end
    return a
end

-- ---------------------------------------------------------------------------
-- Stack mechanics
-- ---------------------------------------------------------------------------

function M.test_an_empty_stack_has_no_current_activity()
    local stack = make_stack()
    T.assert_nil(stack:current())
    T.assert_equal(stack:depth(), 0)
end

function M.test_push_makes_an_activity_current()
    local stack = make_stack()
    local grind = activity("activity.grind", "GOAL")
    local handle = stack:push(grind)

    T.assert_not_nil(handle)
    T.assert_equal(stack:current().id, "activity.grind")
    T.assert_equal(stack:depth(), 1)
    T.assert_equal(stack:current().priority, 30, "GOAL+0 resolves to 30")
end

--- "One active Activity" -- the deepest entries are suspended, not concurrent.
function M.test_only_the_top_activity_is_current()
    local stack = make_stack()
    stack:push(activity("activity.grind", "GOAL"))
    stack:push(activity("behavior.recover", "SAFETY"))

    T.assert_equal(stack:current().id, "behavior.recover")
    T.assert_equal(stack:depth(), 2)
end

function M.test_push_suspends_the_previous_activity_and_pop_resumes_it()
    local stack = make_stack()
    local grind = activity("activity.grind", "GOAL")
    local recover = activity("behavior.recover", "SAFETY")

    stack:push(grind)
    stack:push(recover)
    T.assert_equal(grind.suspends, 1, "the interrupted activity must be told")
    T.assert_equal(grind.resumes, 0)

    local popped = stack:pop()
    T.assert_equal(popped.id, "behavior.recover")
    T.assert_equal(grind.resumes, 1, "popping the interrupt must resume what it interrupted")
    T.assert_equal(stack:current().id, "activity.grind")
end

function M.test_pop_on_an_empty_stack_is_nil_not_an_error()
    local stack = make_stack()
    local ok, popped = pcall(function() return stack:pop() end)
    T.assert_true(ok)
    T.assert_nil(popped)
end

function M.test_a_bare_integer_band_is_refused()
    local stack = make_stack()
    local handle, reason = stack:push({ id = "x", priority = 55 })
    T.assert_nil(handle)
    T.assert_equal(reason, "band_must_be_named")
end

function M.test_an_activity_without_an_id_is_refused()
    local stack = make_stack()
    local handle, reason = stack:push({ band = "GOAL" })
    T.assert_nil(handle)
    T.assert_equal(reason, "missing_id")
end

--- A suspend/resume callback is third-party code on the interrupt path.
function M.test_a_throwing_suspend_callback_does_not_break_the_push()
    local stack = make_stack()
    stack:push({ id = "activity.buggy", band = "GOAL", on_suspend = function() error("boom", 0) end })
    local ok, handle = pcall(function() return stack:push(activity("behavior.recover", "SAFETY")) end)

    T.assert_true(ok, "a throwing on_suspend must not propagate out of push")
    T.assert_not_nil(handle)
    T.assert_equal(stack:current().id, "behavior.recover")
end

-- ---------------------------------------------------------------------------
-- Revocation on push (ADR 08 §6.4)
-- ---------------------------------------------------------------------------

--- "death pushes at band 90, REVOKES EVERYTHING [below]".
function M.test_a_safety_push_revokes_every_lease_below_it()
    local stack, broker, stopped = make_stack()
    local revoked = {}

    stack:push(activity("activity.grind", "GOAL"))
    broker:acquire({
        channel = Channel.MOVEMENT, owner = "activity.grind", band = "GOAL", ttl_ticks = 10,
        on_revoke = function(reason) revoked[#revoked + 1] = reason end,
    })
    broker:acquire({ channel = Channel.CASTING, owner = "rotation.frost", band = "COMBAT", ttl_ticks = 10 })
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.grind")

    stack:push(activity("behavior.corpse_run", "SAFETY"))

    T.assert_nil(broker:who_owns(Channel.MOVEMENT), "a band-90 push must clear MOVEMENT")
    T.assert_nil(broker:who_owns(Channel.CASTING), "…and CASTING")
    T.assert_equal(revoked[1], "activity_push")
    T.assert_equal(#stopped, #MovementRelease.KEYS,
        "the revoked MOVEMENT holder must be force-stopped -- a corpse run cannot start while "
        .. "the previous activity's keys are still down")
end

--- A push does NOT revoke leases at or above its own priority: it is an interrupt, not a
--- reset. Revoking the safety net because a goal activity started would invert the bands.
function M.test_a_push_does_not_revoke_equal_or_higher_leases()
    local stack, broker = make_stack()
    broker:acquire({ channel = Channel.ITEMS, owner = "behavior.safety", band = "SAFETY", ttl_ticks = 10 })
    stack:push(activity("activity.grind", "GOAL"))

    T.assert_equal(broker:who_owns(Channel.ITEMS), "behavior.safety",
        "a GOAL push must not disturb a SAFETY holder")
end

function M.test_push_is_published()
    local stack, _, _, bus = make_stack()
    local events = {}
    bus:subscribe("activity:pushed", function(p) events[#events + 1] = p end)
    stack:push(activity("behavior.recover", "SAFETY"))

    T.assert_equal(#events, 1)
    T.assert_equal(events[1].id, "behavior.recover")
    T.assert_equal(events[1].priority, 90)
end

-- ---------------------------------------------------------------------------
-- Delegation (ADR 08 §6.4) -- the kiting scenario
-- ---------------------------------------------------------------------------

--- The exact ADR §6.4 shape:
---   [ Grind -> Combat(policy) ]  <- delegates CASTING+TARGETING, KEEPS MOVEMENT
function M.test_the_activity_delegates_casting_and_keeps_movement()
    local stack, broker = make_stack()
    stack:push(activity("activity.grind", "GOAL"))

    local held = broker:acquire({
        channels = { Channel.MOVEMENT, Channel.CASTING, Channel.TARGETING },
        owner = "activity.grind", band = "GOAL", ttl_ticks = 10,
    })
    T.assert_not_nil(held)

    local service = stack:delegate(Channel.CASTING, "service.combat", {
        policy = "objective", leash = 30, allow_adds = false,
    })
    local service2 = stack:delegate(Channel.TARGETING, "service.combat", { policy = "objective" })

    T.assert_not_nil(service, "delegation must yield the service a caretaker of its own")
    T.assert_not_nil(service2)
    T.assert_equal(broker:who_owns(Channel.CASTING), "service.combat")
    T.assert_equal(broker:who_owns(Channel.TARGETING), "service.combat")
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.grind",
        "THE POINT: the activity keeps MOVEMENT so it can backpedal while combat casts")
end

function M.test_the_policy_is_recorded_and_readable_by_the_service()
    local stack = make_stack()
    stack:push(activity("activity.grind", "GOAL"))
    stack:broker():acquire({
        channel = Channel.CASTING, owner = "activity.grind", band = "GOAL", ttl_ticks = 10,
    })

    stack:delegate(Channel.CASTING, "service.combat", { policy = "objective", leash = 30 })
    local delegation = stack:delegation(Channel.CASTING)

    T.assert_not_nil(delegation)
    T.assert_equal(delegation.service_id, "service.combat")
    T.assert_equal(delegation.policy.policy, "objective", "the policy is what makes combat a service")
    T.assert_equal(delegation.policy.leash, 30)
end

--- The delegated service inherits the activity's priority: it is acting under the activity's
--- authority, not its own.
function M.test_the_delegate_inherits_the_activity_priority()
    local stack, broker = make_stack()
    stack:push(activity("activity.grind", "GOAL"))
    broker:acquire({ channel = Channel.CASTING, owner = "activity.grind", band = "GOAL", ttl_ticks = 10 })

    local service = stack:delegate(Channel.CASTING, "service.combat", {})
    T.assert_equal(service:priority(), 30, "the service acts at the delegating activity's band")
end

function M.test_delegating_a_channel_the_activity_does_not_hold_is_refused()
    local stack = make_stack()
    stack:push(activity("activity.grind", "GOAL"))
    local service, reason = stack:delegate(Channel.CASTING, "service.combat", {})
    T.assert_nil(service, "an activity cannot hand out authority it does not have")
    T.assert_equal(reason, "channel_not_held_by_activity")
end

function M.test_delegating_with_no_active_activity_is_refused()
    local stack = make_stack()
    local service, reason = stack:delegate(Channel.CASTING, "service.combat", {})
    T.assert_nil(service)
    T.assert_equal(reason, "no_active_activity")
end

--- Popping the delegating activity must not leave the service holding a channel under the
--- authority of something that is no longer running.
function M.test_popping_an_activity_withdraws_its_delegations()
    local stack, broker = make_stack()
    stack:push(activity("activity.grind", "GOAL"))
    broker:acquire({ channel = Channel.CASTING, owner = "activity.grind", band = "GOAL", ttl_ticks = 10 })
    stack:delegate(Channel.CASTING, "service.combat", {})
    T.assert_equal(broker:who_owns(Channel.CASTING), "service.combat")

    stack:pop()

    T.assert_nil(broker:who_owns(Channel.CASTING),
        "a delegation cannot outlive the activity that granted it")
    T.assert_nil(stack:delegation(Channel.CASTING))
end

-- ---------------------------------------------------------------------------
-- INTERRUPT stage (ADR 08 §7 step 3)
-- ---------------------------------------------------------------------------

function M.test_evaluators_run_on_the_interrupt_stage()
    local stack = make_stack()
    local calls = 0
    stack:register_evaluator("death_watch", function() calls = calls + 1 end)
    stack:evaluate({ tick_index = 1 })
    stack:evaluate({ tick_index = 2 })
    T.assert_equal(calls, 2)
end

function M.test_an_evaluator_can_push_a_safety_activity()
    local stack, broker = make_stack()
    stack:push(activity("activity.grind", "GOAL"))
    broker:acquire({ channel = Channel.MOVEMENT, owner = "activity.grind", band = "GOAL", ttl_ticks = 10 })

    stack:register_evaluator("death_watch", function(ctx, s)
        if ctx.player_is_dead then
            s:push({ id = "behavior.corpse_run", band = "SAFETY" })
        end
    end)

    stack:evaluate({ tick_index = 1, player_is_dead = false })
    T.assert_equal(stack:current().id, "activity.grind", "no interrupt while alive")

    stack:evaluate({ tick_index = 2, player_is_dead = true })
    T.assert_equal(stack:current().id, "behavior.corpse_run", "the evaluator must be able to interrupt")
    T.assert_nil(broker:who_owns(Channel.MOVEMENT), "and its push revokes what was below")
end

--- An evaluator is the safety net's trigger. One that throws must not disarm the others.
function M.test_a_throwing_evaluator_does_not_stop_the_rest()
    local stack = make_stack()
    local second_ran = false
    stack:register_evaluator("broken", function() error("evaluator died", 0) end)
    stack:register_evaluator("stuck_watch", function() second_ran = true end)

    local ok, report = pcall(function() return stack:evaluate({ tick_index = 1 }) end)
    T.assert_true(ok, "a throwing evaluator must not propagate out of the INTERRUPT stage")
    T.assert_true(second_ran, "later evaluators must still run")
    T.assert_equal(report.faults, 1, "the fault must be reported, not swallowed")
end

function M.test_evaluate_with_no_evaluators_is_a_no_op()
    local stack = make_stack()
    local ok, report = pcall(function() return stack:evaluate({ tick_index = 1 }) end)
    T.assert_true(ok)
    T.assert_equal(report.faults, 0)
    T.assert_equal(report.evaluated, 0)
end

return M
