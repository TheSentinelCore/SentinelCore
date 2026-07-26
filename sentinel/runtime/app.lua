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
local Spells = require("kernel/spells")
local Units = require("kernel/units")
local Forecast = require("kernel/forecast")
local AoeHelper = require("shared/aoe_helper")
local IntentExecutors = require("kernel/intent_executors")
local MovementRelease = require("kernel/movement_release")
local SpellHelper = require("shared/spell_helper")
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
    -- THE ONLY IziBridge in the process. `modules/combat/init.lua` used to build a second one, so
    -- the app's instance and combat's instance kept independent IZI state and the app's was
    -- unreachable (ADR 08 §7 recorded it as "constructed and never read"). Combat now takes THIS one
    -- at `init(app)` time -- see modules/combat/init.lua.
    o._izi_bridge = IziBridge:new()
    -- ADR 08 §5.1. The public face of that bridge: `Sentinel.forecast`, the service the six former
    -- readers of `module.combat.izi_bridge` consult now that the blackboard holds values only.
    o._forecast = Forecast:new({ bridge = o._izi_bridge })

    -- ADR 08 §3.2 -- the commit choke point. Phase 4 registers the real cast/target executors on
    -- it, so from here on this is the single path by which the kernel affects the game.
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
    -- ADR §2.5 -- GCD state, derived from the kernel's own cast timestamps on the game_time ms axis.
    -- Constructed before the intent queue's executors, which are what feed it.
    -- One spell catalog for the whole app. §5.1: catalogs are kernel precisely because duplicating
    -- reference data "costs memory and drifts".
    o._spell_catalog = SpellCatalog:new()
    o._units = Units:new()
    -- `shared/aoe_helper` is the existing wrapper over the injector's `spell_prediction` module; the
    -- kernel adapts it rather than re-deriving optimal AoE placement.
    o._spells = Spells:new({ spell_helper = SpellHelper, spell_prediction = AoeHelper })
    -- GCD membership comes from the catalog rather than a second hardcoded list, so "is this on the
    -- GCD" has exactly one answer.
    o._timing = Timing:new({
        is_gcd_spell = function(id) return o._spell_catalog:is_gcd_spell(id) end,
    })

    -- ADR 08 §3.2/§6.3 -- intents become packets here, and nowhere else.
    --
    -- `common/modules/spell_queue` and the spell-book helper exist only inside the injector, so both
    -- are resolved through a GUARDED require for the same reason the IziBridge one is: a top-level
    -- require of an injector-only module makes the entire composition root unloadable offline, and
    -- an untestable composition root is how a file that sends packets ends up with no tests.
    local ok_sq, spell_queue = pcall(require, "common/modules/spell_queue")
    IntentExecutors.install({
        intent_queue = o._intent_queue,
        -- ADR 08 §13.1 item 19, made live by the Phase 4c cast conversion. Left unset, the executor
        -- resolves `"target"` as `player:get_target()` -- the CLIENT's target -- while the rotation
        -- aims at `combat.target`. They usually agree and are not guaranteed to, so every converted
        -- cast would have silently fought a different mob. One resolution, shared.
        unit_target = o:unit_target_resolver(),
        -- The GCD gate's clock, and what the cast executor calls `note_cast` on. `gcd_gate` FAILS
        -- OPEN without it (`if not timing then return true end`), so an unwired clock does not
        -- break loudly -- it silently admits every cast for the whole session. Pinned at the SDK
        -- boundary by `test_the_gcd_gate_holds_a_second_cast_because_timing_is_wired_to_the_executors`,
        -- because nothing that drives `Timing` directly can see a `Timing` that is merely unplugged.
        timing = o._timing,
        -- `spell_catalog`, `units` and `spells` WERE PASSED HERE AND NEVER READ. Phase 4e reverted
        -- each composition-root hand-off in turn and recorded what reddened; these three reddened
        -- nothing, and the reason turned out not to be a missing test -- `kernel/intent_executors.lua`
        -- reads exactly seven deps (`input`, `intent_queue`, `object_manager`, `spell_helper`,
        -- `spell_queue`, `timing`, `unit_target`) and none of them is in this group.
        --
        -- Deleted rather than pinned: there is no wiring here to observe. All three reach plugins
        -- through the API surface instead (`_kernel_table` below), where reverting each one DOES
        -- redden -- 8, 4 and 3 cases respectively. A dead argument that reads as wiring is worse
        -- than no argument, because the next reader trying to work out why the catalog is unused
        -- starts from the assumption that it is.
        spell_queue = ok_sq and spell_queue or nil,
        object_manager = core and core.object_manager or nil,
        spell_helper = SpellHelper,
        input = core and core.input or nil,
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
        -- Drives the `move` intent's desired state onto real keys after COMMIT.
        -- `movement_input` is left unset for the same reason the broker's is: the module
        -- resolves the live `core.input` itself, in the kernel's one permitted place.
        movement = MovementRelease,
    })
    o:_register_kernel_stages()

    -- The API surface is BUILT but deliberately NOT published to `_G.Sentinel` -- see
    -- SentinelApp:publish_api() for why.
    o._api = Api.build(o:_kernel_table())

    return o
end

--- The unit the ROTATION is fighting, which is not always the one the client has targeted.
---
--- `combat.target` is the combat module's own selection; `player.target` is the sensor's read of the
--- client. The module selects before the client is set and holds a selection across a tick where the
--- client's is cleared, so the two diverge in exactly the moments that matter. This mirrors
--- `rotations/mage_frost/frost_support.player_and_target` deliberately -- a cast must land on the unit
--- the rotation decided to attack, not on whatever the client happens to point at when COMMIT runs.
---
--- Returns nil rather than falling back further: an unresolved unit makes the castable gate refuse,
--- which is loud and correct, whereas guessing a unit sends a real packet at the wrong thing.
---@return table|nil handle
function SentinelApp:selected_target()
    return self._blackboard:get("combat.target") or self._blackboard:get("player.target")
end

--- `selected_target` as the callable `Executors.install` takes, bound to this app.
---
--- A method reference cannot be handed over directly (the executor calls it with the player, not
--- with the app), so the binding is made once, here, rather than inline at the install site where a
--- later reader would have to work out which receiver it closes over.
---@return function (player) -> table|nil
function SentinelApp:unit_target_resolver()
    return function() return self:selected_target() end
end

--- The components the kernel surface resolves against.
---
--- ONE builder, because there used to be two. `new()` and `publish_api()` each hand-maintained
--- their own literal, and they had already drifted: `units` and `spells` were passed by
--- `publish_api` and forgotten by `new`, so `app:get_api().units` was nil while `_G.Sentinel.units`
--- worked. Nothing failed -- the live getter returns nil for an absent component, which is the same
--- silent shape as the `snapshot` defect. `tests/kernel/test_capability_resolution.lua` found it by
--- checking both surfaces; this makes the two impossible to disagree.
---@param host table|nil verbs the host contributes (see publish_api)
function SentinelApp:_kernel_table(host)
    return {
        app = self,
        host = host,
        registry = self._plugin_registry,
        config = self._kernel_config,
        broker = self._control_broker,
        activity_stack = self._activity_stack,
        intent_queue = self._intent_queue,
        blackboard = self._blackboard,
        event_bus = self._event_bus,
        scheduler = self._scheduler,
        timing = self._timing,
        spell_catalog = self._spell_catalog,
        units = self._units,
        spells = self._spells,
        forecast = self._forecast,
        nav = self._nav_adapter,
    }
end

---Publish the kernel surface at `_G.Sentinel`.
---
---@param host table|nil Verbs the host contributes to the surface (`reload`, `questing`, ...). The
---kernel owns components; it does not own these, because it does not build the app -- `main.lua`
---does, and only the host can tear one down and stand a new one up. A host verb colliding with a
---kernel field is refused at build time rather than silently shadowing it.
function SentinelApp:publish_api(host)
    local surface, drain = Api.publish(self:_kernel_table(host))
    -- The publish drain just registered whatever pushed itself onto `__SentinelPending` before we
    -- came up. If ANY of it is a rotation, the kernel owns rotation selection from here on — and
    -- the flag must be visible BEFORE initialize() runs the combat module, or the module builds
    -- its own profile through Registry.resolve and the plugin path idles behind the §14 guard.
    self:_note_rotation_ownership()
    return surface, drain
end

---Set `rotation.kernel_pending` iff a plugin of kind "rotation" has registered. Detection is by
---KIND — the kernel's own manifest vocabulary — never by plugin name or path: the app has no idea
---which rotation packages exist, only that something claimed the rotation role. Called after the
---publish drain and again from the SENSE stage, so an injector-loaded rotation that arrives
---during the §2.4 window is noticed too.
function SentinelApp:_note_rotation_ownership()
    if self._blackboard:get("rotation.kernel_pending") then return end
    local S = PluginRegistry.STATES
    for _, state in ipairs({ S.VALIDATED, S.LOADED, S.ELIGIBLE, S.ACTIVE }) do
        for _, id in ipairs(self._plugin_registry:ids_in_state(state)) do
            local m = self._plugin_registry:manifest(id)
            if m and m.kind == "rotation" then
                self._blackboard:set("rotation.kernel_pending", true)
                return
            end
        end
    end
end

---Activate the first ELIGIBLE rotation plugin and publish its tree for the combat module.
---
---Guards, in order (each is a §14 hazard, not decoration):
---  * `rotation.profile_id` set with no plugin id — `Registry.resolve`'s fallback built the
---    profile first; building again here is the double-drive. Defer to it.
---  * The plugin that built the current profile was demoted by `refresh_eligibility` (class or
---    level moved) — retire its tree so a successor can activate.
---  * No `player.class` in the snapshot yet — boot silence is NOT "no rotation matches"; raising
---    the unmatched flag here would disable combat during startup.
---@param snapshot table|nil the tick's frozen snapshot
function SentinelApp:_activate_eligible_rotation(snapshot)
    local registry = self._plugin_registry
    local S = PluginRegistry.STATES

    local existing = self._blackboard:get("rotation.profile_id")
    local built_by = self._blackboard:get("rotation.kernel_plugin_id")
    if existing ~= nil then
        if built_by == nil then return end -- the fallback path owns the profile
        if registry:state(built_by) == S.ACTIVE then return end
        -- Demoted underneath us: retire the stale tree and fall through to a successor.
        self._blackboard:set("rotation.kernel_profile", nil)
        self._blackboard:set("rotation.kernel_plugin_id", nil)
        self._blackboard:set("rotation.profile_id", nil)
    end

    local saw_rotation = false
    for _, id in ipairs(registry:order()) do
        local m = registry:manifest(id)
        if m and m.kind == "rotation" then
            saw_rotation = true
            -- A rotation that arrived through the §2.4 tick-window drain rather than at publish:
            -- flip ownership now. (If the combat module already built via the fallback, the §14
            -- guard above keeps deferring to it — a late plugin takes over only after a demotion.)
            if not self._blackboard:get("rotation.kernel_pending") then
                self._blackboard:set("rotation.kernel_pending", true)
            end
            local state = registry:state(id)
            if state == S.ACTIVE then return end
            if state == S.ELIGIBLE then
                local ok, reason = registry:activate(id, {
                    blackboard = self._blackboard,
                    event_bus = self._event_bus,
                    api = _G.Sentinel,
                })
                if ok then
                    self._blackboard:set("rotation.kernel_profile", registry:tree(id))
                    self._blackboard:set("rotation.kernel_plugin_id", id)
                else
                    -- preflight veto / build error: the registry recorded the reason; a veto is
                    -- retryable next tick, so this is not the unmatched verdict below.
                    self:_log_error("rotation activation refused: " .. id
                        .. " (" .. tostring(reason) .. ")")
                end
                return
            end
        end
    end

    -- Every bundled rotation is ineligible for this character. Only a CONFIRMED class earns the
    -- verdict — it mirrors Registry.resolve's fail-loud nil, through the plugin path.
    if saw_rotation and snapshot ~= nil and snapshot:get("player.class") ~= nil then
        self._blackboard:set("rotation.kernel_unmatched", true)
    end
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
    --
    -- Order inside the handler matters and is the §14 wiring: drain first so a late manifest is
    -- in the registry this tick, re-resolve only when something actually landed (`discover` clears
    -- `is_resolved`), refresh eligibility over the result, then activate. Activation last, so a
    -- manifest can go DISCOVERED -> ACTIVE inside one tick instead of dribbling across four.
    sched:register("SENSE", "plugin_registry", function(ctx)
        -- §2.4's deferred queue, re-drained for the first ~60 ticks: a plugin the injector loads
        -- after us can push at any point during startup. A no-op once the window closes.
        Api.tick_pending({ registry = self._plugin_registry }, ctx.tick_index)
        if not self._plugin_registry:is_resolved() then
            self._plugin_registry:resolve()
        end
        self._plugin_registry:refresh_eligibility(ctx.snapshot, ctx.tick_index)
        self:_activate_eligible_rotation(ctx.snapshot)
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

---Same sink the EventBus logger uses; a method so stage handlers can reach it through `self`.
function SentinelApp:_log_error(message)
    if core and core.log_error then
        pcall(core.log_error, "[SentinelApp] " .. tostring(message))
    end
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

--- The one IziBridge, for the collaborators that take it BY CONSTRUCTOR.
---
--- ADR 08 §7 named `_izi_bridge` as constructed-and-never-read, and until Phase 4d it genuinely had
--- zero callers -- the accessor existed, and combat built its own bridge anyway, so the two
--- instances never met. `modules/combat/init.lua:init(app)` is now its ONE caller, and that is what
--- makes this the single instance rather than one of two.
---
--- The comment this replaces named `strategies/{default,grind}_target_strategy.lua` as the readers.
--- They are consumers, but they never called this: they receive the bridge through
--- `SentinelCombat -> TargetSelector -> StrategyFactory`, which is why the reach had to be closed at
--- the top of that chain and not at the bottom.
---
--- Prefer `get_forecast()` for anything that only needs the predictions. This returns the raw
--- injector adapter, and its surface is the SDK's shape rather than the kernel's.
function SentinelApp:get_izi_bridge()
    return self._izi_bridge
end

--- The kernel's forecast service (`Sentinel.forecast`). One per app, wrapping the one bridge.
function SentinelApp:get_forecast()
    return self._forecast
end

--- The MEASURED tick cadence (ADR 08 §13 q7). Returns nil plus a reason until the
--- scheduler has enough samples -- it never reports a guessed rate.
function SentinelApp:get_cadence()
    return self._scheduler:cadence()
end

return SentinelApp
