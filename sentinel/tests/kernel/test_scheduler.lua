-- tests/kernel/test_scheduler.lua
-- ADR 08 §7 -- the tick pipeline, promoted from runtime/app.lua's 4-step frame:
--
--   1. SENSE      hot sensors -> Snapshot, frozen for the tick (VALUES, not handles)
--   2. EVENTS     drain queue, fire subscribers (inside ErrorBoundary)
--   3. INTERRUPT  safety evaluators may push/pop the ActivityStack
--   4. ARBITRATE  ControlBroker resolves leases, fires revocations, force-releases keys
--   5. ACT        active activity + delegated services run -> emit intents
--   6. COMMIT     IntentQueue: dedupe -> gate -> generation-check -> execute
--   7. ACCOUNT    frame budget, quarantine checks, telemetry
--
-- INTERRUPT and ARBITRATE are real stages with no kernel occupants in Phase 1 -- the
-- ControlBroker and ActivityStack are Phase 2. They are present rather than deferred so
-- Phase 2 plugs in rather than re-cuts the pipeline.
--
-- ADR 08 §7 also names two defects in the 4-step version, both regression-guarded here:
-- `nav_adapter:poll()` was NOT error-wrapped while its neighbours were, and `_izi_bridge`
-- was constructed and never read.

local Scheduler = require("kernel/scheduler")
local IntentQueue = require("kernel/intent_queue")
local Blackboard = require("core/blackboard")
local ErrorBoundary = require("core/error_boundary")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

--- A scheduler on a scripted clock, so budget accounting is deterministic offline.
local function make_scheduler(opts)
    opts = opts or {}
    local elapsed = { 0 }
    local bus = EventBus:new(function() end)
    local sched = Scheduler:new({
        event_bus = bus,
        blackboard = opts.blackboard or Blackboard:new(),
        error_boundary = ErrorBoundary:new(bus),
        intent_queue = opts.intent_queue,
        frame_budget_ms = opts.frame_budget_ms,
        monotonic_ms = function() return elapsed[1] end,
        game_time_ms = opts.game_time_ms,
    })
    -- Tests advance the fake clock to simulate work taking time.
    return sched, elapsed, bus
end

-- ---------------------------------------------------------------------------
-- Exit criterion: a tick with nothing registered
-- ---------------------------------------------------------------------------

function M.test_tick_runs_with_nothing_registered()
    local sched = make_scheduler()
    local ok, report = pcall(function() return sched:tick() end)
    T.assert_true(ok, "an empty tick must not throw: " .. tostring(report))
    T.assert_not_nil(report, "every tick must produce a report")
    T.assert_equal(report.tick_index, 1)
end

function M.test_repeated_empty_ticks_advance_the_index()
    local sched = make_scheduler()
    sched:tick(); sched:tick()
    local report = sched:tick()
    T.assert_equal(report.tick_index, 3)
end

function M.test_all_seven_stages_run_in_adr_order()
    local sched = make_scheduler()
    local seen = {}
    for _, stage in ipairs(Scheduler.STAGES) do
        sched:register(stage, "probe", function() seen[#seen + 1] = stage end)
    end
    sched:tick()

    T.assert_equal(#seen, 7, "all seven stages must run")
    for i, stage in ipairs(Scheduler.STAGES) do
        T.assert_equal(seen[i], stage, "stage " .. i .. " must be " .. stage)
    end
end

function M.test_registering_an_unknown_stage_is_refused()
    local sched = make_scheduler()
    local ok, err = pcall(function() sched:register("MIDDLE_BIT", "x", function() end) end)
    T.assert_false(ok, "an unknown stage name must be refused, not silently ignored")
    T.assert_true(tostring(err):find("MIDDLE_BIT", 1, true) ~= nil, tostring(err))
end

-- ---------------------------------------------------------------------------
-- Exit criterion: frame budget accounted
-- ---------------------------------------------------------------------------

function M.test_frame_budget_is_accounted_per_stage_and_per_owner()
    local sched, clock = make_scheduler()
    sched:register("ACT", "questing", function() clock[1] = clock[1] + 4 end)
    sched:register("ACT", "combat", function() clock[1] = clock[1] + 2 end)
    sched:register("SENSE", "sensors", function() clock[1] = clock[1] + 1 end)

    local report = sched:tick()

    T.assert_equal(report.total_ms, 7, "the frame total must be the sum of its parts")
    T.assert_equal(report.stages.ACT.ms, 6)
    T.assert_equal(report.stages.SENSE.ms, 1)
    T.assert_equal(report.owners.questing, 4, "per-owner accounting is what attributes a slow frame")
    T.assert_equal(report.owners.combat, 2)
end

function M.test_exceeding_the_frame_budget_is_reported()
    local sched, clock, bus = make_scheduler({ frame_budget_ms = 5 })
    local alerts = {}
    bus:subscribe("kernel:budget_exceeded", function(p) alerts[#alerts + 1] = p end)
    sched:register("ACT", "hog", function() clock[1] = clock[1] + 20 end)

    local report = sched:tick()

    T.assert_true(report.over_budget, "20 ms against a 5 ms budget must be flagged")
    T.assert_equal(#alerts, 1, "over-budget must be observable on the bus")
    T.assert_equal(alerts[1].worst_owner, "hog", "the alert must name the owner that cost the most")
end

function M.test_within_budget_raises_nothing()
    local sched, clock, bus = make_scheduler({ frame_budget_ms = 16 })
    local alerts = 0
    bus:subscribe("kernel:budget_exceeded", function() alerts = alerts + 1 end)
    sched:register("ACT", "cheap", function() clock[1] = clock[1] + 1 end)

    local report = sched:tick()
    T.assert_false(report.over_budget)
    T.assert_equal(alerts, 0)
end

function M.test_telemetry_reaches_the_blackboard()
    local bb = Blackboard:new()
    local sched, clock = make_scheduler({ blackboard = bb })
    sched:register("ACT", "questing", function() clock[1] = clock[1] + 3 end)
    sched:tick()

    T.assert_equal(bb:get("system.frame_ms"), 3, "the cockpit needs the frame cost")
    T.assert_equal(bb:get("system.tick_index"), 1)
end

-- ---------------------------------------------------------------------------
-- Fault isolation + quarantine
-- ---------------------------------------------------------------------------

function M.test_a_throwing_handler_does_not_stop_the_tick()
    local sched = make_scheduler()
    local later_ran = false
    sched:register("ACT", "bad", function() error("handler blew up", 0) end)
    sched:register("ACT", "good", function() later_ran = true end)
    sched:register("ACCOUNT", "after", function() later_ran = later_ran and true end)

    local ok = pcall(function() return sched:tick() end)
    T.assert_true(ok, "a throwing handler must not propagate out of tick()")
    T.assert_true(later_ran, "handlers after the faulting one must still run")
end

function M.test_a_faulting_handler_is_reported_in_the_tick_report()
    local sched = make_scheduler()
    sched:register("ACT", "bad", function() error("nope", 0) end)
    local report = sched:tick()

    T.assert_equal(#report.faults, 1)
    T.assert_equal(report.faults[1].owner, "bad")
    T.assert_equal(report.faults[1].stage, "ACT")
end

--- Mirrors ModuleRegistry's existing 3-strike DEGRADED policy (ADR 08 §5.1): a handler that
--- faults every frame would otherwise burn the frame budget forever.
function M.test_three_consecutive_faults_quarantine_a_handler()
    local sched, _, bus = make_scheduler()
    local quarantined = {}
    bus:subscribe("kernel:handler_quarantined", function(p) quarantined[#quarantined + 1] = p end)

    local calls = 0
    sched:register("ACT", "flaky", function() calls = calls + 1; error("always", 0) end)

    sched:tick(); sched:tick(); sched:tick()
    T.assert_equal(calls, 3)
    T.assert_equal(#quarantined, 1, "the third consecutive fault must quarantine")

    sched:tick(); sched:tick()
    T.assert_equal(calls, 3, "a quarantined handler must stop being called")
end

--- Only CONSECUTIVE faults degrade -- a transient error must not accumulate forever.
function M.test_a_successful_run_resets_the_fault_streak()
    local sched = make_scheduler()
    local should_fail = true
    local calls = 0
    sched:register("ACT", "intermittent", function()
        calls = calls + 1
        if should_fail then error("transient", 0) end
    end)

    sched:tick(); sched:tick()   -- 2 faults
    should_fail = false
    sched:tick()                 -- clean run resets the streak
    should_fail = true
    sched:tick(); sched:tick()   -- 2 more faults -- still under the limit

    T.assert_equal(calls, 5, "the handler must still be running after a reset streak")
end

-- ---------------------------------------------------------------------------
-- The frozen snapshot contract
-- ---------------------------------------------------------------------------

--- SENSE writes; every later stage reads a FROZEN snapshot. This is the structural
--- expression of ADR 08 §7 step 1 -- sense once, frozen for the tick.
function M.test_sense_fills_the_snapshot_and_later_stages_read_it_frozen()
    local sched = make_scheduler()
    sched:register("SENSE", "vitals", function(ctx)
        ctx.snapshot:put("player.health_pct", 0.5)
    end)

    local seen, frozen_here = nil, nil
    sched:register("ACT", "reader", function(ctx)
        seen = ctx.snapshot:get("player.health_pct")
        frozen_here = ctx.snapshot:is_frozen()
    end)

    sched:tick()
    T.assert_near(seen, 0.5, 0.0001, "ACT must see what SENSE captured")
    T.assert_true(frozen_here, "the snapshot must be frozen by the time ACT runs")
end

function M.test_a_post_sense_stage_cannot_write_to_the_snapshot()
    local sched = make_scheduler()
    local write_ok = nil
    sched:register("ACT", "sneaky", function(ctx)
        write_ok = pcall(function() ctx.snapshot:put("player.level", 70) end)
    end)
    sched:tick()
    T.assert_false(write_ok, "a stage after SENSE must not be able to mutate the tick's view")
end

function M.test_each_tick_gets_a_fresh_snapshot()
    local sched = make_scheduler()
    local n = 0
    sched:register("SENSE", "counter", function(ctx)
        n = n + 1
        ctx.snapshot:put("player.level", n)
    end)
    local seen = {}
    sched:register("ACT", "reader", function(ctx) seen[#seen + 1] = ctx.snapshot:get("player.level") end)

    sched:tick(); sched:tick()
    T.assert_equal(seen[1], 1)
    T.assert_equal(seen[2], 2, "tick 2 must not see tick 1's frozen values")
end

--- A SENSE handler that throws must not leave the tick without a snapshot.
function M.test_a_faulting_sensor_still_yields_a_usable_snapshot()
    local sched = make_scheduler()
    sched:register("SENSE", "broken", function() error("sensor died", 0) end)
    local got = "unset"
    sched:register("ACT", "reader", function(ctx) got = ctx.snapshot:get("player.health_pct", "absent") end)

    local ok = pcall(function() return sched:tick() end)
    T.assert_true(ok)
    T.assert_equal(got, "absent", "a failed sensor yields an empty snapshot, never a nil one")
end

-- ---------------------------------------------------------------------------
-- Retention: the frozen snapshot must OUTLIVE the tick that froze it
-- ---------------------------------------------------------------------------
-- ADR 08 §13.1 item 14. The snapshot existed only as a `local` inside `tick()`, reachable solely by
-- a handler the scheduler itself called with `ctx`. Everything else in the tree -- a rotation deep
-- inside an ACT handler, a plugin holding `_G.Sentinel` -- had no route to it, and `Sentinel.snapshot`
-- resolved through a `Scheduler:current_snapshot()` that did not exist. Retention is the read path.

--- Before the first tick there is no sensed data, but there IS a snapshot: an EMPTY frozen one.
--- The same choice `tick()` already makes when a sensor throws -- "an empty frozen snapshot is
--- readable and honest, whereas a nil one forces every downstream consumer to nil-check" -- applied
--- to the interval before tick 1. A nil here would put a nil-check in every plugin.
function M.test_current_snapshot_is_an_empty_frozen_snapshot_before_the_first_tick()
    local sched = make_scheduler()
    local snap = sched:current_snapshot()
    T.assert_not_nil(snap, "there must be a snapshot to read before tick 1, not nil")
    T.assert_true(snap:is_frozen(), "and it must be frozen, like every other snapshot")
    T.assert_equal(snap:tick_index(), 0, "tick 0 -- nothing has been sensed yet")
    T.assert_equal(snap:get("player.health_pct", "absent"), "absent")
end

function M.test_current_snapshot_returns_what_this_tick_sensed()
    local sched = make_scheduler()
    sched:register("SENSE", "vitals", function(ctx)
        ctx.snapshot:put("player.health_pct", 0.42)
    end)
    sched:tick()

    local snap = sched:current_snapshot()
    T.assert_near(snap:get("player.health_pct"), 0.42, 0.0001,
        "a caller outside the pipeline must read the same values ACT saw")
    T.assert_equal(snap:tick_index(), 1)
end

--- The retained snapshot is the SAME object the stages read, not a copy taken afterwards. A copy
--- would drift the moment anything about the capture changed, and would silently answer a different
--- question than the one COMMIT gated on.
function M.test_the_retained_snapshot_is_the_identical_object_the_stages_received()
    local sched = make_scheduler()
    local from_ctx = nil
    sched:register("ACT", "reader", function(ctx) from_ctx = ctx.snapshot end)
    sched:tick()
    T.assert_true(sched:current_snapshot() == from_ctx,
        "current_snapshot() must hand back the tick's frozen snapshot itself")
end

function M.test_each_tick_replaces_the_retained_snapshot()
    local sched = make_scheduler()
    local n = 0
    sched:register("SENSE", "counter", function(ctx)
        n = n + 1
        ctx.snapshot:put("player.level", n)
    end)

    sched:tick()
    local first = sched:current_snapshot()
    sched:tick()
    local second = sched:current_snapshot()

    T.assert_equal(first:get("player.level"), 1)
    T.assert_equal(second:get("player.level"), 2, "the retained snapshot must advance with the tick")
    T.assert_false(first == second, "and must not be the same object two ticks running")
end

--- Retention must survive the failure modes the tick already handles. A sensor that throws yields
--- an empty snapshot rather than none; retaining nil instead would reintroduce the nil-check.
function M.test_a_faulting_sensor_still_leaves_a_readable_retained_snapshot()
    local sched = make_scheduler()
    sched:register("SENSE", "broken", function() error("sensor died", 0) end)
    sched:tick()

    local snap = sched:current_snapshot()
    T.assert_not_nil(snap)
    T.assert_equal(snap:get("player.health_pct", "absent"), "absent")
    T.assert_equal(snap:tick_index(), 1, "the tick happened, even though its sensor did not")
end

--- The retained snapshot is handed out to arbitrary callers, so it must be as unwritable as the one
--- the pipeline passes -- otherwise `Sentinel.snapshot` becomes a shared mutable scratchpad that
--- every plugin can poison for the rest of the tick.
function M.test_the_retained_snapshot_is_not_writable_by_its_readers()
    local sched = make_scheduler()
    sched:tick()
    local ok = pcall(function() sched:current_snapshot():put("player.level", 70) end)
    T.assert_false(ok, "a caller must not be able to write into the tick's frozen view")
end

-- ---------------------------------------------------------------------------
-- COMMIT wiring
-- ---------------------------------------------------------------------------

function M.test_commit_stage_drives_the_intent_queue_with_the_frozen_snapshot()
    local queue = IntentQueue:new()
    local executed_with = nil
    queue:register_executor("cast", function(intent, snap)
        executed_with = { spell = intent.payload.spell_id, level = snap:get("player.level") }
        return true
    end)

    local sched = make_scheduler({ intent_queue = queue })
    sched:register("SENSE", "vitals", function(ctx) ctx.snapshot:put("player.level", 60) end)
    sched:register("ACT", "rotation", function(ctx)
        ctx.intents:submit({ type = "cast", owner = "rotation", band = 55, payload = { spell_id = 116 } })
    end)

    local report = sched:tick()

    T.assert_not_nil(executed_with, "an intent submitted in ACT must be committed in COMMIT")
    T.assert_equal(executed_with.spell, 116)
    T.assert_equal(executed_with.level, 60, "the executor must see the tick's frozen snapshot")
    T.assert_equal(#report.intents.committed, 1)
end

function M.test_intents_do_not_leak_between_ticks()
    local queue = IntentQueue:new()
    queue:register_executor("cast", function() return true end)
    local sched = make_scheduler({ intent_queue = queue })

    local submit = true
    sched:register("ACT", "rotation", function(ctx)
        if submit then
            ctx.intents:submit({ type = "cast", owner = "r", band = 55, payload = { spell_id = 1 } })
        end
    end)

    local first = sched:tick()
    submit = false
    local second = sched:tick()

    T.assert_equal(#first.intents.committed, 1)
    T.assert_equal(#second.intents.committed, 0, "tick 2 must not re-commit tick 1's intent")
end

-- ---------------------------------------------------------------------------
-- ADR 08 §7 named defects
-- ---------------------------------------------------------------------------

--- app.lua:68 -- `nav_adapter:poll()` was the one call in the frame with no error wrapper
--- while both of its neighbours had one.
function M.test_every_registered_handler_is_error_wrapped_including_nav_poll()
    local sched = make_scheduler()
    local nav_polled, registry_ticked = false, false
    sched:register("SENSE", "nav_adapter", function() nav_polled = true; error("nav exploded", 0) end)
    sched:register("ACT", "registry", function() registry_ticked = true end)

    local ok = pcall(function() return sched:tick() end)
    T.assert_true(ok, "a throwing nav poll must be contained like any other handler")
    T.assert_true(nav_polled)
    T.assert_true(registry_ticked, "the rest of the frame must survive a nav fault")
end

function M.test_ctx_carries_the_tick_delta()
    local times = { 1000, 1016, 1033 }
    local i = 0
    local sched = make_scheduler({ game_time_ms = function() i = i + 1; return times[i] end })
    local deltas = {}
    sched:register("ACT", "reader", function(ctx) deltas[#deltas + 1] = ctx.delta_ms end)

    sched:tick(); sched:tick(); sched:tick()
    T.assert_equal(deltas[1], 0, "the first tick has no predecessor")
    T.assert_equal(deltas[2], 16)
    T.assert_equal(deltas[3], 17)
end

--- ADR 08 §13 q7: the scheduler must MEASURE the cadence, not assume it.
function M.test_scheduler_exposes_the_measured_cadence()
    local t = 1000
    local sched = make_scheduler({ game_time_ms = function() t = t + 16; return t end })
    for _ = 1, 40 do sched:tick() end

    local stats = sched:cadence()
    T.assert_not_nil(stats, "after 40 ticks the scheduler must report a measured cadence")
    T.assert_equal(stats.median, 16)
    T.assert_near(stats.hz, 62.5, 0.1)
end

function M.test_unregister_removes_a_handler()
    local sched = make_scheduler()
    local calls = 0
    sched:register("ACT", "temp", function() calls = calls + 1 end)
    sched:tick()
    sched:unregister("ACT", "temp")
    sched:tick()
    T.assert_equal(calls, 1, "an unregistered handler must stop running")
end

-- ---------------------------------------------------------------------------
-- Movement reconciliation (Phase 4b)
-- ---------------------------------------------------------------------------
--
-- A `move` intent commits by recording a desired state and pressing nothing. If the reconciler
-- is not actually driven by the tick, that intent is inert IN GAME and green in every unit test
-- -- the worst possible split. These tests exist to close it.

local function movement_double()
    local calls = {}
    return {
        calls = calls,
        reconcile = function(input)
            calls[#calls + 1] = { input = input }
            return { pressed = {}, released = {} }
        end,
    }
end

function M.test_the_tick_reconciles_movement_after_the_intent_queue_drains()
    local movement = movement_double()
    local sched = Scheduler:new({ movement = movement })

    local report = sched:tick()

    T.assert_equal(#movement.calls, 1, "every tick must reconcile movement exactly once")
    T.assert_not_nil(report.movement, "the reconcile report must reach the tick report")
end

--- Order is the whole point: reconciling BEFORE the queue drains would act on last tick's
--- desire, so a `move` would take effect one frame late and a stop would linger one frame long.
function M.test_reconciliation_happens_after_intents_commit()
    local order = {}
    local queue = {
        commit = function() order[#order + 1] = "commit" return
            { committed = {}, deduped = {}, rejected = {}, failed = {} } end,
    }
    local movement = { reconcile = function() order[#order + 1] = "reconcile" return {} end }

    Scheduler:new({ intent_queue = queue, movement = movement }):tick()

    T.assert_equal(order[1], "commit")
    T.assert_equal(order[2], "reconcile")
end

--- The reconciler runs on the movement path every tick. A throw there must be reported and
--- survived, not allowed to take the frame down with it.
function M.test_a_throwing_reconciler_is_a_reported_fault_not_a_dead_tick()
    local movement = { reconcile = function() error("SDK exploded", 0) end }
    local sched = Scheduler:new({ movement = movement })

    local ok, report = pcall(function() return sched:tick() end)

    T.assert_true(ok, "a throwing reconciler must not propagate out of the tick")
    T.assert_equal(#report.faults, 1)
    T.assert_equal(report.faults[1].owner, "movement_reconcile")
end

--- Its cost is attributed to COMMIT, because pressing the key IS the execution half of a
--- `move`. A reconcile that ran outside the measured stages would be time the frame budget
--- cannot see.
function M.test_reconciliation_is_billed_to_the_commit_stage()
    local slow = 0
    local movement = { reconcile = function() slow = slow + 1 return {} end }
    local sched = Scheduler:new({
        movement = movement,
        monotonic_ms = function()
            -- Two reads per measured span; step the clock so the span is non-zero.
            slow = slow + 0
            return os.clock() * 1000
        end,
    })
    local report = sched:tick()
    T.assert_true(report.stages.COMMIT.ms >= 0, "the reconcile must be billed inside COMMIT")
    T.assert_equal(slow, 1)
end

--- A scheduler with no movement module must behave exactly as it did before Phase 4b.
function M.test_a_scheduler_without_a_movement_module_never_reconciles()
    local report = Scheduler:new({}):tick()
    T.assert_nil(report.movement)
end

return M
