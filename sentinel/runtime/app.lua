local EventBus = require("core/event_bus")
local Blackboard = require("core/blackboard")
local ErrorBoundary = require("core/error_boundary")
local ModuleRegistry = require("runtime/module_registry")
local SensorHub = require("runtime/sensor_hub")
local CallbackBridge = require("runtime/callback_bridge")
local NavAdapter = require("integrations/nav_client/adapter")
local IziBridge = require("integrations/izi_bridge")
local Scheduler = require("kernel/scheduler")
local IntentQueue = require("kernel/intent_queue")
local SnapshotSource = require("kernel/snapshot_source")

local SentinelApp = {}
SentinelApp.__index = SentinelApp

-- Frame budget in milliseconds. ACCOUNTING ONLY -- the scheduler names the owner that
-- burned the frame, it cannot preempt one mid-call (ADR 08 §13 q12: coroutines are
-- undocumented in this SDK). The value is deliberately conservative and provisional: the
-- real tick cadence is not documented (ADR 08 §13 q7) and is being MEASURED by the
-- scheduler's TickClock. Tune it once `system.tick_cadence` has reported from a live client.
local FRAME_BUDGET_MS = 8

function SentinelApp:new()
    local logger = function(message)
        if core and core.log_error then
            core.log_error(message)
        end
    end
    local o = setmetatable({}, SentinelApp)
    o._event_bus = EventBus:new(logger)
    o._blackboard = Blackboard:new()
    o._error_boundary = ErrorBoundary:new(o._event_bus)
    o._registry = ModuleRegistry:new()
    o._sensor_hub = SensorHub:new(o._blackboard, o._event_bus)
    o._callback_bridge = CallbackBridge:new(o._event_bus)
    -- B4: shared adapter (see integrations/nav_client/adapter.lua) so combat and
    -- questing stop stealing the nav client from each other via private instances.
    o._nav_adapter = NavAdapter.get_shared(o._event_bus)
    o._izi_bridge = IziBridge:new()

    -- ADR 08 §3.2 -- the commit choke point. No executors are registered in Phase 1: the
    -- queue is structure and gates only until the ControlBroker (Phase 2) can issue the
    -- leases that authorize an intent. Anything submitted now is refused by name
    -- (`no_executor`), which is the intended fail-closed behaviour, not an oversight.
    o._intent_queue = IntentQueue:new()

    o._scheduler = Scheduler:new({
        event_bus = o._event_bus,
        blackboard = o._blackboard,
        error_boundary = o._error_boundary,
        intent_queue = o._intent_queue,
        frame_budget_ms = FRAME_BUDGET_MS,
    })
    o:_register_kernel_stages()

    return o
end

--- Wire the existing 4-step frame onto the 7-stage pipeline (ADR 08 §7).
---
--- STRANGLER FIG: the ModuleRegistry keeps running, unchanged, as a single ACT-stage
--- handler. Both paths are live until Phase 3 replaces the registry with manifest-based
--- plugin registration. Nothing here deletes the old road while it is still being driven on.
---
--- Every handler closes over `self` and reads its collaborator AT CALL TIME rather than
--- capturing it at registration, so a test can swap `app._registry` (or any other
--- collaborator) for a stub after construction and the pipeline picks it up.
function SentinelApp:_register_kernel_stages()
    local sched = self._scheduler

    -- 1. SENSE -- sense once, freeze for the tick.
    sched:register("SENSE", "sensor_hub", function()
        self._sensor_hub:refresh()
    end)
    sched:register("SENSE", "snapshot", function(ctx)
        -- ADR 08 §2.7: handles are held transiently INSIDE the sensor and never stored.
        -- The player object on the blackboard is a live pointer; SnapshotSource extracts
        -- values from it and the snapshot keeps only those.
        SnapshotSource.capture_player(ctx.snapshot, self._blackboard:get("player.object"))
    end)
    -- ADR 08 §7 names this one explicitly: nav_adapter:poll() was the single call in the
    -- old frame with NO error wrapper while both of its neighbours had one. Registered as
    -- an ordinary handler, it is now wrapped by construction.
    sched:register("SENSE", "nav_adapter", function()
        self._nav_adapter:poll()
    end)

    -- 2. EVENTS -- publish the engine frame to subscribers.
    sched:register("EVENTS", "callback_bridge", function()
        self._callback_bridge:on_update()
    end)

    -- 3. INTERRUPT and 4. ARBITRATE have no kernel occupants in Phase 1. The safety
    --    evaluators and the ControlBroker are Phase 2; the stages exist so that work plugs
    --    in rather than re-cutting the pipeline.

    -- 5. ACT -- the existing module registry, driven as one attributed handler.
    sched:register("ACT", "module_registry", function(ctx)
        self._registry:tick_all(ctx.delta_ms)
    end)

    -- 6. COMMIT is driven by the scheduler itself (it owns the IntentQueue).
    -- 7. ACCOUNT is the scheduler's own budget/telemetry pass.
end

function SentinelApp:initialize()
    -- Register modules declaratively via ModuleRegistry
    self._registry:register_all(self._blackboard, self._event_bus)

    -- Get module reference for direct access. NOTE: this is the registry's module
    -- WRAPPER (modules/combat/init.lua), whose interface is init/tick/shutdown --
    -- not a raw SentinelCombat. Use :get_combat() to reach the engine itself.
    self._combat = self._registry:get("combat")

    -- Initialize modules. register_all/initialize_all already drives each wrapper's
    -- init(), which is what calls SentinelCombat:initialize().
    self._registry:initialize_all(self)
end

function SentinelApp:shutdown()
    self._sensor_hub:shutdown()
    -- B7: registry:shutdown_all() already calls module:shutdown() on every
    -- registered module. A redundant manual loop here used to shut every
    -- module down TWICE per SentinelApp:shutdown() -- e.g. combat's
    -- shutdown re-ran a full disengage (chase stop -> nav stop -> profile
    -- reset -> DISENGAGED publish) a second time on every reload. The
    -- registry is now the single shutdown path.
    self._registry:shutdown_all()
end

-- ---------------------------------------------------------------------------
-- Injector callbacks
--
-- ADR 08 §5.1: "No engine-level error isolation is documented -- EVERY CALLBACK must
-- self-pcall." on_update was wrapped; on_pre_tick, on_render, on_render_menu and both
-- spell-cast callbacks were not, so a throw in any of them escaped into the injector.
-- ---------------------------------------------------------------------------

function SentinelApp:on_pre_tick()
    self._error_boundary:wrap("callback_bridge", "on_pre_tick", function()
        self._callback_bridge:on_pre_tick()
    end)
end

function SentinelApp:on_update()
    return self._scheduler:tick()
end

function SentinelApp:on_render()
    self._error_boundary:wrap("callback_bridge", "on_render", function()
        self._callback_bridge:on_render()
    end)
end

function SentinelApp:on_render_window()
    -- No editor UI to render in combat-only mode
end

function SentinelApp:on_render_menu()
    self._error_boundary:wrap("callback_bridge", "on_render_menu", function()
        self._callback_bridge:on_render_menu()
    end)
end

function SentinelApp:on_spell_cast(data)
    self._error_boundary:wrap("callback_bridge", "on_spell_cast", function()
        self._callback_bridge:on_spell_cast(data)
    end)
end

function SentinelApp:on_legit_spell_cast(data)
    self._error_boundary:wrap("callback_bridge", "on_legit_spell_cast", function()
        self._callback_bridge:on_legit_spell_cast(data)
    end)
end

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------

function SentinelApp:get_blackboard()
    return self._blackboard
end

function SentinelApp:get_event_bus()
    return self._event_bus
end

function SentinelApp:get_module(name)
    return self._registry:get(name)
end

function SentinelApp:get_scheduler()
    return self._scheduler
end

function SentinelApp:get_intent_queue()
    return self._intent_queue
end

--- ADR 08 §7 names `_izi_bridge` as constructed-and-never-read. It is a real collaborator
--- -- modules/combat/strategies/{default,grind}_target_strategy.lua both consume an
--- izi_bridge for time-to-die scoring -- so the fix is to make the app's instance
--- REACHABLE rather than to delete it and leave each module building a private one.
function SentinelApp:get_izi_bridge()
    return self._izi_bridge
end

--- The MEASURED tick cadence (ADR 08 §13 q7). Returns nil plus a reason until the
--- scheduler has enough samples -- it never reports a guessed rate.
function SentinelApp:get_cadence()
    return self._scheduler:cadence()
end

return SentinelApp
