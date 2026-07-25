-- kernel/scheduler.lua
-- The tick pipeline. ADR 08 §5.1: "One thing drives the tick; also enforces per-plugin
-- frame budget."
--
-- ================================================================================
-- THE SEVEN STAGES (ADR 08 §7)
-- ================================================================================
--   1. SENSE      hot sensors -> Snapshot, frozen for the tick (VALUES, not handles)
--   2. EVENTS     drain queue, fire subscribers (inside ErrorBoundary)
--   3. INTERRUPT  safety evaluators may push/pop the ActivityStack
--   4. ARBITRATE  ControlBroker resolves leases, fires revocations, force-releases keys
--   5. ACT        active activity + delegated services run -> emit intents
--   6. COMMIT     IntentQueue: dedupe -> gate -> generation-check -> execute
--   7. ACCOUNT    frame budget, quarantine checks, telemetry
--
-- This is the promotion of `runtime/app.lua`'s 4-step frame
-- (callback_bridge -> sensor_hub:refresh -> nav_adapter:poll -> registry:tick_all).
--
-- INTERRUPT and ARBITRATE have no kernel occupants in Phase 1 -- the ControlBroker and
-- ActivityStack are Phase 2. They exist as real stages anyway so Phase 2 plugs in rather
-- than re-cutting the pipeline.
--
-- ================================================================================
-- THE TWO DEFECTS ADR 08 §7 NAMES IN THE 4-STEP VERSION
-- ================================================================================
-- `nav_adapter:poll()` at app.lua:68 was NOT error-wrapped while both its neighbours were,
-- and `_izi_bridge` at app.lua:29 was constructed and never read. Here EVERY registered
-- handler goes through the boundary by construction -- there is no unwrapped path to
-- forget about.
--
-- ================================================================================
-- FRAME BUDGET: ACCOUNTING, NOT PREEMPTION
-- ================================================================================
-- This measures and attributes; it cannot interrupt a handler mid-call. Lua is
-- cooperatively scheduled here and coroutines are undocumented in this SDK (ADR 08 §13
-- q12), so there is no mechanism to preempt a handler that runs long. What the kernel CAN
-- do -- and does -- is name the owner that burned the frame, and quarantine one that faults
-- repeatedly. Calling this "enforcement" would overstate it.
--
-- Durations are measured with a monotonic source and are INTERVALS only. ADR 08 §2.5
-- forbids mixing `core.time()` (seconds since injection) with `core.game_time()`
-- (milliseconds since game start); no value produced here is ever comparable to a server
-- timestamp.

local Snapshot = require("kernel/snapshot")
local TickClock = require("kernel/tick_clock")
local FaultTracker = require("kernel/fault_tracker")

local Scheduler = {}
Scheduler.__index = Scheduler

Scheduler.STAGES = { "SENSE", "EVENTS", "INTERRUPT", "ARBITRATE", "ACT", "COMMIT", "ACCOUNT" }

local STAGE_SET = {}
for _, stage in ipairs(Scheduler.STAGES) do STAGE_SET[stage] = true end

-- The 3-strike quarantine policy lives in kernel/fault_tracker.lua. This file used to implement it
-- inline, which made it the SECOND copy after runtime/module_registry.lua:232-270 -- and Phase 3
-- needed a third for the plugin lifecycle. Three copies of "what counts as too many faults" is
-- three places for the number to drift, so the rule was extracted and this delegates to it.
-- ModuleRegistry is the last holdout and stays untouched while it is the running path (strangler
-- fig); Phase 4 retires it.

--- Monotonic milliseconds for measuring INTERVALS.
--- `core.time()` is seconds-since-injection: monotonic, float, and never comparable to a
--- server timestamp, which makes it the right axis for durations (ADR 08 §2.5).
local function default_monotonic_ms()
    if core and type(core.time) == "function" then
        local ok, seconds = pcall(core.time)
        if ok and type(seconds) == "number" then return seconds * 1000 end
    end
    if core and type(core.game_time) == "function" then
        local ok, ms = pcall(core.game_time)
        if ok and type(ms) == "number" then return ms end
    end
    if type(os) == "table" and type(os.clock) == "function" then
        return os.clock() * 1000
    end
    return 0
end

---@param opts table {
---   event_bus, blackboard, error_boundary,     -- kernel collaborators
---   intent_queue,                              -- optional; COMMIT is a no-op without one
---   frame_budget_ms,                           -- optional; accounting only, no preemption
---   monotonic_ms, game_time_ms,                -- injectable clocks (tests)
---   clock                                      -- optional pre-built TickClock
--- }
function Scheduler:new(opts)
    opts = opts or {}
    local o = setmetatable({}, Scheduler)
    o._event_bus = opts.event_bus
    o._blackboard = opts.blackboard
    o._error_boundary = opts.error_boundary
    o._intent_queue = opts.intent_queue
    -- kernel/movement_release.lua, or a double. Optional: a scheduler without it simply never
    -- reconciles, which is what every test predating Phase 4b expects.
    o._movement = opts.movement
    o._movement_input = opts.movement_input
    o._frame_budget_ms = opts.frame_budget_ms
    o._monotonic_ms = opts.monotonic_ms or default_monotonic_ms
    o._game_time_ms = opts.game_time_ms
    o._clock = opts.clock or TickClock:new(opts.tick_clock)

    o._handlers = {}
    for _, stage in ipairs(Scheduler.STAGES) do o._handlers[stage] = {} end

    o._faults = FaultTracker:new()
    o._tick_index = 0
    -- The tick's frozen view, RETAINED so it outlives the tick that built it (ADR 08 §13.1 item 14).
    -- Seeded with an empty frozen snapshot rather than nil, for the same reason `tick()` hands one to
    -- a stage whose sensor threw: a nil here would put a nil-check in every consumer, and the pre-init
    -- window is exactly when a plugin taking a reference to `Sentinel.snapshot` would hit it.
    o._snapshot = Snapshot.empty(0)
    return o
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

---Register a handler on a stage.
---@param stage string One of Scheduler.STAGES
---@param owner string Attribution for budget accounting and fault reporting
---@param fn function (ctx) -> any
function Scheduler:register(stage, owner, fn)
    if not STAGE_SET[stage] then
        error("unknown scheduler stage '" .. tostring(stage) .. "' -- valid stages: "
            .. table.concat(Scheduler.STAGES, ", "), 0)
    end
    if type(owner) ~= "string" or owner == "" then
        error("a scheduler handler must name its owner (ADR 08 §5.1: attribution or it is undebuggable)", 0)
    end
    if type(fn) ~= "function" then
        error("scheduler handler for '" .. owner .. "' must be a function", 0)
    end
    local list = self._handlers[stage]
    list[#list + 1] = { owner = owner, fn = fn }
    return self
end

function Scheduler:unregister(stage, owner)
    local list = self._handlers[stage]
    if not list then return false end
    for i = #list, 1, -1 do
        if list[i].owner == owner then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local function quarantine_key(stage, owner)
    return stage .. "\0" .. owner
end

function Scheduler:is_quarantined(stage, owner)
    return self._faults:is_quarantined(quarantine_key(stage, owner))
end

-- ---------------------------------------------------------------------------
-- The tick
-- ---------------------------------------------------------------------------

function Scheduler:_publish(event, payload)
    if not self._event_bus then return end
    pcall(function() self._event_bus:publish(event, payload) end)
end

--- Run one handler: timed, isolated, attributed, and quarantined after 3 straight faults.
function Scheduler:_run_handler(stage, entry, ctx, report)
    if self:is_quarantined(stage, entry.owner) then
        return
    end

    local started = self._monotonic_ms()
    local ok, err
    if self._error_boundary then
        ok, err = self._error_boundary:wrap(entry.owner, stage, entry.fn, ctx)
    else
        ok, err = pcall(entry.fn, ctx)
    end
    local cost = self._monotonic_ms() - started
    if cost < 0 then cost = 0 end

    report.stages[stage].ms = report.stages[stage].ms + cost
    report.owners[entry.owner] = (report.owners[entry.owner] or 0) + cost
    report.total_ms = report.total_ms + cost
    report.stages[stage].entries[#report.stages[stage].entries + 1] =
        { owner = entry.owner, ms = cost, ok = ok }

    local key = quarantine_key(stage, entry.owner)
    if ok then
        self._faults:success(key)
        return
    end

    local quarantined_now, streak = self._faults:fault(key, err)
    report.faults[#report.faults + 1] =
        { stage = stage, owner = entry.owner, error = tostring(err), streak = streak }

    if quarantined_now then
        self:_publish("kernel:handler_quarantined", {
            stage = stage, owner = entry.owner, faults = streak, error = tostring(err),
        })
    end
end

---Drive one tick through all seven stages.
---@return table report
function Scheduler:tick()
    self._tick_index = self._tick_index + 1

    local delta_ms = self._clock:tick(
        self._game_time_ms and self._game_time_ms() or nil,
        nil)

    local report = {
        tick_index = self._tick_index,
        delta_ms = delta_ms,
        total_ms = 0,
        stages = {},
        owners = {},
        faults = {},
        intents = nil,
        over_budget = false,
    }
    for _, stage in ipairs(Scheduler.STAGES) do
        report.stages[stage] = { ms = 0, entries = {} }
    end

    -- STAGE 1 -- SENSE. Handlers receive a BUILDER; the snapshot is sealed the moment
    -- SENSE ends, which is what makes "frozen for the tick" structural rather than
    -- aspirational (ADR 08 §7).
    local builder = Snapshot.builder({ tick_index = self._tick_index })
    local sense_ctx = {
        tick_index = self._tick_index,
        delta_ms = delta_ms,
        snapshot = builder,
        blackboard = self._blackboard,
        events = self._event_bus,
    }
    for _, entry in ipairs(self._handlers.SENSE) do
        self:_run_handler("SENSE", entry, sense_ctx, report)
    end

    -- A sensor that threw must not cost the tick its snapshot: an empty frozen snapshot is
    -- readable and honest, whereas a nil one forces every downstream consumer to nil-check.
    local frozen = builder:freeze()
    -- Retained, not just passed. `ctx.snapshot` reaches only the handlers the scheduler itself
    -- calls; a rotation running deep inside an ACT handler, or any plugin holding `_G.Sentinel`,
    -- has no route to `ctx`. This assignment IS the read path behind `Sentinel.snapshot`.
    self._snapshot = frozen

    local ctx = {
        tick_index = self._tick_index,
        delta_ms = delta_ms,
        snapshot = frozen,
        blackboard = self._blackboard,
        events = self._event_bus,
        intents = self._intent_queue,
    }

    -- STAGES 2-5 -- EVENTS, INTERRUPT, ARBITRATE, ACT.
    for _, stage in ipairs({ "EVENTS", "INTERRUPT", "ARBITRATE", "ACT" }) do
        for _, entry in ipairs(self._handlers[stage]) do
            self:_run_handler(stage, entry, ctx, report)
        end
    end

    -- STAGE 6 -- COMMIT. The choke point: everything emitted during ACT is deduped, gated,
    -- generation-checked and executed here, against the tick's frozen snapshot.
    for _, entry in ipairs(self._handlers.COMMIT) do
        self:_run_handler("COMMIT", entry, ctx, report)
    end
    if self._intent_queue then
        local started = self._monotonic_ms()
        local ok, result = pcall(function() return self._intent_queue:commit(frozen) end)
        local cost = self._monotonic_ms() - started
        if cost < 0 then cost = 0 end
        report.stages.COMMIT.ms = report.stages.COMMIT.ms + cost
        report.total_ms = report.total_ms + cost
        if ok then
            report.intents = result
        else
            report.intents = { committed = {}, deduped = {}, rejected = {}, failed = {} }
            report.faults[#report.faults + 1] =
                { stage = "COMMIT", owner = "intent_queue", error = tostring(result), streak = 1 }
        end
    else
        report.intents = { committed = {}, deduped = {}, rejected = {}, failed = {} }
    end

    -- MOVEMENT RECONCILIATION -- still part of COMMIT, deliberately.
    --
    -- A `move` intent commits by recording a DESIRED STATE and touching no key; the keys move
    -- here. That makes this the execution half of a `move`, which is COMMIT's job ("execute"),
    -- not ACCOUNT's ("frame budget, quarantine checks, telemetry"). Putting it in ACCOUNT would
    -- read as accounting and would sit after the budget measurement it belongs inside.
    --
    -- It must run AFTER the queue drains, because that is when this tick's desire is final.
    if self._movement then
        local started = self._monotonic_ms()
        local ok, result = pcall(function()
            return self._movement.reconcile(self._movement_input)
        end)
        local cost = self._monotonic_ms() - started
        if cost < 0 then cost = 0 end
        report.stages.COMMIT.ms = report.stages.COMMIT.ms + cost
        report.total_ms = report.total_ms + cost
        if ok then
            report.movement = result
        else
            report.faults[#report.faults + 1] =
                { stage = "COMMIT", owner = "movement_reconcile", error = tostring(result), streak = 1 }
        end
    end

    -- STAGE 7 -- ACCOUNT.
    for _, entry in ipairs(self._handlers.ACCOUNT) do
        self:_run_handler("ACCOUNT", entry, ctx, report)
    end
    self:_account(report)

    return report
end

--- Budget accounting + telemetry. Names the owner that cost the most, because "the frame
--- was slow" is not actionable and "questing cost 22 ms" is.
function Scheduler:_account(report)
    local worst_owner, worst_ms = nil, -1
    for owner, ms in pairs(report.owners) do
        if ms > worst_ms then worst_owner, worst_ms = owner, ms end
    end
    report.worst_owner = worst_owner
    report.worst_owner_ms = worst_owner and worst_ms or nil

    if self._frame_budget_ms and report.total_ms > self._frame_budget_ms then
        report.over_budget = true
        self:_publish("kernel:budget_exceeded", {
            tick_index = report.tick_index,
            total_ms = report.total_ms,
            budget_ms = self._frame_budget_ms,
            worst_owner = worst_owner,
            worst_owner_ms = report.worst_owner_ms,
        })
    end

    if self._blackboard then
        pcall(function()
            self._blackboard:set("system.frame_ms", report.total_ms)
            self._blackboard:set("system.tick_index", report.tick_index)
            self._blackboard:set("system.frame_over_budget", report.over_budget)
            local cadence = self._clock:cadence()
            if cadence then
                self._blackboard:set("system.tick_cadence", cadence)
            end
            self._blackboard:set("system.delta_time_unit", self._clock:delta_time_unit())
        end)
    end
end

---This tick's frozen world view, readable from outside the pipeline.
---
---Never nil: before tick 1 it is an empty frozen snapshot. The value is the SAME object the tick's
---stages received, so what a plugin reads is what COMMIT gated on -- a copy would answer a subtly
---different question and drift as capture changed.
---@return table frozen snapshot
function Scheduler:current_snapshot()
    return self._snapshot
end

---@return table|nil stats, string|nil reason -- the MEASURED tick cadence (ADR 08 §13 q7)
function Scheduler:cadence()
    return self._clock:cadence()
end

---@return table the tick clock, for callers that need the delta_time calibration verdict
function Scheduler:clock()
    return self._clock
end

function Scheduler:tick_index()
    return self._tick_index
end

return Scheduler
