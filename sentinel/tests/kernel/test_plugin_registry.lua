-- tests/kernel/test_plugin_registry.lua
-- ADR 08 §8.3's lifecycle, driven by the adversarial fixture.
--
--   DISCOVERED -> VALIDATED -> LOADED -> ELIGIBLE -> ACTIVE <-> SUSPENDED -> UNLOADED
--                      |                    |
--                      +-> REJECTED         +-> QUARANTINED (3 faults)

local PluginRegistry = require("kernel/plugin_registry")
local S = PluginRegistry.STATES
local Config = require("kernel/config")
local Api = require("kernel/api")
local Snapshot = require("kernel/snapshot")
local EventBus = require("core/event_bus")
local Fixture = require("tests/fixtures/awkward_rotation")
local T = require("tests/test_util")

local M = {}

local function make_registry(opts)
    opts = opts or {}
    return PluginRegistry:new({
        api_version = opts.api_version or "1.0.0",
        kernel_provides = opts.kernel_provides or Api.KERNEL_CAPABILITIES,
        event_bus = EventBus:new(function() end),
        config = opts.config,
        eligibility_interval_ticks = opts.eligibility_interval_ticks,
    })
end

local function snapshot_of(fields)
    local b = Snapshot.builder({ tick_index = 1 })
    for k, v in pairs(fields) do b:put(k, v) end
    return b:freeze()
end

--- A level-20 Mage: satisfies the fixture's applies_to.
local function mage_20()
    return snapshot_of({ ["player.class"] = "Mage", ["player.level"] = 20 })
end

--- A level-1 Mage: fails the fixture's min_level gate.
local function mage_1()
    return snapshot_of({ ["player.class"] = "Mage", ["player.level"] = 1 })
end

-- ---------------------------------------------------------------------------
-- DISCOVERED -> VALIDATED | REJECTED
-- ---------------------------------------------------------------------------

function M.test_a_valid_manifest_reaches_validated()
    local registry = make_registry()
    local fixture = Fixture.new()
    T.assert_true(registry:discover(fixture.manifest))
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.VALIDATED)
end

function M.test_an_invalid_manifest_is_rejected_with_the_validator_reason()
    local registry = make_registry()
    local fixture = Fixture.new({ kind = "wizard" })
    local ok, reason = registry:discover(fixture.manifest)
    T.assert_false(ok)
    T.assert_equal(reason, "invalid_kind:wizard")
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.REJECTED)
    T.assert_equal(registry:reason("sentinel.rotation.awkward"), "invalid_kind:wizard")
end

function M.test_a_manifest_with_no_id_cannot_even_be_filed()
    local registry = make_registry()
    local ok, reason = registry:discover({ kind = "rotation" })
    T.assert_false(ok)
    T.assert_equal(reason, "missing_field:id")
end

function M.test_a_duplicate_id_is_refused()
    local registry = make_registry()
    registry:discover(Fixture.new().manifest)
    local ok, reason = registry:discover(Fixture.new().manifest)
    T.assert_false(ok)
    T.assert_equal(reason, "duplicate_id")
end

--- The version gate, through the registry.
function M.test_an_incompatible_api_version_is_rejected()
    local registry = make_registry({ api_version = "2.0.0" })
    local ok, reason = registry:discover(Fixture.new().manifest)
    T.assert_false(ok, "^1.0 must not load on a 2.0.0 kernel")
    T.assert_equal(reason, "api_incompatible:^1.0")
end

-- ---------------------------------------------------------------------------
-- VALIDATED -> LOADED | REJECTED  (capability resolution)
-- ---------------------------------------------------------------------------

--- The named exit criterion: unmet `requires`, refused with a named reason.
function M.test_the_fixture_alone_is_refused_for_its_unmet_requirement()
    local registry = make_registry()
    registry:discover(Fixture.new().manifest)
    registry:resolve()

    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.REJECTED)
    T.assert_equal(registry:reason("sentinel.rotation.awkward"),
        "requires_unmet:target_selection",
        "the refusal must name the capability the fixture is missing")
end

function M.test_the_fixture_loads_once_its_provider_is_present()
    local registry = make_registry()
    registry:discover(Fixture.target_strategy())
    registry:discover(Fixture.new().manifest)
    registry:resolve()

    T.assert_equal(registry:state("sentinel.strategy.dummy_targeting"), S.LOADED)
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.LOADED)

    local order = registry:order()
    T.assert_equal(order[1], "sentinel.strategy.dummy_targeting",
        "the provider must load before the consumer")
    T.assert_equal(order[2], "sentinel.rotation.awkward")
end

--- The fixture's `conflicts` entry, in the reverse direction: the conflicting rotation sorts
--- lexicographically after the fixture, so the fixture wins and it is refused.
function M.test_the_fixtures_conflict_is_enforced()
    local registry = make_registry()
    registry:discover(Fixture.target_strategy())
    registry:discover(Fixture.new().manifest)
    registry:discover(Fixture.conflicting_rotation())
    registry:resolve()

    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.LOADED)
    T.assert_equal(registry:state("sentinel.rotation.mage_generic"), S.REJECTED)
    T.assert_equal(registry:reason("sentinel.rotation.mage_generic"),
        "conflicts:sentinel.rotation.awkward")
end

-- ---------------------------------------------------------------------------
-- LOADED <-> ELIGIBLE  (applies_to against live state)
-- ---------------------------------------------------------------------------

--- The fixture's applies_to is FALSE at level 1 and TRUE at level 20 -- deliberately, so this
--- transition is exercised rather than assumed.
function M.test_applies_to_gates_eligibility_and_later_admits()
    local registry = make_registry()
    registry:discover(Fixture.target_strategy())
    registry:discover(Fixture.new().manifest)
    registry:resolve()

    registry:refresh_eligibility(mage_1(), 1)
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.LOADED,
        "a level-1 character must not make a min_level-20 rotation eligible")
    T.assert_equal(registry:reason("sentinel.rotation.awkward"), "applies_to:min_level")

    registry:invalidate_eligibility()
    registry:refresh_eligibility(mage_20(), 2)
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.ELIGIBLE,
        "levelling to 20 must make it eligible")
end

function M.test_a_wrong_class_is_never_eligible()
    local registry = make_registry()
    registry:discover(Fixture.target_strategy())
    registry:discover(Fixture.new().manifest)
    registry:resolve()
    registry:refresh_eligibility(
        snapshot_of({ ["player.class"] = "Warrior", ["player.level"] = 60 }), 1)
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.LOADED)
    T.assert_equal(registry:reason("sentinel.rotation.awkward"), "applies_to:class")
end

--- A manifest with no applies_to is eligible unconditionally.
function M.test_a_manifest_without_applies_to_is_eligible_immediately()
    local registry = make_registry()
    registry:discover(Fixture.target_strategy())
    registry:resolve()
    registry:refresh_eligibility(mage_1(), 1)
    T.assert_equal(registry:state("sentinel.strategy.dummy_targeting"), S.ELIGIBLE)
end

-- ---------------------------------------------------------------------------
-- The throttle -- applies_to reads cold-tier data
-- ---------------------------------------------------------------------------

--- ADR §7 puts class/level in the cold tier (poll-only) and §13 risk 6 is the RXPGuides
--- never-invalidated cache. So: throttled, not per-tick.
function M.test_eligibility_is_not_re_evaluated_every_tick()
    local registry = make_registry({ eligibility_interval_ticks = 10 })
    registry:discover(Fixture.target_strategy())
    registry:resolve()

    T.assert_true(registry:refresh_eligibility(mage_1(), 1), "the first call must evaluate")
    T.assert_false(registry:refresh_eligibility(mage_1(), 2), "tick 2 is inside the throttle window")
    T.assert_false(registry:refresh_eligibility(mage_1(), 9))
    T.assert_true(registry:refresh_eligibility(mage_1(), 11),
        "past the interval it must evaluate again")
end

--- ...and the signal is the fast path, because with no level-up event a throttle alone would leave
--- a rotation ineligible for up to a full interval after the state actually changed.
function M.test_invalidating_eligibility_bypasses_the_throttle()
    local registry = make_registry({ eligibility_interval_ticks = 1000 })
    registry:discover(Fixture.target_strategy())
    registry:discover(Fixture.new().manifest)
    registry:resolve()
    registry:refresh_eligibility(mage_1(), 1)

    T.assert_false(registry:refresh_eligibility(mage_20(), 2), "throttled without a signal")
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.LOADED)

    registry:invalidate_eligibility()
    T.assert_true(registry:refresh_eligibility(mage_20(), 3), "the signal must force a re-read")
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.ELIGIBLE)
end

-- ---------------------------------------------------------------------------
-- ELIGIBLE -> ACTIVE, and the preflight veto
-- ---------------------------------------------------------------------------

--- The fixture vetoes its FIRST preflight and passes afterwards, which is why activation is a
--- separate step from eligibility.
function M.test_the_fixtures_preflight_vetoes_once_then_admits()
    local registry = make_registry()
    local fixture = Fixture.new()
    registry:discover(Fixture.target_strategy())
    registry:discover(fixture.manifest)
    registry:resolve()
    registry:refresh_eligibility(mage_20(), 1)
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.ELIGIBLE)

    local ok, reason = registry:activate("sentinel.rotation.awkward")
    T.assert_false(ok, "the first preflight vetoes")
    T.assert_equal(reason, "preflight_vetoed")
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.ELIGIBLE,
        "a veto leaves it eligible, not rejected -- it may pass later")
    T.assert_equal(registry:reason("sentinel.rotation.awkward"),
        "preflight_vetoed:water elemental on cooldown",
        "the veto reason must survive into the diagnostic")

    T.assert_true(registry:activate("sentinel.rotation.awkward"), "the second attempt passes")
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.ACTIVE)
    T.assert_equal(fixture.preflight_calls, 2)
end

--- `build` runs on activation, and its tree is retained (§8.2: declarative is preferred).
function M.test_build_runs_on_activation()
    local registry = make_registry()
    local fixture = Fixture.new()
    fixture.veto_first_preflight = false
    registry:discover(Fixture.target_strategy())
    registry:discover(fixture.manifest)
    registry:resolve()
    registry:refresh_eligibility(mage_20(), 1)
    registry:activate("sentinel.rotation.awkward")

    T.assert_equal(fixture.build_calls, 1)
end

--- A preflight that throws is a VETO, not a pass: it was asked whether it can run and failed to
--- answer, and assuming yes is the fail-open direction.
function M.test_a_throwing_preflight_is_treated_as_a_veto()
    local registry = make_registry()
    local fixture = Fixture.new({ preflight = function() error("preflight exploded", 0) end })
    registry:discover(Fixture.target_strategy())
    registry:discover(fixture.manifest)
    registry:resolve()
    registry:refresh_eligibility(mage_20(), 1)

    local ok, reason = registry:activate("sentinel.rotation.awkward")
    T.assert_false(ok, "a throwing preflight must not activate the plugin")
    T.assert_equal(reason, "preflight_error")
end

function M.test_activating_something_not_eligible_is_refused_by_name()
    local registry = make_registry()
    registry:discover(Fixture.target_strategy())
    registry:discover(Fixture.new().manifest)
    registry:resolve()
    local ok, reason = registry:activate("sentinel.rotation.awkward")
    T.assert_false(ok)
    T.assert_equal(reason, "not_eligible:LOADED")
end

function M.test_suspend_and_reactivate()
    local registry = make_registry()
    local fixture = Fixture.new()
    fixture.veto_first_preflight = false
    registry:discover(Fixture.target_strategy())
    registry:discover(fixture.manifest)
    registry:resolve()
    registry:refresh_eligibility(mage_20(), 1)
    registry:activate("sentinel.rotation.awkward")

    T.assert_true(registry:suspend("sentinel.rotation.awkward", "player_paused"))
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.SUSPENDED)
    T.assert_true(registry:activate("sentinel.rotation.awkward"))
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.ACTIVE)
end

-- ---------------------------------------------------------------------------
-- Status, and the nil-return rule (ADR 08 §8.3)
-- ---------------------------------------------------------------------------

local function active_fixture()
    local registry = make_registry()
    local fixture = Fixture.new()
    fixture.veto_first_preflight = false
    registry:discover(Fixture.target_strategy())
    registry:discover(fixture.manifest)
    registry:resolve()
    registry:refresh_eligibility(mage_20(), 1)
    registry:activate("sentinel.rotation.awkward")
    return registry, fixture
end

function M.test_every_status_round_trips()
    local registry, fixture = active_fixture()
    for _, status in ipairs({ "DONE", "RUNNING", "YIELD", "FAILED" }) do
        fixture.next_status = status
        local got = registry:tick("sentinel.rotation.awkward", { tick_index = 1 })
        T.assert_equal(got, status)
    end
end

--- §8.3: BLOCKED "carries a reason string, which is what feeds the runner cockpit's blocked-reason
--- display".
function M.test_blocked_carries_its_reason()
    local registry, fixture = active_fixture()
    fixture.next_status = "BLOCKED"
    fixture.next_reason = "no path to the vendor"
    local status, reason = registry:tick("sentinel.rotation.awkward", { tick_index = 1 })
    T.assert_equal(status, "BLOCKED")
    T.assert_equal(reason, "no path to the vendor")
end

--- THE named exit criterion: "A `tick` returning `nil` is a validation error."
function M.test_a_tick_returning_nil_is_a_fault_not_a_default()
    local registry = make_registry()
    local fixture = Fixture.new({ tick = function() return nil end })
    fixture.veto_first_preflight = false
    registry:discover(Fixture.target_strategy())
    registry:discover(fixture.manifest)
    registry:resolve()
    registry:refresh_eligibility(mage_20(), 1)
    registry:activate("sentinel.rotation.awkward")

    local status, reason = registry:tick("sentinel.rotation.awkward", { tick_index = 1 })
    T.assert_nil(status, "nil must NOT be silently read as DONE")
    T.assert_equal(reason, "tick_returned_nil")
end

function M.test_an_unrecognised_status_is_a_fault()
    local registry = make_registry()
    local fixture = Fixture.new({ tick = function() return "PROBABLY_FINE" end })
    fixture.veto_first_preflight = false
    registry:discover(Fixture.target_strategy())
    registry:discover(fixture.manifest)
    registry:resolve()
    registry:refresh_eligibility(mage_20(), 1)
    registry:activate("sentinel.rotation.awkward")

    local status, reason = registry:tick("sentinel.rotation.awkward", { tick_index = 1 })
    T.assert_nil(status)
    T.assert_equal(reason, "invalid_status:PROBABLY_FINE")
end

-- ---------------------------------------------------------------------------
-- QUARANTINE -- reusing the 3-strike rule
-- ---------------------------------------------------------------------------

function M.test_three_consecutive_nil_returns_quarantine_the_plugin()
    local registry = make_registry()
    local fixture = Fixture.new({ tick = function() return nil end })
    fixture.veto_first_preflight = false
    registry:discover(Fixture.target_strategy())
    registry:discover(fixture.manifest)
    registry:resolve()
    registry:refresh_eligibility(mage_20(), 1)
    registry:activate("sentinel.rotation.awkward")

    for _ = 1, 3 do registry:tick("sentinel.rotation.awkward", { tick_index = 1 }) end
    T.assert_equal(registry:state("sentinel.rotation.awkward"), S.QUARANTINED)

    local status, reason = registry:tick("sentinel.rotation.awkward", { tick_index = 2 })
    T.assert_nil(status)
    T.assert_equal(reason, "quarantined", "a quarantined plugin must stop being called")
end

--- Only CONSECUTIVE faults degrade -- the rule inherited from ModuleRegistry.
function M.test_a_successful_tick_resets_the_fault_streak()
    local registry, fixture = active_fixture()
    local id = "sentinel.rotation.awkward"

    fixture.manifest.tick = function() return nil end
    registry:tick(id, {}); registry:tick(id, {})
    fixture.manifest.tick = function() return "RUNNING" end
    T.assert_equal(registry:tick(id, {}), "RUNNING")
    fixture.manifest.tick = function() return nil end
    registry:tick(id, {}); registry:tick(id, {})

    T.assert_equal(registry:state(id), S.ACTIVE, "the streak must have reset")
end

-- ---------------------------------------------------------------------------
-- The load-time diagnostic report (ADR 08 §12)
-- ---------------------------------------------------------------------------

function M.test_the_report_explains_every_plugin_state()
    local registry = make_registry()
    registry:discover(Fixture.new().manifest)                 -- will lack target_selection
    registry:discover(Fixture.new({ id = "bad.kind", kind = "wizard" }).manifest)
    registry:resolve()

    local report = registry:report()
    T.assert_equal(report.api_version, "1.0.0")
    T.assert_equal(#report.plugins, 2)

    local by_id = {}
    for _, p in ipairs(report.plugins) do by_id[p.id] = p end

    T.assert_equal(by_id["bad.kind"].state, S.REJECTED)
    T.assert_equal(by_id["bad.kind"].reason, "invalid_kind:wizard")
    T.assert_equal(by_id["sentinel.rotation.awkward"].state, S.REJECTED)
    T.assert_equal(by_id["sentinel.rotation.awkward"].reason, "requires_unmet:target_selection")
    T.assert_equal(by_id["sentinel.rotation.awkward"].kind, "rotation")
    T.assert_equal(by_id["sentinel.rotation.awkward"].version, "0.3.1")
end

function M.test_the_report_is_byte_stable_across_runs()
    local function build_report()
        local registry = make_registry()
        registry:discover(Fixture.target_strategy())
        registry:discover(Fixture.new().manifest)
        registry:discover(Fixture.conflicting_rotation())
        registry:resolve()
        local report = registry:report()
        local parts = {}
        for _, p in ipairs(report.plugins) do
            parts[#parts + 1] = p.id .. "=" .. p.state .. "/" .. tostring(p.reason)
        end
        return table.concat(parts, ";")
    end

    local first = build_report()
    for _ = 1, 10 do
        T.assert_equal(build_report(), first, "the diagnostic report must be reproducible")
    end
end

function M.test_the_report_counts_states()
    local registry = make_registry()
    registry:discover(Fixture.target_strategy())
    registry:discover(Fixture.new().manifest)
    registry:resolve()
    local report = registry:report()
    T.assert_equal(report.counts[S.LOADED], 2)
end

function M.test_report_lines_are_human_readable()
    local registry = make_registry()
    registry:discover(Fixture.new().manifest)
    registry:resolve()
    local lines = registry:report_lines()
    T.assert_true(#lines >= 2)
    T.assert_true(lines[2]:find("requires_unmet:target_selection", 1, true) ~= nil,
        "the log line must carry the reason: " .. lines[2])
end

-- ---------------------------------------------------------------------------
-- Config integration
-- ---------------------------------------------------------------------------

function M.test_discovery_declares_the_manifests_config_block()
    local config = Config:new()
    local registry = make_registry({ config = config })
    registry:discover(Fixture.new().manifest)

    local id = "sentinel.rotation.awkward"
    T.assert_equal(config:get(id, "use_water_elemental"), true)
    T.assert_equal(config:get(id, "blink_threshold"), 35)
    T.assert_near(config:get(id, "leash_yards"), 12.5, 0.0001)
    T.assert_equal(config:get(id, "label"), "awkward")
    T.assert_equal(config:get(id, "stance"), "objective")
end

return M
