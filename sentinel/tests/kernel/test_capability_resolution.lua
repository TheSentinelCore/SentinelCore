-- tests/kernel/test_capability_resolution.lua
-- Every capability the kernel CLAIMS must resolve to something callable on the surface it PUBLISHES.
--
-- ================================================================================
-- WHY THIS EXISTS: THE CAPABILITY LIE IS A CLASS, NOT A BUG
-- ================================================================================
-- `Api.KERNEL_CAPABILITIES` is the list a manifest's `requires` is checked against. A name on that
-- list is a promise that a plugin admitted on its strength can then USE the thing. Twice now the
-- promise was empty:
--
--   * `log` was listed from Phase 3 while the surface had no `log` field at all. A manifest
--     requiring it was admitted and failed at first use (kernel/log.lua's own header records this).
--   * `snapshot` was listed while `api.lua` resolved it through
--     `scheduler.current_snapshot and scheduler:current_snapshot()` -- an identifier that appeared
--     exactly once in the repository, on that line. `Scheduler` had no such method, and the `and`
--     chain turned the miss into a SILENT nil (ADR 08 §13.1 item 14).
--
-- Two independent instances of one shape is a class. So the list stops being free text: every
-- capability now declares, in `Api.CAPABILITY_BINDINGS`, the path on the surface that satisfies it
-- and the members that must be callable there. This file enforces that the declaration is true.
--
-- ================================================================================
-- WHAT THIS CHECK CANNOT SEE
-- ================================================================================
-- Stated up front, because two of the three defects this repo found in Phase 4b were checks that
-- were right about what they saw and wrong about what they looked at.
--
--  1. A FIELD THAT EXISTS AND RETURNS nil FOR OTHER REASONS. The check resolves each binding against
--     the compositions built HERE (a fully-wired kernel table, and a real `SentinelApp`). A live
--     getter reads `kernel.<component>` at access time; a DIFFERENT composition that omits that
--     component still yields nil and this file never sees it. `tests/run_offline.lua` builds exactly
--     such a partial surface on purpose -- `Sentinel.control` is nil for every plugin test in the
--     suite -- and that is invisible here.
--  2. WHETHER A MEMBER DOES WHAT ITS NAME SAYS. `type(v) == "function"` is the whole test. A member
--     that exists and always returns nil, throws, or no-ops passes. MEASURED, not assumed: deleting
--     `self._snapshot = frozen` from `Scheduler:tick()` kills six tests in test_scheduler.lua and
--     test_api.lua and this file does not notice, because the seeded empty snapshot still resolves
--     and still carries all five members. Resolvability is not freshness. The tests that pin
--     BEHAVIOUR live next to the behaviour; this file only closes the "claimed but absent" class.
--  3. A BINDING POINTED AT THE WRONG OBJECT. The binding is a claim written by the same hand as the
--     capability. If `nav` were bound to a path that happened to carry the named members, this file
--     would agree. It proves the list is not EMPTY, not that it is CORRECT.
--  4. CAPABILITIES A PLUGIN REQUIRES THAT THE KERNEL NEVER CLAIMED. That refusal is the plugin
--     registry's job (`tests/kernel/test_capabilities.lua`), not this one's.
--  5. ANYTHING ABOUT NON-KERNEL PROVIDERS. A capability supplied by another plugin's `provides`
--     never appears in `KERNEL_CAPABILITIES` and is out of scope by construction.
--
-- The two meta-tests at the bottom exist because of point 3's neighbour: a checker that can never
-- fail is worth nothing. They introduce a capability that resolves nowhere and a member that is
-- absent, and assert the checker reports both.

local Api = require("kernel/api")
local Bands = require("kernel/bands")
local Blackboard = require("core/blackboard")
local ControlBroker = require("kernel/control_broker")
local Config = require("kernel/config")
local EventBus = require("core/event_bus")
local ActivityStack = require("kernel/activity_stack")
local IntentQueue = require("kernel/intent_queue")
local PluginRegistry = require("kernel/plugin_registry")
local Scheduler = require("kernel/scheduler")
local SpellCatalog = require("kernel/catalogs/spell")
local Spells = require("kernel/spells")
local Units = require("kernel/units")
local Forecast = require("kernel/forecast")
local Timing = require("kernel/timing")
local NavAdapter = require("integrations/nav_client/adapter")
local SpellHelper = require("shared/spell_helper")
local AoeHelper = require("shared/aoe_helper")
local SentinelApp = require("runtime/app")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- The checker
-- ---------------------------------------------------------------------------

---Walk a binding's dotted path across the surface.
---@return any value, string|nil missing -- `missing` names the first segment that resolved to nil
local function resolve_path(surface, path)
    local node = surface
    for index = 1, #path do
        if node == nil then
            return nil, table.concat(path, ".", 1, index - 1)
        end
        node = node[path[index]]
    end
    if node == nil then return nil, table.concat(path, ".") end
    return node, nil
end

---@return boolean ok, string|nil reason
local function check_capability(surface, name, binding)
    if binding == nil then
        return false, "capability '" .. name .. "' declares no binding"
    end
    local value, missing = resolve_path(surface, binding.path)
    if value == nil then
        return false, string.format(
            "capability '%s' claims Sentinel.%s, which resolves to nil at '%s'",
            name, table.concat(binding.path, "."), tostring(missing))
    end
    -- A capability may be satisfied by a bare function (none are today, but the shape is legal).
    if type(value) == "function" then return true end
    if type(value) ~= "table" then
        return false, string.format("capability '%s' resolves to a %s, which nothing can be called on",
            name, type(value))
    end
    for _, member in ipairs(binding.members or {}) do
        if type(value[member]) ~= "function" then
            return false, string.format(
                "capability '%s' promises Sentinel.%s:%s(), which is a %s",
                name, table.concat(binding.path, "."), member, type(value[member]))
        end
    end
    return true
end

---@return table failures -- one message per capability that does not hold
local function check_all(surface, capabilities, bindings)
    local failures = {}
    local names = {}
    for name in pairs(capabilities) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, reason = check_capability(surface, name, bindings[name])
        if not ok then failures[#failures + 1] = reason end
    end
    return failures
end

local function assert_no_failures(failures, context)
    if #failures == 0 then return end
    error(context .. ":\n  - " .. table.concat(failures, "\n  - "), 0)
end

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

--- Everything a real app hands `Api.build`. Deliberately NOT a stub surface: a stub would let the
--- capability list pass against a shape the kernel does not have, which is the failure mode.
local function fully_wired_kernel()
    local bus = EventBus:new(function() end)
    local config = Config:new()
    local broker = ControlBroker:new({ event_bus = bus })
    local intent_queue = IntentQueue:new()
    local spell_catalog = SpellCatalog:new()
    return {
        app = { marker = "app" },
        registry = PluginRegistry:new({
            api_version = Api.API_VERSION,
            kernel_provides = Api.KERNEL_CAPABILITIES,
            event_bus = bus,
            config = config,
        }),
        config = config,
        broker = broker,
        activity_stack = ActivityStack:new({ broker = broker, event_bus = bus }),
        intent_queue = intent_queue,
        blackboard = Blackboard:new(),
        event_bus = bus,
        scheduler = Scheduler:new({ event_bus = bus, intent_queue = intent_queue }),
        timing = Timing:new(),
        spell_catalog = spell_catalog,
        units = Units:new(),
        spells = Spells:new({ spell_helper = SpellHelper, spell_prediction = AoeHelper }),
        -- Constructed WITHOUT a bridge, which is the honest offline shape: the IZI SDK is
        -- injector-only. The binding proves the members resolve; whether a live bridge sits behind
        -- them is the app's wiring, pinned in tests/integration/test_kernel_end_to_end.lua.
        forecast = Forecast:new(),
        nav = NavAdapter:new(bus),
    }
end

local function with_saved_globals(fn)
    local saved_surface = _G.Sentinel
    local saved_pending = _G[Api.PENDING_GLOBAL]
    local ok, err = pcall(fn)
    _G.Sentinel = saved_surface
    _G[Api.PENDING_GLOBAL] = saved_pending
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------
-- The declaration must be total
-- ---------------------------------------------------------------------------

function M.test_every_capability_declares_a_binding()
    local missing = {}
    for name in pairs(Api.KERNEL_CAPABILITIES) do
        if Api.CAPABILITY_BINDINGS[name] == nil then missing[#missing + 1] = name end
    end
    table.sort(missing)
    T.assert_equal(#missing, 0,
        "these capabilities are claimed with no binding: " .. table.concat(missing, ", "))
end

--- The other direction. An orphan binding means a capability was renamed or dropped and its
--- declaration was left behind, which would then be checked forever against nothing.
function M.test_every_binding_names_a_declared_capability()
    local orphans = {}
    for name in pairs(Api.CAPABILITY_BINDINGS) do
        if Api.KERNEL_CAPABILITIES[name] == nil then orphans[#orphans + 1] = name end
    end
    table.sort(orphans)
    T.assert_equal(#orphans, 0,
        "these bindings name no declared capability: " .. table.concat(orphans, ", "))
end

function M.test_every_binding_declares_a_path_and_at_least_one_member()
    for name, binding in pairs(Api.CAPABILITY_BINDINGS) do
        T.assert_true(type(binding.path) == "table" and #binding.path > 0,
            "binding '" .. name .. "' must name a surface path")
        T.assert_true(type(binding.members) == "table" and #binding.members > 0,
            "binding '" .. name .. "' must name at least one callable member, or it asserts nothing")
    end
end

-- ---------------------------------------------------------------------------
-- THE POINT: every claim resolves
-- ---------------------------------------------------------------------------

function M.test_every_capability_resolves_on_a_fully_wired_surface()
    with_saved_globals(function()
        local surface = Api.build(fully_wired_kernel())
        assert_no_failures(
            check_all(surface, Api.KERNEL_CAPABILITIES, Api.CAPABILITY_BINDINGS),
            "capabilities claimed by the kernel that do not resolve on the surface it builds")
    end)
end

--- The composition that actually ships. `Api.build` is called in two places -- `SentinelApp:new`
--- and `SentinelApp:publish_api` -- with two separately maintained kernel tables, so a component
--- passed to one and forgotten by the other produces a surface that is complete in tests and
--- holed in production, or the reverse.
function M.test_every_capability_resolves_on_the_surface_the_real_app_builds()
    with_saved_globals(function()
        local app = SentinelApp:new()
        assert_no_failures(
            check_all(app:get_api(), Api.KERNEL_CAPABILITIES, Api.CAPABILITY_BINDINGS),
            "capabilities that do not resolve on SentinelApp:get_api()")
    end)
end

function M.test_every_capability_resolves_on_the_surface_the_real_app_publishes()
    with_saved_globals(function()
        local app = SentinelApp:new()
        app:publish_api()
        assert_no_failures(
            check_all(_G.Sentinel, Api.KERNEL_CAPABILITIES, Api.CAPABILITY_BINDINGS),
            "capabilities that do not resolve on the published _G.Sentinel")
    end)
end

--- `Sentinel.available()` is what a plugin reads to decide whether to degrade. It must enumerate
--- the same set the bindings prove, or a plugin degrades on a capability that works (or trusts one
--- that does not).
function M.test_available_enumerates_exactly_the_bound_capabilities()
    with_saved_globals(function()
        local surface = Api.build(fully_wired_kernel())
        local seen = {}
        for _, name in ipairs(surface.available()) do
            seen[name] = true
            T.assert_not_nil(Api.CAPABILITY_BINDINGS[name],
                "available() offers '" .. name .. "' with no binding behind it")
        end
        for name in pairs(Api.CAPABILITY_BINDINGS) do
            T.assert_true(seen[name], "available() omits the bound capability '" .. name .. "'")
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Meta: the checker can fail
-- ---------------------------------------------------------------------------
-- A green check whose failure path is never exercised measures nothing. These two drive the
-- checker against deliberate lies of each shape it is meant to catch.

--- ADR 08 §13.1 item 18 explained the truthiness lint's zero by saying it seeds on `Sentinel.cond`
--- and cannot recognise a `require("kernel/cond")` consumer. There was a second cause it did not
--- name: `Sentinel.cond` WAS NOT A FIELD. The module had 17 predicates, a test suite, and -- outside
--- itself -- zero requires anywhere in the tree. It was unreachable by either route, so the lint's
--- seed matched a surface that did not exist and the zero measured nothing twice over.
---
--- Publishing it is what lets a plugin evaluate a predicate at all, which is what Phase 4c D5's
--- end-to-end pin drives.
function M.test_cond_is_published_and_binds_against_a_frozen_snapshot()
    with_saved_globals(function()
        local Snapshot = require("kernel/snapshot")
        local Truth = require("kernel/truth")
        local surface = Api.build(fully_wired_kernel())

        T.assert_not_nil(surface.cond, "kernel/cond must be reachable from the public surface")

        local builder = Snapshot.builder({ tick_index = 1 })
        builder:put("player.available", true)
        builder:put("player.health_pct", 0.10)
        local predicates = surface.cond.bind(builder:freeze())

        T.assert_true(predicates.health_below(0.15) == Truth.True,
            "a bound predicate must answer in Truth, not in booleans")
    end)
end

--- `cond` without `Truth` is a service a plugin can call and cannot USE.
---
--- Predicates answer in Truth values. A plugin may not `require("kernel/truth")` -- that is what
--- `tests/kernel/test_plugin_require_audit.lua` forbids -- so without the type on the surface it has
--- no way to name `Truth.True`, and no way to reach `Truth.resolve`, which is the only thing that
--- turns a tri-state into the boolean a behaviour-tree condition must return. Publishing the
--- predicates alone would have shipped the same defect this phase is about, one level up.
function M.test_the_truth_type_is_published_alongside_the_predicates()
    with_saved_globals(function()
        local surface = Api.build(fully_wired_kernel())
        T.assert_not_nil(surface.Truth, "the tri-state type must be nameable by a plugin")
        T.assert_not_nil(surface.Truth.Unknown)
        T.assert_true(type(surface.Truth.resolve) == "function",
            "and resolvable, or a BT condition cannot answer at all")
        T.assert_not_nil(surface.Truth.Policy.TreatFalse,
            "with the unknown policies, since resolve REFUSES to be called without one")
    end)
end

function M.test_the_checker_catches_a_capability_that_resolves_to_nothing()
    with_saved_globals(function()
        local surface = Api.build(fully_wired_kernel())
        local failures = check_all(
            surface,
            { ["ghost"] = true },
            { ["ghost"] = { path = { "no_such_field" }, members = { "anything" } } })
        T.assert_equal(#failures, 1, "an unresolvable capability must be reported")
        T.assert_true(failures[1]:find("ghost", 1, true) ~= nil, failures[1])
        T.assert_true(failures[1]:find("no_such_field", 1, true) ~= nil,
            "and the report must name the segment that failed: " .. failures[1])
    end)
end

function M.test_the_checker_catches_a_promised_member_that_is_absent()
    with_saved_globals(function()
        local surface = Api.build(fully_wired_kernel())
        local failures = check_all(
            surface,
            { ["control"] = true },
            { ["control"] = { path = { "control" }, members = { "acquire", "teleport" } } })
        T.assert_equal(#failures, 1, "a missing member must be reported even when the path resolves")
        T.assert_true(failures[1]:find("teleport", 1, true) ~= nil, failures[1])
    end)
end

return M
