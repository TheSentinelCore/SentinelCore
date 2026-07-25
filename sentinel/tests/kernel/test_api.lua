-- tests/kernel/test_api.lua
-- `_G.Sentinel`, the live-getter handshake, and the deferred registration queue.
--
-- ADR 08 §2.3: no documented plugin load order, and plugin A cannot `require` plugin B, so `_G` is
-- the only handshake. §2.4: adopt the pattern already proven at `SentinelNavClient/main.lua:106`,
-- and "keep the deferred `__SentinelPending` queue as well -- THE GETTER FIXES READS, THE QUEUE
-- FIXES REGISTRATION."
--
-- ADR §12's Phase 3 exit criterion: "A rotation registers in EITHER LOAD ORDER."

local Api = require("kernel/api")
local PluginRegistry = require("kernel/plugin_registry")
local S = PluginRegistry.STATES
local Config = require("kernel/config")
local ControlBroker = require("kernel/control_broker")
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local Fixture = require("tests/fixtures/awkward_rotation")
local T = require("tests/test_util")

local M = {}

--- Every test starts from a clean global namespace: these tests write `_G.Sentinel` and
--- `_G.__SentinelPending`, and a leaked value would make the next test pass for the wrong reason.
local function reset_globals()
    _G.Sentinel = nil
    _G[Api.PENDING_GLOBAL] = nil
end

local function make_kernel()
    local bus = EventBus:new(function() end)
    local config = Config:new()
    return {
        event_bus = bus,
        blackboard = Blackboard:new(),
        config = config,
        broker = ControlBroker:new({ event_bus = bus }),
        registry = PluginRegistry:new({
            api_version = Api.API_VERSION,
            kernel_provides = Api.KERNEL_CAPABILITIES,
            event_bus = bus,
            config = config,
        }),
    }
end

--- Runs `fn` against a pristine global namespace, then puts back whatever was there before.
---
--- RESTORING matters, not just clearing. The offline harness publishes a real `_G.Sentinel` so that
--- plugin tests (`tests/rotations/*`) have a kernel to talk to -- plugins reach the kernel through
--- `_G` and nothing else, which is the whole point of the require audit. These tests run FIRST, so
--- leaving `_G.Sentinel = nil` behind stripped the surface out from under every plugin test that
--- followed, and they failed with `attempt to call field 'condition' (a nil value)` a long way from
--- the cause.
local function with_clean_globals(fn)
    local saved_surface = _G.Sentinel
    local saved_pending = _G[Api.PENDING_GLOBAL]

    reset_globals()
    local ok, err = pcall(fn)

    _G.Sentinel = saved_surface
    _G[Api.PENDING_GLOBAL] = saved_pending
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------
-- The surface
-- ---------------------------------------------------------------------------

function M.test_publish_installs_the_global()
    with_clean_globals(function()
        local kernel = make_kernel()
        Api.publish(kernel)
        T.assert_not_nil(_G.Sentinel)
        T.assert_equal(_G.Sentinel.API_VERSION, "1.0.0")
    end)
end

function M.test_static_fields_are_present()
    with_clean_globals(function()
        Api.publish(make_kernel())
        T.assert_equal(_G.Sentinel.Status.DONE, "DONE")
        T.assert_equal(_G.Sentinel.Channel.MOVEMENT, "MOVEMENT")
        T.assert_equal(_G.Sentinel.Band.COMBAT.min, 50)
    end)
end

function M.test_live_getters_resolve_the_kernel_components()
    with_clean_globals(function()
        local kernel = make_kernel()
        Api.publish(kernel)
        T.assert_true(_G.Sentinel.control == kernel.broker)
        T.assert_true(_G.Sentinel.state == kernel.blackboard)
        T.assert_true(_G.Sentinel.events == kernel.event_bus)
        T.assert_true(_G.Sentinel.config == kernel.config)
        T.assert_true(_G.Sentinel.plugins == kernel.registry)
    end)
end

--- THE POINT of the live getter (§2.4): a reference taken before a component exists must resolve to
--- it afterwards. A plain table would have captured nil forever.
function M.test_a_getter_read_before_the_component_exists_resolves_later()
    with_clean_globals(function()
        local kernel = { registry = nil, broker = nil }
        local surface = Api.build(kernel)

        T.assert_nil(surface.control, "nothing to resolve yet")

        local bus = EventBus:new(function() end)
        kernel.broker = ControlBroker:new({ event_bus = bus })

        T.assert_true(surface.control == kernel.broker,
            "the SAME surface reference must now resolve the broker -- this is the live getter")
    end)
end

--- ADR §10's surface lists services Phase 1-3 does not implement. They must be ABSENT, not stubbed:
--- a field that exists and returns nil fails at the call site, arbitrarily far from the cause.
function M.test_unimplemented_services_are_absent_rather_than_nil_returning_stubs()
    with_clean_globals(function()
        Api.publish(make_kernel())
        for _, field in ipairs({ "objectives", "facts", "persist" }) do
            T.assert_nil(_G.Sentinel[field],
                "'" .. field .. "' is Phase 5+ and must not be published as a stub")
        end
    end)
end

--- `aura` is a stateless module and sits on the table directly. `spell` is a per-app INSTANCE and
--- resolves live, so every plugin shares ONE catalog -- a rotation carrying its own rank table would
--- duplicate DB-baked data per class, which is exactly the drift §5.1 says catalogs prevent.
function M.test_catalogs_shares_one_spell_catalog_and_exposes_aura_directly()
    with_clean_globals(function()
        local kernel = make_kernel()
        kernel.spell_catalog = { marker = "the-one-catalog" }
        Api.publish(kernel)

        T.assert_true(type(_G.Sentinel.catalogs.aura.has_any) == "function", "aura is a module")
        T.assert_true(_G.Sentinel.catalogs.spell == kernel.spell_catalog,
            "spell must resolve to the app's single instance, not a fresh one per reader")
    end)
end

--- Absent when the app has not built one, rather than a stub that fails later at the call site.
function M.test_an_unbuilt_spell_catalog_is_absent_rather_than_stubbed()
    with_clean_globals(function()
        Api.publish(make_kernel())
        T.assert_nil(_G.Sentinel.catalogs.spell)
    end)
end

--- The BT library needs both halves. Handing back the factory alone would make every plugin invent
--- its own SUCCESS/FAILURE strings, and two trees that disagree on what "done" means is a bug that
--- only shows up under composition.
function M.test_the_bt_library_exposes_both_constructors_and_the_status_enum()
    with_clean_globals(function()
        Api.publish(make_kernel())
        T.assert_true(type(_G.Sentinel.bt.sequence) == "function")
        T.assert_true(type(_G.Sentinel.bt.priority_selector) == "function")
        T.assert_equal(_G.Sentinel.bt.Status.SUCCESS, "SUCCESS")
    end)
end

--- `timing` left that list in Phase 4: the frost port needs `gcd_remaining_est` to avoid
--- double-casting, so the service was built (kernel/timing.lua) rather than worked around.
function M.test_timing_is_published_now_that_it_exists()
    with_clean_globals(function()
        local kernel = make_kernel()
        kernel.timing = { marker = "timing" }
        Api.publish(kernel)
        T.assert_true(_G.Sentinel.timing == kernel.timing)
    end)
end

function M.test_available_enumerates_only_real_capabilities()
    with_clean_globals(function()
        Api.publish(make_kernel())
        local available = _G.Sentinel.available()
        local set = {}
        for _, c in ipairs(available) do set[c] = true end
        T.assert_true(set["control"], "control is implemented")
        T.assert_true(set["intents"])
        T.assert_true(set["timing.gcd"], "timing.gcd IS implemented as of Phase 4")
        T.assert_true(set["catalogs.spell"], "catalogs.spell IS implemented as of Phase 4")
        T.assert_nil(set["objectives"], "objectives is NOT implemented and must not be claimed")
    end)
end

--- The surface is shared state every plugin reads; it is not a scratchpad.
function M.test_the_surface_is_read_only()
    with_clean_globals(function()
        Api.publish(make_kernel())
        local ok = pcall(function() _G.Sentinel.control = "hijacked" end)
        T.assert_false(ok, "assigning to the API surface must fail loudly")
    end)
end

-- ---------------------------------------------------------------------------
-- The host seam (Phase 4)
-- ---------------------------------------------------------------------------
-- Publication has to reconcile two surfaces, and the honest split is by OWNERSHIP, not by age.
-- The kernel owns components (control, state, events, intents). It cannot own `reload` or
-- `questing`, because it does not build the app -- `main.lua` does, and it is the only thing that
-- can tear one down and stand a new one up. So the host CONTRIBUTES verbs to the surface.
--
-- That is a permanent seam, not a compatibility shim. What genuinely was dead got deleted rather
-- than carried: `get_event_bus` and `get_blackboard` had zero callers and duplicated
-- `Sentinel.events` / `Sentinel.state`.

local function host_stub()
    local calls = {}
    return calls, {
        combat = function() calls[#calls + 1] = "combat" return "combat-module" end,
        questing = function() calls[#calls + 1] = "questing" return "questing-module" end,
        reload = function() calls[#calls + 1] = "reload" return true end,
        toggle_quest_editor = function() return false end,
    }
end

--- HANDOFF.md's restart snippet is `_G.Sentinel.questing()`. If publication breaks that, the phase
--- has destroyed its own verification path.
function M.test_host_verbs_survive_publication()
    with_clean_globals(function()
        local calls, host = host_stub()
        local kernel = make_kernel()
        kernel.host = host
        Api.publish(kernel)

        T.assert_equal(_G.Sentinel.questing(), "questing-module")
        T.assert_equal(_G.Sentinel.combat(), "combat-module")
        T.assert_true(_G.Sentinel.reload())
        T.assert_equal(calls[1], "questing")
        T.assert_true(_G.Sentinel.control == kernel.broker,
            "and the kernel surface still resolves alongside them")
    end)
end

--- `main.lua:153` and `:201` did `_G.Sentinel.app = app`. That assignment cannot survive contact
--- with a read-only surface, so `app` becomes a live getter -- strictly better, because it resolves
--- whether read before or after the app is built.
function M.test_app_resolves_through_a_live_getter_rather_than_assignment()
    with_clean_globals(function()
        local kernel = make_kernel()
        local surface = Api.build(kernel)

        T.assert_nil(surface.app, "no app yet")
        kernel.app = { marker = "the-app" }
        T.assert_true(surface.app == kernel.app,
            "app must resolve at access time, not be captured at publish time")

        local ok = pcall(function() surface.app = "hijacked" end)
        T.assert_false(ok, "and assigning it must still fail loudly")
    end)
end

--- A host verb silently overwriting a kernel field would shadow the new surface for every plugin
--- that reads it -- the exact failure the read-only guard exists to prevent.
function M.test_a_host_verb_that_shadows_a_kernel_field_is_refused()
    with_clean_globals(function()
        local kernel = make_kernel()
        kernel.host = { control = function() return "shadowed" end }
        local ok, err = pcall(Api.build, kernel)
        T.assert_false(ok, "a colliding host verb must fail at build time")
        T.assert_true(tostring(err):find("control") ~= nil, "and must name the collision")
    end)
end

--- Deleted, not carried. Both duplicated a kernel field and had no callers; keeping them would mean
--- two ways to reach the same object, which is how the surfaces drift apart again.
function M.test_the_dead_duplicate_accessors_are_gone()
    with_clean_globals(function()
        local _, host = host_stub()
        local kernel = make_kernel()
        kernel.host = host
        Api.publish(kernel)

        T.assert_nil(_G.Sentinel.get_event_bus, "superseded by Sentinel.events")
        T.assert_nil(_G.Sentinel.get_blackboard, "superseded by Sentinel.state")
        T.assert_true(_G.Sentinel.events == kernel.event_bus)
        T.assert_true(_G.Sentinel.state == kernel.blackboard)
    end)
end

-- ---------------------------------------------------------------------------
-- THE EXIT CRITERION: either load order
-- ---------------------------------------------------------------------------

--- KERNEL FIRST, then the plugin. The plugin calls `Sentinel.register` directly.
function M.test_a_plugin_registers_when_the_kernel_loads_first()
    with_clean_globals(function()
        local kernel = make_kernel()
        Api.publish(kernel)

        -- The plugin loads now and sees a live API.
        T.assert_true(_G.Sentinel.register(Fixture.target_strategy()))
        T.assert_true(_G.Sentinel.register(Fixture.new().manifest))

        kernel.registry:resolve()
        T.assert_equal(kernel.registry:state("sentinel.rotation.awkward"), S.LOADED)
    end)
end

--- PLUGIN FIRST, before `_G.Sentinel` exists at all. It pushes onto the pending queue, which the
--- kernel drains on publish.
function M.test_a_plugin_registers_when_it_loads_before_the_kernel()
    with_clean_globals(function()
        -- No _G.Sentinel yet. This is what a plugin's own main.lua does.
        Api.enqueue(Fixture.target_strategy())
        Api.enqueue(Fixture.new().manifest)
        T.assert_nil(_G.Sentinel, "precondition: the kernel has not published yet")

        local kernel = make_kernel()
        local _, drain = Api.publish(kernel)

        T.assert_equal(drain.drained, 2)
        T.assert_equal(drain.registered, 2)
        kernel.registry:resolve()
        T.assert_equal(kernel.registry:state("sentinel.rotation.awkward"), S.LOADED,
            "a plugin that loaded BEFORE the kernel must still end up loaded")
    end)
end

--- Both orders must reach the same end state, or "which order did the injector pick" becomes a
--- behavioural variable.
function M.test_both_load_orders_reach_the_same_state()
    local function kernel_first()
        local kernel = make_kernel()
        Api.publish(kernel)
        _G.Sentinel.register(Fixture.target_strategy())
        _G.Sentinel.register(Fixture.new().manifest)
        kernel.registry:resolve()
        return kernel.registry:order()
    end
    local function plugin_first()
        Api.enqueue(Fixture.target_strategy())
        Api.enqueue(Fixture.new().manifest)
        local kernel = make_kernel()
        Api.publish(kernel)
        kernel.registry:resolve()
        return kernel.registry:order()
    end

    local a, b
    with_clean_globals(function() a = kernel_first() end)
    with_clean_globals(function() b = plugin_first() end)

    T.assert_equal(#a, #b)
    for i = 1, #a do
        T.assert_equal(b[i], a[i], "load order must not depend on which side initialised first")
    end
end

--- `register` before the kernel exists must QUEUE rather than fail, since a plugin has no way to
--- know whether it won the race.
function M.test_register_before_publish_queues_instead_of_failing()
    with_clean_globals(function()
        local surface = Api.build({ registry = nil })
        local ok, reason = surface.register(Fixture.target_strategy())
        T.assert_false(ok)
        T.assert_equal(reason, "queued")
        T.assert_equal(#_G[Api.PENDING_GLOBAL], 1)
    end)
end

-- ---------------------------------------------------------------------------
-- Double registration -- "the obvious bug in this pattern"
-- ---------------------------------------------------------------------------

--- The queue is re-drained for the first ~60 ticks. An entry drained on publish and drained AGAIN
--- by the re-drain must not register twice.
function M.test_queue_drain_plus_re_drain_does_not_double_register()
    with_clean_globals(function()
        Api.enqueue(Fixture.target_strategy())
        local kernel = make_kernel()
        local _, drain = Api.publish(kernel)
        T.assert_equal(drain.registered, 1)

        -- Re-drain across the whole window.
        for tick = 1, Api.PENDING_DRAIN_TICKS do
            local report = Api.tick_pending(kernel, tick)
            if report then
                T.assert_equal(report.registered, 0,
                    "tick " .. tick .. " must not re-register an already-drained manifest")
            end
        end

        kernel.registry:resolve()
        T.assert_equal(#kernel.registry:order(), 1, "exactly one registration must have happened")
    end)
end

--- The second guard: a plugin that pushes the SAME manifest twice itself. Queue removal cannot
--- catch this -- both entries are legitimately in the queue -- so the registry's duplicate-id
--- refusal has to.
function M.test_a_manifest_enqueued_twice_registers_once_and_is_refused_by_name()
    with_clean_globals(function()
        local manifest = Fixture.target_strategy()
        Api.enqueue(manifest)
        Api.enqueue(manifest)

        local kernel = make_kernel()
        local _, drain = Api.publish(kernel)

        T.assert_equal(drain.drained, 2, "both entries must be consumed")
        T.assert_equal(drain.registered, 1, "but only one may register")
        T.assert_equal(#drain.refused, 1)
        T.assert_equal(drain.refused[1].reason, "duplicate_id")
    end)
end

--- Registering the same id through the LIVE path after it arrived via the queue must also be
--- refused -- the two routes must not each get a slot.
function M.test_live_registration_after_a_queued_one_is_refused()
    with_clean_globals(function()
        Api.enqueue(Fixture.target_strategy())
        local kernel = make_kernel()
        Api.publish(kernel)

        local ok, reason = _G.Sentinel.register(Fixture.target_strategy())
        T.assert_false(ok)
        T.assert_equal(reason, "duplicate_id")
    end)
end

--- The queue must be emptied, not just read: a growing queue would be re-scanned every tick for
--- the whole window.
function M.test_draining_empties_the_queue()
    with_clean_globals(function()
        Api.enqueue(Fixture.target_strategy())
        local kernel = make_kernel()
        Api.publish(kernel)
        T.assert_equal(#_G[Api.PENDING_GLOBAL], 0)
    end)
end

--- A plugin that loads LATE -- after publish but inside the window -- must still get in. That is
--- the reason the re-drain exists at all.
function M.test_a_late_arrival_inside_the_window_is_still_registered()
    with_clean_globals(function()
        local kernel = make_kernel()
        Api.publish(kernel)

        Api.enqueue(Fixture.target_strategy()) -- pushed at tick 5, after publish
        local report = Api.tick_pending(kernel, 5)

        T.assert_not_nil(report)
        T.assert_equal(report.registered, 1)
        T.assert_equal(kernel.registry:state("sentinel.strategy.dummy_targeting"), S.VALIDATED)
    end)
end

--- ...and the window closes, or the kernel scans a global forever.
function M.test_the_drain_window_closes()
    with_clean_globals(function()
        local kernel = make_kernel()
        Api.publish(kernel)
        Api.enqueue(Fixture.target_strategy())
        T.assert_nil(Api.tick_pending(kernel, Api.PENDING_DRAIN_TICKS + 1),
            "past the window the kernel must stop draining")
    end)
end

function M.test_a_malformed_queue_entry_is_refused_by_name_not_fatal()
    with_clean_globals(function()
        Api.enqueue("not a manifest")
        local kernel = make_kernel()
        local ok, result = pcall(function() return select(2, Api.publish(kernel)) end)
        T.assert_true(ok, "garbage in the queue must not break publication")
        T.assert_equal(result.registered, 0)
        T.assert_equal(#result.refused, 1)
        T.assert_equal(result.refused[1].id, "<malformed>")
    end)
end

-- ---------------------------------------------------------------------------
-- Config: menu ID allocation (ADR 08 §5.1 / §2.3)
-- ---------------------------------------------------------------------------

function M.test_menu_ids_are_namespaced_and_stable()
    local config = Config:new()
    local first = config:allocate_menu_id("sentinel.rotation.awkward", "blink_threshold")
    T.assert_not_nil(first)
    T.assert_true(first:find("^sentinel_") ~= nil, "IDs must carry the Sentinel prefix: " .. first)
    T.assert_equal(config:allocate_menu_id("sentinel.rotation.awkward", "blink_threshold"), first,
        "the same owner must get the same ID across reloads")
end

--- Menu IDs share ONE namespace across every Sylvanas plugin (§2.3), so a collision is a real
--- failure and must be reported rather than silently shared.
function M.test_a_menu_id_collision_between_owners_is_refused()
    local config = Config:new()
    config:allocate_menu_id("plugin.a", "shared_key")
    -- Distinct owners whose folded IDs coincide: "a.b"/"c" and "a_b"/"c" both fold to
    -- sentinel_a_b_c.
    config:allocate_menu_id("a.b", "c")
    local id, reason = config:allocate_menu_id("a_b", "c")
    T.assert_nil(id, "a second owner must not be handed an ID already in use")
    T.assert_true(tostring(reason):find("menu_id_collision", 1, true) ~= nil, tostring(reason))
end

function M.test_config_set_validates_against_the_declared_schema()
    local config = Config:new()
    config:declare("p", Fixture.new().manifest.config)

    T.assert_true(config:set("p", "blink_threshold", 50))
    T.assert_equal(config:get("p", "blink_threshold"), 50)

    local ok, reason = config:set("p", "blink_threshold", 500)
    T.assert_false(ok, "above the declared max")
    T.assert_equal(reason, "above_max:blink_threshold")

    local ok2, reason2 = config:set("p", "blink_threshold", "fifty")
    T.assert_false(ok2)
    T.assert_equal(reason2, "type_mismatch:blink_threshold")

    local ok3, reason3 = config:set("p", "stance", "berserk")
    T.assert_false(ok3, "not one of the enum values")
    T.assert_equal(reason3, "not_in_enum:stance")

    local ok4, reason4 = config:set("p", "no_such_key", 1)
    T.assert_false(ok4)
    T.assert_equal(reason4, "unknown_key:no_such_key")
end

function M.test_an_int_config_rejects_a_fractional_value()
    local config = Config:new()
    config:declare("p", Fixture.new().manifest.config)
    local ok, reason = config:set("p", "blink_threshold", 12.5)
    T.assert_false(ok)
    T.assert_equal(reason, "type_mismatch:blink_threshold")
    T.assert_true(config:set("p", "leash_yards", 12.5), "but a float accepts one")
end

--- Persisted values override defaults, but only where they still validate: a stored value whose
--- schema later changed shape must not resurrect as a type error.
function M.test_persisted_values_override_defaults_but_only_if_still_valid()
    local store = { ["p"] = { blink_threshold = 70, stance = "berserk" } }
    local config = Config:new({ persist = {
        load = function(ns) return store[ns] end,
        save = function(ns, values) store[ns] = values end,
    } })
    config:declare("p", Fixture.new().manifest.config)

    T.assert_equal(config:get("p", "blink_threshold"), 70, "a valid stored value must be restored")
    T.assert_equal(config:get("p", "stance"), "objective",
        "a stored value that no longer validates must fall back to the default")
end

return M
