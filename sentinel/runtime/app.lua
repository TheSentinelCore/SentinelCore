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
local ControlBroker = require("kernel/control_broker")
local ActivityStack = require("kernel/activity_stack")
local PluginRegistry = require("kernel/plugin_registry")
local KernelConfig = require("kernel/config")
local Timing = require("kernel/timing")
local SpellCatalog = require("kernel/catalogs/spell")
local Api = require("kernel/api")

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

    -- ADR 08 §3.2 -- the commit choke point. Still no executors registered: the queue gates
    -- and refuses by name (`no_executor`) until Phase 4 ports a real rotation. That is the
    -- intended fail-closed behaviour, not an oversight.
    o._intent_queue = IntentQueue:new()

    -- ADR 08 §6 -- the arbiter. `input` is left unset so the broker reaches the live
    -- `core.input` through kernel/movement_release.lua, which is the kernel's ONLY
    -- `core.input.*` call site. Tests inject a double there.
    o._control_broker = ControlBroker:new({
        event_bus = o._event_bus,
        intent_queue = o._intent_queue,
    })
    o._activity_stack = ActivityStack:new({
        broker = o._control_broker,
        event_bus = o._event_bus,
    })

    -- ADR 08 §6.1 -- close the revocation race. The generation stamped on an intent when it
    -- was emitted is re-checked here at the commit point, so an intent emitted early in the
    -- tick under a lease that was revoked later in the SAME tick does not commit.
    o._intent_queue:set_generation_validator(function(intent)
        return o._control_broker:is_generation_valid(intent)
    end)

    -- ADR 08 §8 -- the plugin contract. Runs ALONGSIDE ModuleRegistry, which still drives combat
    -- and questing; Phase 4 migrates the first real consumer. Nothing is deleted before then,
    -- because deleting the working path while this one has no consumer leaves nothing running.
    o._kernel_config = KernelConfig:new()
    -- One spell catalog for the whole app. §5.1: catalogs are kernel precisely because duplicating
    -- reference data "costs memory and drifts".
    o._spell_catalog = SpellCatalog:new()
    -- ADR §2.5 -- GCD state, derived from the kernel's own cast timestamps on the game_time ms axis.
    -- GCD membership comes from the catalog rather than a second hardcoded list, so "is this on the
    -- GCD" has exactly one answer.
    o._timing = Timing:new({
        is_gcd_spell = function(id) return o._spell_catalog:is_gcd_spell(id) end,
    })
    o._plugin_registry = PluginRegistry:new({
        api_version = Api.API_VERSION,
        kernel_provides = Api.KERNEL_CAPABILITIES,
        event_bus = o._event_bus,
        config = o._kernel_config,
    })

    o._scheduler = Scheduler:new({
        event_bus = o._event_bus,
        blackboard = o._blackboard,
        error_boundary = o._error_boundary,
        intent_queue = o._intent_queue,
        frame_budget_ms = FRAME_BUDGET_MS,
    })
    o:_register_kernel_stages()

    -- The API surface is BUILT but deliberately NOT published to `_G.Sentinel` -- see
    -- SentinelApp:publish_api() for why.
    o._api = Api.build({
        app = o,
        registry = o._plugin_registry,
        config = o._kernel_config,
        broker = o._control_broker,
        activity_stack = o._activity_stack,
        intent_queue = o._intent_queue,
        blackboard = o._blackboard,
        event_bus = o._event_bus,
        scheduler = o._scheduler,
        nav = o._nav_adapter,
    })

    return o
end

---Publish the kernel surface at `_G.Sentinel`.
---
---NOT called from main.lua in Phase 3, and that is a deliberate hold rather than an omission.
---`main.lua` currently owns `_G.Sentinel`: it builds the table at main.lua:160 and ASSIGNS into it
---(`_G.Sentinel.app = app`, main.lua:153 and :201). The kernel surface is read-only by design --
---a plugin must not be able to mutate what every other plugin reads -- so publishing over it would
---throw on the first assignment.
---
---Worse, the legacy table is what the live-debug workflow uses: HANDOFF.md's restart snippet calls
---`_G.Sentinel.questing()`, and `.combat()` / `.reload()` are the documented entry points for
---in-game verification. Clobbering them in a phase whose own deliverables cannot be verified
---in-game would break the only workflow that can verify anything.
---
---Phase 4 merges the two surfaces when the first real plugin needs `_G.Sentinel`, at which point
---the legacy accessors move onto the kernel surface as static fields and this becomes a one-line
---call from main.lua. Publication semantics are fully covered by tests/kernel/test_api.lua.
function SentinelApp:publish_api()
    return Api.publish({
        app = self,
        registry = self._plugin_registry,
        config = self._kernel_config,
        broker = self._control_broker,
        activity_stack = self._activity_stack,
        intent_queue = self._intent_queue,
        blackboard = self._blackboard,
        event_bus = self._event_bus,
        scheduler = self._scheduler,
        nav = self._nav_adapter,
    })
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

    -- The broker's tick index must be current before INTERRUPT (§7 step 3) can evaluate
    -- cool-downs, and INTERRUPT runs before ARBITRATE (step 4). This publishes the index only;
    -- all arbitration stays in ARBITRATE where §7 puts it.
    sched:register("SENSE", "control_broker.clock", function(ctx)
        self._control_broker:begin_tick(ctx.tick_index)
    end)

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

    -- Plugin lifecycle upkeep, at the end of SENSE so it reads the tick's frozen snapshot.
    --
    -- `refresh_eligibility` is internally THROTTLED: `applies_to` reads class/spec/level, which §7
    -- puts in the cold tier (poll-only). Calling it every tick is the RXPGuides mistake from the
    -- opposite direction -- §13 risk 6 caches a level-dependent gate and never invalidates it,
    -- while re-reading cold data 60 times a second just burns the frame budget.
    sched:register("SENSE", "plugin_registry", function(ctx)
        self._plugin_registry:refresh_eligibility(ctx.snapshot, ctx.tick_index)
        -- §2.4's deferred queue, re-drained for the first ~60 ticks: a plugin the injector loads
        -- after us can push at any point during startup. A no-op once the window closes.
        Api.tick_pending({ registry = self._plugin_registry }, ctx.tick_index)
    end)

    -- 3. INTERRUPT -- safety evaluators may push/pop the ActivityStack. No evaluators are
    --    registered yet (anti-stuck and corpse recovery are Phase 5 built-in plugins); the
    --    stage runs the real hook so those plug in rather than re-cutting the pipeline.
    sched:register("INTERRUPT", "activity_stack", function(ctx)
        self._activity_stack:evaluate(ctx)
    end)

    -- 4. ARBITRATE -- "ControlBroker resolves leases, expires TTLs, fires revocations,
    --    force-releases keys." In that order, inside ControlBroker:arbitrate.
    sched:register("ARBITRATE", "control_broker", function(ctx)
        self._control_broker:arbitrate(ctx.tick_index)
    end)

    -- 5. ACT -- the existing module registry, driven as one attributed handler.
    sched:register("ACT", "module_registry", function(ctx)
        self._registry:tick_all(ctx.delta_ms)
    end)

    -- 6. COMMIT is driven by the scheduler itself (it owns the IntentQueue).

    -- 7. ACCOUNT -- retire this tick's caretakers (ADR 08 §6.1: "the kernel flips its
    --    `revoked` flag at TICK END"). Deliberately here and not in COMMIT: an intent
    --    submitted during ACT must still validate against its live lease while COMMIT runs.
    sched:register("ACCOUNT", "control_broker.end_tick", function()
        self._control_broker:end_tick()
    end)
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

function SentinelApp:get_control_broker()
    return self._control_broker
end

function SentinelApp:get_activity_stack()
    return self._activity_stack
end

function SentinelApp:get_plugin_registry()
    return self._plugin_registry
end

function SentinelApp:get_kernel_config()
    return self._kernel_config
end

function SentinelApp:get_timing()
    return self._timing
end

--- The kernel API surface. Reachable here in Phase 3; see publish_api() for why it is not yet at
--- `_G.Sentinel`.
function SentinelApp:get_api()
    return self._api
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
