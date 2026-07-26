-- tests/kernel/test_rotation_discovery.lua
-- ADR 08 §14: the three bundled rotation manifests must actually REACH the kernel.
--
-- Before this wiring, every manifest was well-formed and unreachable: nothing called
-- `Sentinel.register` or pushed `__SentinelPending`, so `refresh_eligibility` iterated an empty
-- table on every tick, forever, and the live path stayed `Registry.resolve`. These tests pin the
-- whole road: seed -> discover -> VALIDATED -> resolve -> LOADED -> refresh -> ELIGIBLE ->
-- activate -> ACTIVE with a built tree, plus the two guards that stop the wiring from
-- double-driving a rotation that `Registry.resolve` already built.
--
-- WHAT THESE TESTS CANNOT SEE
--  * The real Sylvanas surface. Activation of the REAL paladin manifest goes through
--    `Profile.build`, which needs `Sentinel.rotation`/`Sentinel.bt`; the app-level test boots the
--    real kernel surface offline, but nothing here proves the surface matches the live injector's.
--  * Tick ordering under load. The SENSE-stage handler runs drain -> resolve -> refresh ->
--    activate in one tick here; a live client interleaves other stages between them.
--  * `Registry.resolve`'s own behaviour — pinned by test_registry.lua, not re-tested here.

local PluginRegistry = require("kernel/plugin_registry")
local S = PluginRegistry.STATES
local Api = require("kernel/api")
local Snapshot = require("kernel/snapshot")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

-- test_util spells it assert_equal(actual, expected); this file argues expected-first.
local function assert_eq(expected, actual, message)
    T.assert_equal(actual, expected, message)
end

local ROTATION_MANIFEST_PATHS = {
    "rotations/mage_frost/manifest",
    "rotations/paladin_retribution/manifest",
    "rotations/warlock_affliction/manifest",
}

local function make_registry()
    return PluginRegistry:new({
        api_version = "1.0.0",
        kernel_provides = Api.KERNEL_CAPABILITIES,
        event_bus = EventBus:new(function() end),
    })
end

local function snapshot_of(fields)
    local b = Snapshot.builder({ tick_index = 1 })
    for k, v in pairs(fields) do b:put(k, v) end
    return b:freeze()
end

local function discover_all(registry)
    for _, path in ipairs(ROTATION_MANIFEST_PATHS) do
        local manifest = require(path)
        local ok, reason = registry:discover(manifest)
        T.assert_true(ok, path .. " must validate, got: " .. tostring(reason))
    end
end

-- ---------------------------------------------------------------------------
-- 1. The lifecycle, with the three REAL manifests
-- ---------------------------------------------------------------------------

function M.test_all_three_real_manifests_reach_loaded()
    local registry = make_registry()
    discover_all(registry)
    registry:resolve()
    for _, id in ipairs({
        "sentinel.rotation.mage_frost",
        "sentinel.rotation.paladin_retribution",
        "sentinel.rotation.warlock_affliction",
    }) do
        assert_eq(S.LOADED, registry:state(id),
            id .. " must be LOADED after capability resolution, got: "
            .. tostring(registry:state(id)) .. " (" .. tostring(registry:reason(id)) .. ")")
    end
end

function M.test_eligibility_selects_exactly_the_snapshot_class()
    local registry = make_registry()
    discover_all(registry)
    registry:resolve()
    registry:refresh_eligibility(
        snapshot_of({ ["player.class"] = "Paladin", ["player.level"] = 60 }), 1)

    assert_eq(S.ELIGIBLE, registry:state("sentinel.rotation.paladin_retribution"),
        "the Paladin manifest must be ELIGIBLE for a Paladin snapshot")
    for _, other in ipairs({ "sentinel.rotation.mage_frost", "sentinel.rotation.warlock_affliction" }) do
        assert_eq(S.LOADED, registry:state(other),
            other .. " must stay LOADED for a Paladin snapshot")
        assert_eq("applies_to:class", registry:reason(other),
            other .. " must record WHY it is ineligible — an anonymous refusal is the ADR §12 failure")
    end
end

-- ---------------------------------------------------------------------------
-- 2. The app's activation step (the method the SENSE stage calls)
-- ---------------------------------------------------------------------------

--- A stub rotation manifest whose build counts invocations — the double-drive detector.
local function stub_rotation(id, class, builds)
    return {
        id = id,
        kind = "rotation",
        version = "1.0.0",
        api = "^1.0",
        applies_to = { class = class },
        provides = {},
        requires = {},
        priority = { band = "COMBAT", offset = 0 },
        build = function()
            builds.count = builds.count + 1
            return { id = id .. ".tree" }
        end,
    }
end

local function app_shim(registry, blackboard_fields)
    -- The narrow seam _activate_eligible_rotation actually reads: a blackboard, an event bus and
    -- the registry. A full SentinelApp boot is the integration test's job, not this one's.
    local store = blackboard_fields or {}
    local bb = {
        get = function(_, k) return store[k] end,
        set = function(_, k, v) store[k] = v end,
    }
    local App = require("runtime/app")
    local shim = setmetatable({
        _plugin_registry = registry,
        _blackboard = bb,
        _event_bus = EventBus:new(function() end),
    }, { __index = App })
    return shim, store
end

function M.test_activation_builds_the_eligible_rotation_exactly_once()
    local registry = make_registry()
    local builds = { count = 0 }
    T.assert_true(registry:discover(stub_rotation("stub.rotation.pally", "Paladin", builds)))
    registry:resolve()
    local snap = snapshot_of({ ["player.class"] = "Paladin", ["player.level"] = 60 })
    registry:refresh_eligibility(snap, 1)

    local shim, store = app_shim(registry)
    shim:_activate_eligible_rotation(snap)
    assert_eq(1, builds.count, "activation must build the rotation tree exactly once")
    assert_eq("stub.rotation.pally.tree", store["rotation.kernel_profile"].id,
        "the built tree must be published for the combat module to adopt")
    assert_eq(S.ACTIVE, registry:state("stub.rotation.pally"))

    -- A second tick must not rebuild: the plugin is ACTIVE and the method returns early.
    shim:_activate_eligible_rotation(snap)
    assert_eq(1, builds.count, "a second tick must NOT rebuild — that is the double-drive")
end

function M.test_activation_defers_to_a_profile_the_fallback_path_already_built()
    local registry = make_registry()
    local builds = { count = 0 }
    T.assert_true(registry:discover(stub_rotation("stub.rotation.pally", "Paladin", builds)))
    registry:resolve()
    local snap = snapshot_of({ ["player.class"] = "Paladin", ["player.level"] = 60 })
    registry:refresh_eligibility(snap, 1)

    -- Registry.resolve's fallback built first (it writes rotation.profile_id, no plugin id).
    local shim = app_shim(registry, { ["rotation.profile_id"] = "paladin_retribution_tbc" })
    shim:_activate_eligible_rotation(snap)
    assert_eq(0, builds.count,
        "a profile built by the fallback path must not be built AGAIN by the plugin path")
end

function M.test_no_eligible_rotation_raises_the_unmatched_flag_only_with_a_real_class()
    local registry = make_registry()
    local builds = { count = 0 }
    T.assert_true(registry:discover(stub_rotation("stub.rotation.pally", "Paladin", builds)))
    registry:resolve()

    -- Boot tick: no player.class in the snapshot yet. Silence, not a verdict.
    local empty = snapshot_of({})
    registry:refresh_eligibility(empty, 1)
    local shim, store = app_shim(registry)
    shim:_activate_eligible_rotation(empty)
    assert_eq(nil, store["rotation.kernel_unmatched"],
        "no class read yet means NO verdict — flagging here would disable combat during boot")

    -- A confirmed class with no matching rotation: the loud, honest verdict.
    local warrior = snapshot_of({ ["player.class"] = "Warrior", ["player.level"] = 60 })
    registry:refresh_eligibility(warrior, 100)
    shim:_activate_eligible_rotation(warrior)
    assert_eq(true, store["rotation.kernel_unmatched"],
        "a confirmed class with no eligible rotation must surface, matching Registry.resolve's fail-loud nil")
end

return M
