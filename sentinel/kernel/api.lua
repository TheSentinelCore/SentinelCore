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
    ["intents"] = true,     -- IntentQueue
    ["activities"] = true,  -- ActivityStack
    ["config"] = true,      -- Config
    ["bands"] = true,       -- band arithmetic
    ["nav"] = true,         -- NavAdapter, via the app
    ["bt"] = true,          -- behaviour-tree library
    ["rotation"] = true,    -- PriorityBuilder, the Tier-1 rotation DSL (§5.4)
    ["timing.gcd"] = true,  -- kernel/timing.lua: gcd_duration_ms, gcd_remaining_est (§2.5)
    ["units"] = true,       -- kernel/units.lua: player, target, hostiles_within
    ["spells"] = true,      -- kernel/spells.lua: is_castable, is_in_los, find_aoe_position
    ["catalogs.aura"] = true,  -- kernel/catalogs/aura.lua
    ["catalogs.spell"] = true, -- kernel/catalogs/spell.lua: rank resolution by level
    -- `log` was listed here from Phase 3 while the surface had NO `log` field, so a manifest
    -- requiring it was admitted and then failed at first use -- the exact failure this list
    -- exists to prevent. kernel/log.lua closed that in Phase 4b.
    ["log"] = true,
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
        -- Libraries, not kernel instances: stateless, constructed by the plugin, identical for
        -- every caller. They are static because there is nothing per-app to resolve at access time.
        rotation = PriorityBuilder,
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
        scheduler = function() return kernel.scheduler end,
        nav = function() return kernel.nav end,
        plugins = function() return kernel.registry end,
        snapshot = function()
            local scheduler = kernel.scheduler
            return scheduler and scheduler.current_snapshot and scheduler:current_snapshot() or nil
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
