-- kernel/api.lua
-- `_G.Sentinel` -- the public surface, published behind a live-getter metatable.
--
-- ================================================================================
-- THE LOAD-ORDER PROBLEM, AND WHY IT TAKES TWO MECHANISMS
-- ================================================================================
-- ADR 08 §2.3: the injector documents no plugin load order and plugin A cannot `require` plugin B,
-- so `_G` is the only handshake. §2.4 confirms `_G` is shared and points at the pattern already
-- proven in this repo -- `SentinelNavClient/main.lua:106` wraps its export in a metatable whose
-- `__index` makes `.client` a LIVE GETTER, so it resolves whether read before or after `on_load`.
--
-- §2.4's conclusion, adopted here verbatim: "Keep the deferred `__SentinelPending` queue as well --
-- THE GETTER FIXES READS, THE QUEUE FIXES REGISTRATION."
--
-- Those are genuinely different problems:
--   * A plugin that READS `Sentinel.control` before the kernel initialised needs the getter, which
--     resolves the field at access time instead of capturing nil at publish time.
--   * A plugin that REGISTERS before the kernel exists has nowhere to put its manifest. It pushes
--     onto `_G.__SentinelPending`, which the kernel drains on init and RE-DRAINS for the first ~60
--     ticks -- because a plugin loaded after us may push later in the same session.
--
-- The obvious bug in that pattern is DOUBLE REGISTRATION: an entry that is drained, then drained
-- again by the re-drain, registers twice. Guarded on both sides -- entries are removed from the
-- queue as they are consumed, AND the registry refuses a duplicate id -- because either alone
-- fails for a plugin that pushes the same manifest twice itself.
--
-- ================================================================================
-- THE SURFACE IS WHAT PHASE 1-3 ACTUALLY IMPLEMENTS
-- ================================================================================
-- ADR §10 lists the full eventual API. Most of it does not exist yet: `catalogs`, `timing`,
-- `objectives`, `facts`, `units` and `persist` are Phase 5+ services. They are NOT stubbed here.
-- A field that exists and returns nil fails at the CALL SITE, arbitrarily far from the cause; an
-- absent field fails at lookup, where the diagnostic is obvious. So `Sentinel.timing` is nil today
-- and `Sentinel.available()` enumerates what is real.

local Bands = require("kernel/bands")
local Status = require("kernel/status")
local ControlBroker = require("kernel/control_broker")
local PriorityBuilder = require("kernel/lib/priority_builder")
local BTFactory = require("core/bt/factory")
local BTStatus = require("core/bt/status")
local BTRunner = require("core/bt/runner")
local AuraCatalog = require("kernel/catalogs/aura")
-- `kernel/cond/init` spelled out: the Sylvannas `package.path` has no `?/init.lua` entry, so
-- `require("kernel/cond")` resolves to a `kernel/cond.lua` that does not exist.
local Cond = require("kernel/cond/init")
local Truth = require("kernel/truth")
local Log = require("kernel/log")

local Api = {}

--- ADR §10. Bumped when the published surface changes incompatibly; manifests gate on it via
--- `api = "^1.0"`.
Api.API_VERSION = "1.0.0"

--- Capabilities the KERNEL satisfies, i.e. what a manifest's `requires` may name without another
--- plugin providing it. Honest about what is built: `catalogs.spell` from ADR §8.2's sample manifest
--- is still absent, because that service does not exist yet and claiming it would admit plugins that
--- then fail at first use. `timing.gcd` joined the list in Phase 4, when the frost port needed
--- `gcd_remaining_est` and the service was built instead of worked around.
Api.KERNEL_CAPABILITIES = {
    ["control"] = true,     -- ControlBroker: channels, leases, revocation
    ["state"] = true,       -- Blackboard
    ["snapshot"] = true,    -- frozen per-tick snapshot
    ["events"] = true,      -- EventBus
    -- `intent`, SINGULAR, matching the field ADR §10 names (`Sentinel.intent`). It was `intents`
    -- for three phases -- a capability a manifest could require and then find nothing under, since
    -- `Sentinel.intents` has never existed. Renamed rather than aliased: two spellings for one
    -- service is how the next reader learns the wrong one.
    ["intent"] = true,      -- IntentQueue
    ["activities"] = true,  -- ActivityStack
    ["config"] = true,      -- Config
    -- The band ARITHMETIC (`permits`, `resolve`, `name_for`, `spell_queue_priority`), not just the
    -- `Band` enum. Only the enum was ever published, so a plugin admitted on this capability could
    -- read the band table and had no way to turn its manifest priority into an intent's `band`
    -- number -- which is precisely what emitting an intent requires.
    ["bands"] = true,       -- band arithmetic
    ["nav"] = true,         -- NavAdapter, via the app
    ["bt"] = true,          -- behaviour-tree library
    ["rotation"] = true,    -- PriorityBuilder, the Tier-1 rotation DSL (§5.4)
    ["timing.gcd"] = true,  -- kernel/timing.lua: gcd_duration_ms, gcd_remaining_est (§2.5)
    ["units"] = true,       -- kernel/units.lua: player, target, hostiles_within
    ["spells"] = true,      -- kernel/spells.lua: is_castable, is_in_los, find_aoe_position
    -- `forecast` joined in Phase 4d D1, when the IZI bridge stopped being a blackboard key. Six
    -- readers needed it and four of them are handed only a blackboard, so a service was the only
    -- route that reached them all -- see kernel/forecast.lua's header.
    ["forecast"] = true,    -- kernel/forecast.lua: time to die, predicted HP, incoming damage
    ["catalogs.aura"] = true,  -- kernel/catalogs/aura.lua
    ["catalogs.spell"] = true, -- kernel/catalogs/spell.lua: rank resolution by level
    -- `log` was listed here from Phase 3 while the surface had NO `log` field, so a manifest
    -- requiring it was admitted and then failed at first use -- the exact failure this list
    -- exists to prevent. kernel/log.lua closed that in Phase 4b.
    ["log"] = true,
    -- kernel/cond: 17 snapshot predicates answering in `Truth`. Claimed only now that it is
    -- REACHABLE -- it existed for a whole phase with no field behind it, which is the same shape
    -- as the `log` and `snapshot` defects, arrived at from the other side: unclaimed AND unusable
    -- rather than claimed and absent.
    ["cond"] = true,
}

--- WHERE each capability actually lives on the surface, and what must be callable there.
---
--- `KERNEL_CAPABILITIES` alone is free text: a name on it is checked against nothing, which is how
--- `log` shipped for a whole phase with no field behind it and how `snapshot` resolved through a
--- method that existed nowhere. This table turns each claim into an assertion
--- (`tests/kernel/test_capability_resolution.lua` enforces it), so a capability cannot be added
--- without naming the thing that satisfies it.
---
--- `path` is walked from the surface root, so a dotted capability whose name IS a path -- like
--- `catalogs.aura` -- says so, and one whose name is a FEATURE of a service -- like `timing.gcd`,
--- which is not a field but two functions on `timing` -- names the service and the functions.
---
--- ================================================================================
--- WHAT THIS TABLE CANNOT SEE: IT IS A ONE-WAY CHECK
--- ================================================================================
--- It catches OVER-claiming -- a capability naming a member that does not exist. It cannot catch
--- UNDER-declaring: a member that exists on the surface and is named by no binding.
---
--- A plugin discovers what it may call from its manifest's `requires` and from this table, so a
--- verb that works but is undeclared is one a careful plugin author will never find, and one a
--- careless one will depend on without ever having been admitted for it. Recorded rather than
--- fixed, because the closing assertion belongs in the capability-resolution suite that owns the
--- other direction.
Api.CAPABILITY_BINDINGS = {
    ["control"] = { path = { "control" },
        members = { "acquire", "release", "delegate", "who_owns" } },
    ["state"] = { path = { "state" }, members = { "get", "set", "has", "clear" } },
    ["snapshot"] = { path = { "snapshot" },
        members = { "get", "has", "keys", "tick_index", "is_frozen" } },
    ["events"] = { path = { "events" }, members = { "subscribe", "unsubscribe", "publish" } },
    ["intent"] = { path = { "intent" }, members = { "submit", "pending_count" } },
    ["activities"] = { path = { "activities" },
        members = { "push", "pop", "current", "depth", "delegate" } },
    ["config"] = { path = { "config" }, members = { "get", "set", "declare" } },
    ["bands"] = { path = { "bands" },
        members = { "permits", "resolve", "name_for", "spell_queue_priority" } },
    ["nav"] = { path = { "nav" }, members = { "move_to", "follow_path", "stop", "poll" } },
    ["bt"] = { path = { "bt" },
        members = { "sequence", "selector", "priority_selector", "condition", "action" } },
    ["rotation"] = { path = { "rotation" }, members = { "new" } },
    ["timing.gcd"] = { path = { "timing" },
        members = { "gcd_duration_ms", "gcd_remaining_est", "is_gcd_ready" } },
    ["units"] = { path = { "units" },
        members = { "player", "target", "hostiles_within" } },
    ["spells"] = { path = { "spells" },
        members = { "is_castable", "is_in_los", "find_aoe_position" } },
    -- `is_available` is named alongside the four answers deliberately. Every accessor returns nil
    -- when it cannot say, so without a way to ask WHY, a plugin cannot tell "the target has no
    -- time-to-die estimate yet" from "the IZI SDK is not loaded" (ADR 08 §9.3). A binding that
    -- promised the answers and not the availability check would ship a service whose nils are
    -- uninterpretable.
    ["forecast"] = { path = { "forecast" },
        members = { "is_available", "time_to_die", "predicted_health_pct",
                    "incoming_damage_pct", "fight_seconds_remaining" } },
    ["catalogs.aura"] = { path = { "catalogs", "aura" }, members = { "has_any", "get_stacks" } },
    ["catalogs.spell"] = { path = { "catalogs", "spell" },
        members = { "resolve_best_rank", "is_gcd_spell" } },
    ["log"] = { path = { "log" }, members = { "debug", "info", "warn", "error" } },
    ["cond"] = { path = { "cond" }, members = { "bind" } },
}

--- How many ticks to keep re-draining the pending queue after init (§10: "re-drained for the first
--- ~60 ticks"). A plugin the injector loads after us can push at any point during startup.
Api.PENDING_DRAIN_TICKS = 60

Api.PENDING_GLOBAL = "__SentinelPending"

-- ---------------------------------------------------------------------------
-- Publication
-- ---------------------------------------------------------------------------

---Build the `_G.Sentinel` table.
---
---Every dynamic field resolves through `__index` AT ACCESS TIME, so a reference captured before the
---kernel finished initialising still returns the live component -- the §2.4 pattern.
---@param kernel table { app, registry, config, broker, activity_stack, intent_queue, blackboard,
---                      event_bus, scheduler, nav }
---@return table the published surface
function Api.build(kernel)
    kernel = kernel or {}

    -- Static values: safe to place directly, since they never change after load.
    local surface = {
        API_VERSION = Api.API_VERSION,
        Status = Status,
        Channel = ControlBroker.Channel,
        Band = Bands.BANDS,
        -- The tri-state, published WITH `cond` because it is unusable without it. Predicates answer
        -- in Truth values, and a plugin may not `require("kernel/truth")` -- the require audit
        -- forbids reaching into the kernel -- so without this field it could call a predicate and
        -- then have no way to name `Truth.True` or to reach `Truth.resolve`, which is what turns a
        -- tri-state into the boolean a BT condition has to return.
        Truth = Truth,
        -- Libraries, not kernel instances: stateless, constructed by the plugin, identical for
        -- every caller. They are static because there is nothing per-app to resolve at access time.
        rotation = PriorityBuilder,
        -- Band ARITHMETIC. `Band` above is the enum -- the six named ranges. This is the module that
        -- operates on them: `resolve` turns a manifest's `{ band, offset }` into the integer an
        -- intent carries, `permits` answers whether a tier may claim a band at all, and
        -- `spell_queue_priority` maps a band onto the injector's own queue. Publishing the enum
        -- without them satisfied nobody: a plugin cannot emit an intent without computing a band.
        bands = Bands,
        -- Condition predicates: frozen snapshot in, `Truth` out. A LIBRARY, like `bt` and
        -- `rotation` -- stateless, bound per tick by the caller against the snapshot it is reading.
        --
        -- It was built in Phase 4b and published by nobody. ADR §13.1 item 18 blamed the truthiness
        -- lint's seed for not recognising `require("kernel/cond")` consumers; the deeper reason the
        -- lint measured zero is that there were no consumers of EITHER form, because `Sentinel.cond`
        -- did not exist as a field. Seventeen predicates, a test suite, and no route to a plugin.
        cond = Cond,
        -- The behaviour-tree library (§10 `Sentinel.bt`). A rotation composing subtrees needs the
        -- node constructors AND the status enum -- returning the factory alone would force every
        -- plugin to invent its own SUCCESS/FAILURE strings, which is how two trees stop agreeing on
        -- what "done" means.
        -- `Runner` rides along because a rotation does not merely BUILD a tree, it has to TICK one,
        -- and the frost profile wraps each of its three trees in a Runner. Handing over node
        -- constructors without the thing that drives them would force every plugin to reimplement
        -- the tick loop, including its RUNNING semantics.
        bt = setmetatable({ Status = BTStatus, Runner = BTRunner }, { __index = BTFactory }),
        -- Catalogs: shared reference data (§5.1 -- "duplicating it costs memory and drifts").
        --
        -- `aura` is a stateless module, so it sits here directly. `spell` is a per-app INSTANCE
        -- (it caches rank resolution against the live spell book), so it resolves through the
        -- kernel table at access time -- one catalog for every plugin, which is the whole point:
        -- a rotation carrying its own rank table would duplicate DB-baked data per class.
        -- ADR §10: `:debug, :info, :warn, :error (auto-attributed)`. A single shared instance,
        -- not one per plugin: attribution is derived from the CALL SITE, so per-plugin loggers
        -- would carry a name that could disagree with where the call actually came from.
        log = Log.new(),
        catalogs = setmetatable({ aura = AuraCatalog }, {
            __index = function(_, key)
                if key == "spell" then return kernel.spell_catalog end
                return nil
            end,
        }),
    }

    -- Live getters. Each is a function of the kernel table rather than a captured value.
    local live = {
        -- The app itself, for the in-game debug console. A GETTER, not a field: `main.lua` used to
        -- assign `_G.Sentinel.app = app` after init, which a read-only surface cannot accept, and
        -- resolving at access time is what makes the assignment unnecessary in the first place.
        app = function() return kernel.app end,
        control = function() return kernel.broker end,
        activities = function() return kernel.activity_stack end,
        state = function() return kernel.blackboard end,
        events = function() return kernel.event_bus end,
        intent = function() return kernel.intent_queue end,
        config = function() return kernel.config end,
        timing = function() return kernel.timing end,
        units = function() return kernel.units end,
        spells = function() return kernel.spells end,
        -- A GETTER, not a captured value, for the same reason as every other per-app instance: the
        -- surface is built in `SentinelApp:new()` and published later still, and a plugin that took
        -- a reference before either would otherwise hold nil forever (§2.4).
        forecast = function() return kernel.forecast end,
        scheduler = function() return kernel.scheduler end,
        nav = function() return kernel.nav end,
        plugins = function() return kernel.registry end,
        -- ADR 08 §13.1 item 14. This used to read
        -- `scheduler and scheduler.current_snapshot and scheduler:current_snapshot() or nil`, and
        -- `Scheduler` had no such method -- so the middle term made a MISSING SERVICE indistinguishable
        -- from an absent scheduler, and the capability list claimed it worked for three phases.
        -- The feature test is gone on purpose: an absent scheduler is a real state (pre-init) and
        -- returns nil, but a scheduler that cannot answer is a defect and must raise where it is.
        snapshot = function()
            local scheduler = kernel.scheduler
            if scheduler == nil then return nil end
            return scheduler:current_snapshot()
        end,
    }

    surface.register = function(manifest)
        local registry = kernel.registry
        if registry == nil then
            -- The kernel is not up yet, so queue instead of failing. This is the registration half
            -- of the load-order problem.
            Api.enqueue(manifest)
            return false, "queued"
        end
        return registry:discover(manifest)
    end

    --- What is actually available, so a plugin can degrade rather than guess.
    surface.available = function()
        local out = {}
        for capability in pairs(Api.KERNEL_CAPABILITIES) do out[#out + 1] = capability end
        table.sort(out)
        return out
    end

    -- Host verbs. The kernel owns components; it does not own `reload` or `questing`, because it
    -- does not build the app -- `main.lua` does, and only the host can tear one down and stand a new
    -- one up. So the host contributes those verbs here rather than the kernel guessing at them.
    --
    -- A collision is refused rather than resolved. Silently letting a host verb win would shadow a
    -- kernel field for every plugin that reads the surface, which is the same failure the read-only
    -- guard exists to prevent -- just arriving through the front door.
    for name, fn in pairs(kernel.host or {}) do
        if surface[name] ~= nil or live[name] ~= nil then
            error("Sentinel API: host verb '" .. tostring(name) .. "' collides with a kernel field", 2)
        end
        surface[name] = fn
    end

    return setmetatable(surface, {
        __index = function(_, key)
            local getter = live[key]
            if getter then return getter() end
            -- Deliberately nil for anything not implemented: an absent field fails at lookup,
            -- where the cause is visible.
            return nil
        end,
        -- The surface is not a scratchpad. A plugin writing to `_G.Sentinel` would be mutating
        -- shared state every other plugin reads.
        __newindex = function(_, key)
            error("Sentinel API is read-only: cannot assign '" .. tostring(key) .. "'", 2)
        end,
        __metatable = false,
    })
end

---Push a manifest onto the deferred queue. Safe before the kernel exists.
function Api.enqueue(manifest)
    _G[Api.PENDING_GLOBAL] = _G[Api.PENDING_GLOBAL] or {}
    table.insert(_G[Api.PENDING_GLOBAL], manifest)
    return true
end

---Drain the deferred queue into the registry.
---
---Entries are REMOVED as they are consumed, which is the first of the two double-registration
---guards; the registry's duplicate-id refusal is the second. Both are needed: removal alone does
---not stop a plugin that pushes the same manifest twice, and duplicate-id alone would leave the
---queue growing forever.
---@return table report { drained, registered, refused = { {id, reason} } }
function Api.drain_pending(registry)
    local report = { drained = 0, registered = 0, refused = {} }
    local queue = _G[Api.PENDING_GLOBAL]
    if type(queue) ~= "table" or registry == nil then return report end

    while #queue > 0 do
        local manifest = table.remove(queue, 1)
        report.drained = report.drained + 1
        local ok, reason = registry:discover(manifest)
        if ok then
            report.registered = report.registered + 1
        else
            report.refused[#report.refused + 1] = {
                id = type(manifest) == "table" and manifest.id or "<malformed>",
                reason = reason,
            }
        end
    end
    return report
end

---Publish the surface at `_G.Sentinel` and drain whatever was waiting.
---@return table surface, table drain_report
function Api.publish(kernel)
    local surface = Api.build(kernel)
    _G.Sentinel = surface
    local drain = Api.drain_pending(kernel.registry)
    return surface, drain
end

---Re-drain, for the first `PENDING_DRAIN_TICKS` ticks.
---@return table|nil report nil once the window has closed
function Api.tick_pending(kernel, tick_index)
    if tick_index == nil or tick_index > Api.PENDING_DRAIN_TICKS then
        return nil
    end
    local queue = _G[Api.PENDING_GLOBAL]
    if type(queue) ~= "table" or #queue == 0 then return nil end
    return Api.drain_pending(kernel.registry)
end

return Api
