-- tests/kernel/test_arbitration_pipeline.lua
-- Deliverable 7: the ARBITRATE stage wired into the real pipeline.
--
-- The unit tests prove the broker, the stack and the queue each behave. This file proves they
-- are actually CONNECTED -- that a lease acquired in ACT is arbitrated in ARBITRATE, that an
-- intent stamped in ACT is generation-checked in COMMIT, and that caretakers die in ACCOUNT.
-- Wiring bugs are invisible to unit tests by construction: every collaborator can be perfect
-- while nothing is plugged in. Phase 1 shipped exactly that bug in the 4-step frame, where
-- `registry:tick_all` was never called and every module sat frozen while the loop looked alive.

local Scheduler = require("kernel/scheduler")
local ControlBroker = require("kernel/control_broker")
local Channel = ControlBroker.Channel
local ActivityStack = require("kernel/activity_stack")
local IntentQueue = require("kernel/intent_queue")
local MovementRelease = require("kernel/movement_release")
local ErrorBoundary = require("core/error_boundary")
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

--- Assembles the kernel exactly as runtime/app.lua does, with core.input doubled.
local function make_kernel()
    local stopped = {}
    local input = {}
    for _, key in ipairs(MovementRelease.KEYS) do
        input[key .. "_stop"] = function() stopped[#stopped + 1] = key end
    end

    local bus = EventBus:new(function() end)
    local blackboard = Blackboard:new()
    local queue = IntentQueue:new()
    local broker = ControlBroker:new({ event_bus = bus, intent_queue = queue, input = input })
    local stack = ActivityStack:new({ broker = broker, event_bus = bus })

    queue:set_generation_validator(function(intent)
        return broker:is_generation_valid(intent)
    end)

    local game_time = 1000
    local sched = Scheduler:new({
        event_bus = bus,
        blackboard = blackboard,
        error_boundary = ErrorBoundary:new(bus),
        intent_queue = queue,
        monotonic_ms = function() return 0 end,
        game_time_ms = function() game_time = game_time + 16; return game_time end,
    })

    sched:register("SENSE", "control_broker.clock", function(ctx)
        broker:begin_tick(ctx.tick_index)
    end)
    sched:register("INTERRUPT", "activity_stack", function(ctx) stack:evaluate(ctx) end)
    sched:register("ARBITRATE", "control_broker", function(ctx) broker:arbitrate(ctx.tick_index) end)
    sched:register("ACCOUNT", "control_broker.end_tick", function() broker:end_tick() end)

    return {
        sched = sched, broker = broker, stack = stack, queue = queue,
        bus = bus, stopped = stopped, blackboard = blackboard,
    }
end

--- A committed intent needs an executor; without one every intent is refused `no_executor`,
--- which would make the generation assertions vacuous.
local function accept_casts(k)
    local committed = {}
    k.queue:register_executor("cast", function(intent)
        committed[#committed + 1] = intent
        return true
    end)
    return committed
end

-- ---------------------------------------------------------------------------
-- Stage wiring
-- ---------------------------------------------------------------------------

function M.test_arbitrate_stage_advances_the_broker_each_tick()
    local k = make_kernel()
    k.sched:tick()
    T.assert_equal(k.broker:tick_index(), 1)
    k.sched:tick()
    T.assert_equal(k.broker:tick_index(), 2, "the ARBITRATE stage must drive the broker's clock")
end

function M.test_a_lease_expires_through_the_pipeline_with_no_help_from_the_holder()
    local k = make_kernel()
    local revocations = {}

    k.sched:register("ACT", "activity", function()
        if k.broker:tick_index() == 1 then
            k.broker:acquire({
                channel = Channel.MOVEMENT, owner = "activity.grind", band = "GOAL",
                ttl_ticks = 2,
                on_revoke = function(reason) revocations[#revocations + 1] = reason end,
            })
        end
        -- deliberately never renews: this is the wedged-holder case
    end)

    k.sched:tick()
    T.assert_equal(k.broker:who_owns(Channel.MOVEMENT), "activity.grind")
    k.sched:tick()
    T.assert_equal(k.broker:who_owns(Channel.MOVEMENT), "activity.grind", "still in term")
    k.sched:tick()

    T.assert_nil(k.broker:who_owns(Channel.MOVEMENT), "ARBITRATE must expire it")
    T.assert_equal(revocations[1], "ttl_expired")
    T.assert_equal(#k.stopped, #MovementRelease.KEYS,
        "and the force-release must happen inside the pipeline, not just in a unit test")
end

-- ---------------------------------------------------------------------------
-- Generation check at COMMIT -- the named exit criterion
-- ---------------------------------------------------------------------------

--- "Intent under a stale generation is refused BY NAME at commit."
function M.test_an_intent_whose_lease_is_revoked_later_in_the_same_tick_is_refused_by_name()
    local k = make_kernel()
    accept_casts(k)

    k.sched:register("ACT", "activity.grind", function()
        -- Early in ACT: acquire, then emit an intent stamped with the live generation.
        local caretaker = k.broker:acquire({
            channel = Channel.CASTING, owner = "activity.grind", band = "GOAL", ttl_ticks = 5,
        })
        if caretaker then
            caretaker:submit({ type = "cast", payload = { spell_id = 116 } })
        end
    end)

    k.sched:register("ACT", "behavior.safety", function()
        -- Later in the SAME tick, and BEFORE COMMIT: safety preempts CASTING out from under it.
        k.broker:acquire({
            channel = Channel.CASTING, owner = "behavior.safety", band = "SAFETY", ttl_ticks = 5,
        })
    end)

    local report = k.sched:tick()

    T.assert_equal(#report.intents.committed, 0,
        "an intent whose lease died mid-tick must NOT commit")
    T.assert_equal(#report.intents.rejected, 1)
    T.assert_equal(report.intents.rejected[1].reason, "stale_generation",
        "the refusal must be named, not a silent drop")
end

--- The control case, or the test above proves nothing: an intent under a lease that SURVIVES
--- the tick must commit.
function M.test_an_intent_under_a_live_lease_commits()
    local k = make_kernel()
    local committed = accept_casts(k)

    k.sched:register("ACT", "activity.grind", function()
        local caretaker = k.broker:acquire({
            channel = Channel.CASTING, owner = "activity.grind", band = "GOAL", ttl_ticks = 5,
        })
        if caretaker then
            caretaker:submit({ type = "cast", payload = { spell_id = 116 } })
        end
    end)

    local report = k.sched:tick()
    T.assert_equal(#report.intents.committed, 1, "a live lease must let its intent through")
    T.assert_equal(#committed, 1)
    T.assert_equal(committed[1].owner, "activity.grind", "the caretaker stamps the owner")
    T.assert_true(type(committed[1].generation) == "number", "…and the generation")
end

--- Ambient authority fence: an intent submitted straight to the queue, with no lease behind
--- it, must not commit just because it looks well-formed.
function M.test_an_intent_submitted_without_a_lease_is_refused()
    local k = make_kernel()
    accept_casts(k)

    k.sched:register("ACT", "rogue.plugin", function(ctx)
        ctx.intents:submit({
            type = "cast", owner = "rogue.plugin", band = 55, payload = { spell_id = 999 },
        })
    end)

    local report = k.sched:tick()
    T.assert_equal(#report.intents.committed, 0,
        "no lease means no authority -- bypassing the broker must not work")
    T.assert_equal(report.intents.rejected[1].reason, "stale_generation")
end

-- ---------------------------------------------------------------------------
-- Caretaker lifetime across real ticks
-- ---------------------------------------------------------------------------

function M.test_a_caretaker_held_across_a_real_tick_boundary_goes_inert()
    local k = make_kernel()
    local stashed = nil
    local validity = {}

    k.sched:register("ACT", "activity.grind", function()
        if stashed == nil then
            stashed = k.broker:acquire({
                channel = Channel.MOVEMENT, owner = "activity.grind", band = "GOAL", ttl_ticks = 20,
            })
        end
        validity[#validity + 1] = stashed:is_valid()
    end)

    k.sched:tick()
    k.sched:tick()

    T.assert_true(validity[1], "valid in the tick it was issued")
    T.assert_false(validity[2],
        "a caretaker stashed across a real ACCOUNT boundary must be inert next tick")
    T.assert_equal(k.broker:who_owns(Channel.MOVEMENT), "activity.grind",
        "the lease itself survives the tick boundary")
end

function M.test_renewing_every_tick_keeps_one_grant_alive_indefinitely()
    local k = make_kernel()
    local revocations = 0
    local generations = {}

    k.sched:register("ACT", "activity.grind", function()
        local caretaker = k.broker:acquire({
            channel = Channel.MOVEMENT, owner = "activity.grind", band = "GOAL", ttl_ticks = 2,
            on_revoke = function() revocations = revocations + 1 end,
        })
        if caretaker then generations[#generations + 1] = caretaker:generation() end
    end)

    for _ = 1, 10 do k.sched:tick() end

    T.assert_equal(revocations, 0, "a renewing holder must never be revoked")
    T.assert_equal(#generations, 10)
    T.assert_equal(generations[1], generations[10],
        "ten ticks of renewal is ONE grant -- the generation must not churn")
    T.assert_equal(k.broker:who_owns(Channel.MOVEMENT), "activity.grind")
end

-- ---------------------------------------------------------------------------
-- The full §6.4 scenario, driven through the pipeline
-- ---------------------------------------------------------------------------

--- [ Grind ] -> [ Grind -> Combat(policy) ] -> [ Grind -> Recover ]
function M.test_the_adr_6_4_scenario_end_to_end()
    local k = make_kernel()

    -- [ Grind ] -- the base activity takes everything it needs.
    k.stack:push({ id = "activity.grind", band = "GOAL" })
    k.sched:tick()
    k.broker:acquire({
        channels = { Channel.MOVEMENT, Channel.CASTING, Channel.TARGETING },
        owner = "activity.grind", band = "GOAL", ttl_ticks = 50,
    })
    T.assert_equal(k.broker:who_owns(Channel.MOVEMENT), "activity.grind")

    -- [ Grind -> Combat(policy) ] -- delegate the casting channels, KEEP movement.
    k.stack:delegate(Channel.CASTING, "service.combat", { policy = "objective", leash = 30 })
    k.stack:delegate(Channel.TARGETING, "service.combat", { policy = "objective" })
    T.assert_equal(k.broker:who_owns(Channel.CASTING), "service.combat")
    T.assert_equal(k.broker:who_owns(Channel.MOVEMENT), "activity.grind",
        "kiting: combat casts while the activity still drives movement")

    -- [ Grind -> Recover ] -- death pushes at band 90 and revokes everything below.
    k.stack:push({ id = "behavior.corpse_run", band = "SAFETY" })

    T.assert_equal(k.stack:current().id, "behavior.corpse_run")
    T.assert_nil(k.broker:who_owns(Channel.MOVEMENT), "the band-90 push clears movement")
    T.assert_nil(k.broker:who_owns(Channel.CASTING), "…and the delegated casting channel")
    T.assert_equal(#k.stopped, #MovementRelease.KEYS,
        "the character must be stopped before a corpse run starts")

    -- ...and unwinding restores the grind as the active activity.
    k.stack:pop()
    T.assert_equal(k.stack:current().id, "activity.grind")
end

return M
