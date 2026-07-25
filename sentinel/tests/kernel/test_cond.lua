-- tests/kernel/test_cond.lua
-- The kernel condition predicates: snapshot in, Truth out.
--
-- WHAT THIS SUITE IS FOR.
-- The seventeen predicates in kernel/cond are a FIXTURE PROVING THE TYPE, not a rotation
-- vocabulary. They were chosen so that between them they exercise Unknown propagating
-- through Kleene composition, a policy resolving at the call site, TreatTrue announcing
-- itself, and -- the one that cannot be faked -- Unknown arising from data the snapshot
-- genuinely does not carry (there is no pet tier; see kernel/snapshot_source.lua, which
-- captures `player.*` and `target.*` and nothing else).
--
-- Individual `test*` functions, never a `run()` aggregator: the offline runner counts a
-- `run()` suite as ONE unit, hiding how many cases exist. Phase 4b Deliverable 0 was bitten
-- by exactly that.

-- Explicit `/init`, matching runtime/module_registry.lua:41's `require("modules/combat/init")`:
-- the offline package.path has no `?/init.lua` pattern, so a bare `kernel/cond` would resolve
-- to a file that does not exist.
local Cond = require("kernel/cond/init")
local Fraction = require("kernel/cond/fraction")
local Snapshot = require("kernel/snapshot")
local Truth = require("kernel/truth")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- Fixtures -- built through the REAL snapshot builder, not a stub
-- ---------------------------------------------------------------------------
--
-- Using kernel/snapshot.lua itself means these tests also exercise the freeze and
-- deep-copy path. A hand-rolled `{ get = function() end }` stub would let a predicate pass
-- here and fail against a real frozen snapshot.

local function snap(values)
    local builder = Snapshot.builder({ tick_index = 1 })
    for key, value in pairs(values) do builder:put(key, value) end
    return builder:freeze()
end

--- Explicit "this key is absent from the snapshot".
---
--- `{ ["player.in_combat"] = nil }` CANNOT express that: a nil value means the key is not
--- in the override table at all, so `pairs` never yields it and the fixture default
--- survives untouched. Three unreadability tests were silently asserting against a
--- readable `false` until this sentinel existed -- the same shape of green-and-wrong the
--- unit pin exists to prevent, one layer up.
local ABSENT = setmetatable({}, { __tostring = function() return "<absent>" end })
M.ABSENT = ABSENT

--- A fully readable player, no target. Every field on the pin.
local function healthy_player(overrides)
    local values = {
        ["player.available"] = true,
        ["player.health_pct"] = 1.0,
        ["player.power_pct"] = 1.0,
        ["player.level"] = 70,
        ["player.class_id"] = 8,
        ["player.class"] = "Mage",
        ["player.is_dead"] = false,
        ["player.in_combat"] = false,
        ["player.is_casting"] = false,
        ["player.is_channeling"] = false,
        ["player.is_moving"] = false,
        ["player.position"] = { x = 0, y = 0, z = 0 },
        ["target.available"] = false,
    }
    for key, value in pairs(overrides or {}) do
        if value == ABSENT then values[key] = nil else values[key] = value end
    end
    return Cond.bind(snap(values))
end

--- Guards the guard. If ABSENT ever stopped removing keys, every unreadability assertion
--- in this file would quietly start testing a readable value instead.
function M.test_the_absent_sentinel_actually_removes_the_key()
    local cond = healthy_player({ ["player.in_combat"] = ABSENT })
    T.assert_equal(cond.in_combat(), Truth.Unknown,
        "ABSENT must remove the key; a plain nil override cannot, because pairs() skips it")
    T.assert_equal(healthy_player().in_combat(), Truth.False,
        "and without the sentinel the fixture default is a READABLE false, not absence")
end

-- ============================================================================
-- THE PIN, AT THE PREDICATE LEVEL
-- ============================================================================
--
-- kernel/cond/fraction.lua pins the boundary; these assert the predicates actually stand
-- on it. The brief's headline case is first, and it is the one that must be red -- not a
-- review comment -- if anyone reintroduces a factor of 100.

--- health_below(0.30) is TRUE at 29% and FALSE at 31%. Both directions, because a
--- mis-scale that makes the predicate always-true only shows up on the false side.
function M.test_health_below_is_true_at_29_and_false_at_31()
    T.assert_equal(healthy_player({ ["player.health_pct"] = 0.29 }).health_below(0.30),
        Truth.True, "29% health IS below the 30% threshold")
    T.assert_equal(healthy_player({ ["player.health_pct"] = 0.31 }).health_below(0.30),
        Truth.False, "31% health is NOT below the 30% threshold")
end

--- The boundary itself. `below` is strict: at exactly the threshold the answer is False.
--- Without this case a `<` -> `<=` mutation survives, and "pinning the boundary" would
--- mean nothing.
function M.test_health_below_is_false_at_exactly_the_threshold()
    T.assert_equal(healthy_player({ ["player.health_pct"] = 0.30 }).health_below(0.30),
        Truth.False, "health_below is strict: 0.30 is not below 0.30")
end

function M.test_health_above_is_false_at_exactly_the_threshold()
    T.assert_equal(healthy_player({ ["player.health_pct"] = 0.30 }).health_above(0.30),
        Truth.False, "health_above is strict: 0.30 is not above 0.30")
    T.assert_equal(healthy_player({ ["player.health_pct"] = 0.31 }).health_above(0.30),
        Truth.True, "31% IS above 30%")
    T.assert_equal(healthy_player({ ["player.health_pct"] = 0.29 }).health_above(0.30),
        Truth.False, "29% is not above 30%")
end

--- The same pin on the OTHER resource, so that a scale change in fraction.lua breaks more
--- than one predicate and cannot be papered over by adjusting a single call.
function M.test_power_below_stands_on_the_same_pin()
    T.assert_equal(healthy_player({ ["player.power_pct"] = 0.29 }).power_below(0.30),
        Truth.True, "29% power IS below 30%")
    T.assert_equal(healthy_player({ ["player.power_pct"] = 0.31 }).power_below(0.30),
        Truth.False, "31% power is NOT below 30%")
    T.assert_equal(healthy_player({ ["player.power_pct"] = 0.30 }).power_below(0.30),
        Truth.False, "power_below is strict at the boundary")
end

--- THE ANTI-REGRESSION PREDICATE. modules/combat/condition_library.lua:105 divides a live
--- `get_health_percentage` by 100 before comparing. The kernel reads a snapshot value that
--- is ALREADY a fraction, so dividing again would make target_health_below(0.30) fire only
--- under 0.3% health. This case goes red the moment that `/ 100` is reintroduced.
function M.test_target_health_below_does_not_divide_by_one_hundred_again()
    local cond = healthy_player({
        ["target.available"] = true,
        ["target.health_pct"] = 0.29,
    })
    T.assert_equal(cond.target_health_below(0.30), Truth.True,
        "the snapshot already stores a fraction -- a second /100 would make this False")
end

function M.test_target_health_below_and_above_pin_their_boundary()
    local function at(pct) return healthy_player({
        ["target.available"] = true, ["target.health_pct"] = pct }) end
    T.assert_equal(at(0.31).target_health_below(0.30), Truth.False, "31% is not below 30%")
    T.assert_equal(at(0.30).target_health_below(0.30), Truth.False, "strict at the boundary")
    T.assert_equal(at(0.31).target_health_above(0.30), Truth.True, "31% is above 30%")
    T.assert_equal(at(0.30).target_health_above(0.30), Truth.False, "strict at the boundary")
    T.assert_equal(at(0.29).target_health_above(0.30), Truth.False, "29% is not above 30%")
end

--- The call-site half of the mis-scale, reaching the predicate. `health_below(30)` must
--- not quietly become an always-true gate.
function M.test_a_percentage_threshold_raises_at_the_predicate()
    local cond = healthy_player()
    T.assert_false(pcall(cond.health_below, 30), "health_below(30) must raise")
    T.assert_false(pcall(cond.health_above, 60), "health_above(60) must raise")
    T.assert_false(pcall(cond.power_below, 15), "power_below(15) must raise")
    T.assert_false(pcall(cond.target_health_below, 20), "target_health_below(20) must raise")
    T.assert_false(pcall(cond.target_health_above, 20), "target_health_above(20) must raise")
end

--- The SENSOR half, which no threshold guard can catch. If a sensor starts writing 0-100
--- into `health_pct`, the threshold stays a legal fraction and every gate silently
--- inverts. The predicate must say "I cannot tell", not "False".
function M.test_a_mis_scaled_source_value_yields_unknown_not_a_confident_answer()
    local cond = healthy_player({ ["player.health_pct"] = 30 })
    T.assert_equal(cond.health_below(0.30), Truth.Unknown,
        "a 0-100 value where a fraction belongs is unreadable, not a False")
    T.assert_equal(cond.health_above(0.30), Truth.Unknown,
        "and the mirror predicate must not manufacture a True out of it either")
end

--- The fraction guard must be SCOPED to fractions. A level is an integer on a 1-70 scale
--- and must not be clamped to 0-1 -- this is the "pin, convert, verify" invariant applied
--- in the direction people forget: not everything is a fraction.
function M.test_level_thresholds_are_not_fraction_clamped()
    local cond = healthy_player({ ["player.level"] = 70 })
    T.assert_equal(cond.level_at_least(70), Truth.True, "level 70 is at least 70")
    T.assert_equal(cond.level_at_least(71), Truth.False, "level 70 is not at least 71")
    T.assert_equal(cond.level_at_least(1), Truth.True,
        "a level threshold of 1 must not be read as the fraction 1.0")
end

function M.test_distance_thresholds_are_not_fraction_clamped()
    local cond = healthy_player({
        ["target.available"] = true,
        ["target.position"] = { x = 10, y = 0, z = 0 },
    })
    -- Yards, a third scale again: neither a fraction nor a percentage.
    T.assert_equal(cond.target_within(15), Truth.True, "10 yards is within 15")
    T.assert_equal(cond.target_within(5), Truth.False, "10 yards is not within 5")
    T.assert_equal(cond.target_within(10), Truth.True, "within is inclusive at the boundary")
end

-- ============================================================================
-- TYPE BEHAVIOUR: EVERY PREDICATE RETURNS Truth
-- ============================================================================

--- Table-driven over the WHOLE bound namespace rather than a hand-listed subset, so a
--- predicate added later without a Truth return is caught without anyone remembering to
--- extend this test. `Truth.is` indexes by identity and never touches the value's __index.
function M.test_every_predicate_returns_a_truth_and_never_a_boolean()
    local cond = healthy_player({
        ["target.available"] = true,
        ["target.health_pct"] = 0.5,
        ["target.level"] = 70,
        ["target.position"] = { x = 1, y = 0, z = 0 },
    })
    local sample_args = {
        health_below = { 0.3 }, health_above = { 0.3 }, power_below = { 0.3 },
        target_health_below = { 0.3 }, target_health_above = { 0.3 },
        level_at_least = { 60 }, target_level_at_least = { 60 },
        target_within = { 30 }, class_is = { "Mage" },
        unit_available = { Cond.UNIT_TARGET },
        unit_health_below = { Cond.UNIT_TARGET, 0.6 },
    }
    local checked = 0
    for name, predicate in pairs(cond) do
        if type(predicate) == "function" then
            local result = predicate(unpack(sample_args[name] or {}))
            T.assert_true(Truth.is(result),
                "kernel/cond." .. name .. " must return a Truth, got " .. type(result))
            T.assert_true(type(result) ~= "boolean",
                "kernel/cond." .. name .. " must not return a raw boolean")
            checked = checked + 1
        end
    end
    -- The scope-globbing defect, in miniature: a loop over an empty namespace passes
    -- vacuously and reports success. Assert it actually saw the predicates.
    T.assert_equal(checked, Cond.PREDICATE_COUNT,
        "the loop must cover every predicate, not an accidentally-empty namespace")
end

--- The count is asserted as a fact so that adding an eighteenth predicate is a deliberate
--- act with a test to update, rather than something that slips in unmeasured.
function M.test_the_ported_set_is_seventeen_predicates()
    T.assert_equal(Cond.PREDICATE_COUNT, 17,
        "seventeen predicates were ported; the rest are blocked on warm/cold snapshot tiers")
end

-- ============================================================================
-- TYPE BEHAVIOUR: UNKNOWN FROM DATA THAT IS GENUINELY ABSENT
-- ============================================================================
--
-- This is the case a test stub cannot fake. kernel/snapshot_source.lua captures exactly
-- two prefixes -- `player.*` (capture_player) and `target.*` (capture_unit on get_target).
-- There is no pet tier at all. So UNIT_PET produces Unknown because the data is missing in
-- the real system, not because a fixture withheld it.

function M.test_pet_predicates_are_unknown_because_no_pet_tier_exists()
    local cond = healthy_player()
    T.assert_equal(cond.unit_available(Cond.UNIT_PET), Truth.Unknown,
        "the snapshot has no pet tier -- absence of the KEY is not absence of the PET")
    T.assert_equal(cond.unit_health_below(Cond.UNIT_PET, 0.30), Truth.Unknown,
        "a pet's health cannot be read from a snapshot that never captured one")
end

--- The distinction the tri-state exists to make, and the one a boolean port destroys:
--- "there is definitely no target" and "I could not find out" are different answers.
function M.test_a_known_absent_target_is_false_but_an_uncaptured_one_is_unknown()
    T.assert_equal(healthy_player().has_target(), Truth.False,
        "target.available == false is a READING: there is no target")
    -- No `target.available` key at all -- the tier never ran.
    local uncaptured = Cond.bind(snap({ ["player.available"] = true }))
    T.assert_equal(uncaptured.has_target(), Truth.Unknown,
        "a missing key means the tier never ran, which is not the same as no target")
end

--- A target that is known absent still cannot answer a question ABOUT its health. The old
--- library returned false here (condition_library.lua:103), which reads as "the target is
--- healthy" to any caller that negates it.
function M.test_a_question_about_an_absent_target_is_unknown_not_false()
    local cond = healthy_player() -- target.available == false
    T.assert_equal(cond.target_health_below(0.30), Truth.Unknown,
        "no target means no health to compare, not a healthy target")
    T.assert_equal(cond.target_within(30), Truth.Unknown,
        "no target means no distance, not an out-of-range target")
end

--- ADR 08 §9.3. A nullable boolean is the commonest unreadable field, and mapping it to
--- false is the fail-open this whole type exists to kill.
function M.test_a_nil_boolean_field_lifts_to_unknown_never_to_false()
    for _, name in ipairs({ "in_combat", "is_casting", "is_channeling", "is_moving", "is_dead" }) do
        local cond = healthy_player({ ["player." .. name] = ABSENT })
        T.assert_equal(cond[name](), Truth.Unknown,
            "kernel/cond." .. name .. " must be Unknown when the field is unreadable")
    end
end

function M.test_readable_booleans_still_answer_definitely()
    T.assert_equal(healthy_player({ ["player.in_combat"] = true }).in_combat(), Truth.True)
    T.assert_equal(healthy_player({ ["player.in_combat"] = false }).in_combat(), Truth.False)
    T.assert_equal(healthy_player({ ["player.is_casting"] = true }).is_casting(), Truth.True)
    T.assert_equal(healthy_player({ ["player.is_channeling"] = true }).is_channeling(), Truth.True)
    T.assert_equal(healthy_player({ ["player.is_moving"] = true }).is_moving(), Truth.True)
    T.assert_equal(healthy_player({ ["player.is_dead"] = true }).is_dead(), Truth.True)
end

--- The known-state bug, pinned: `unit:get_class()` returns a NUMERIC class id and
--- `ClassIs` compares Title-Case names. The snapshot normalizes at capture
--- (snapshot_source.lua:108); this asserts the predicate consumes the normalized field and
--- does not go looking at class_id itself.
function M.test_class_is_compares_the_normalized_title_case_name()
    local cond = healthy_player({ ["player.class_id"] = 8, ["player.class"] = "Mage" })
    T.assert_equal(cond.class_is("Mage"), Truth.True, "class 8 normalizes to Mage")
    T.assert_equal(cond.class_is("Warlock"), Truth.False, "a Mage is definitely not a Warlock")
    T.assert_equal(cond.class_is("MAGE"), Truth.False,
        "comparison is exact -- UPPER-CASE is the combat module's casing, not the kernel's")
end

--- An unresolvable class_id yields a nil `class`, which must be Unknown rather than "not a
--- Mage". A rotation gated on `not class_is("Mage")` would otherwise run on everyone.
function M.test_an_unreadable_class_is_unknown_not_a_mismatch()
    local cond = healthy_player({ ["player.class_id"] = ABSENT, ["player.class"] = ABSENT })
    T.assert_equal(cond.class_is("Mage"), Truth.Unknown,
        "an unreadable class cannot answer a class question")
end

--- A dead player handle makes every field on that unit unreadable at once, rather than a
--- record of plausible zeros (snapshot_source.lua:93-96 sets available=false in that case).
function M.test_an_unavailable_player_makes_every_player_predicate_unknown()
    local cond = Cond.bind(snap({ ["player.available"] = false }))
    T.assert_equal(cond.health_below(0.30), Truth.Unknown)
    T.assert_equal(cond.in_combat(), Truth.Unknown)
    T.assert_equal(cond.level_at_least(70), Truth.Unknown)
    T.assert_equal(cond.class_is("Mage"), Truth.Unknown)
end

-- ============================================================================
-- TYPE BEHAVIOUR: KLEENE COMPOSITION
-- ============================================================================
--
-- Composed with kernel/truth.lua's combinators, never a second implementation. The point
-- here is not to re-test Kleene logic -- tests/kernel/test_truth.lua does that -- but to
-- prove that the Unknown a PREDICATE produces from real missing data flows through them
-- with the same semantics.

function M.test_unknown_from_a_real_gap_propagates_through_and()
    local cond = healthy_player({ ["player.in_combat"] = true })
    local pet = cond.unit_available(Cond.UNIT_PET) -- Unknown, from the absent pet tier
    T.assert_equal(Truth.and_(cond.in_combat(), pet), Truth.Unknown,
        "True AND Unknown is Unknown -- the unreadable conjunct still decides")
end

--- The rule a boolean port always gets wrong: a KNOWN False beats an unreadable operand.
function M.test_a_known_false_beats_a_real_unknown_under_and()
    local cond = healthy_player({ ["player.in_combat"] = false })
    T.assert_equal(Truth.and_(cond.in_combat(), cond.unit_available(Cond.UNIT_PET)),
        Truth.False, "False AND Unknown is False -- nothing the pet could be rescues it")
end

function M.test_a_known_true_beats_a_real_unknown_under_or()
    local cond = healthy_player({ ["player.in_combat"] = true })
    T.assert_equal(Truth.or_(cond.in_combat(), cond.unit_available(Cond.UNIT_PET)),
        Truth.True, "True OR Unknown is True")
    local idle = healthy_player({ ["player.in_combat"] = false })
    T.assert_equal(Truth.or_(idle.in_combat(), idle.unit_available(Cond.UNIT_PET)),
        Truth.Unknown, "False OR Unknown stays Unknown")
end

--- Negation must preserve ignorance. This is the composition that used to manufacture
--- certainty: `not_casting_or_channeling` (condition_library.lua:147) read two possibly-nil
--- fields, defaulted both to false, and returned a confident true.
function M.test_negating_a_real_unknown_does_not_manufacture_certainty()
    local cond = healthy_player({ ["player.is_casting"] = ABSENT, ["player.is_channeling"] = ABSENT })
    local busy = Truth.or_(cond.is_casting(), cond.is_channeling())
    T.assert_equal(busy, Truth.Unknown, "two unreadable fields cannot say the player is idle")
    T.assert_equal(Truth.not_(busy), Truth.Unknown,
        "NOT Unknown is Unknown -- the old library returned a confident true here")
end

-- ============================================================================
-- TYPE BEHAVIOUR: POLICY RESOLVES AT THE CALL SITE
-- ============================================================================

--- ADR 07 §5.1.2 makes Treat(True) "never a default", and the cheapest guarantee is no
--- default at all. A predicate value handed to resolve without a policy must raise.
function M.test_resolving_a_predicate_without_a_policy_raises()
    local cond = healthy_player()
    T.assert_false(pcall(Truth.resolve, cond.health_below(0.30)),
        "there is no default policy -- resolve must raise when the site did not declare one")
    T.assert_false(pcall(Truth.resolve, cond.health_below(0.30), "TreatTrue"),
        "a bare string is not a policy; the shape is adjacently tagged { type, payload }")
end

function M.test_the_same_unknown_resolves_differently_per_call_site()
    local cond = healthy_player()
    local unknown = cond.unit_available(Cond.UNIT_PET)
    T.assert_equal(unknown, Truth.Unknown, "precondition: a real Unknown")

    T.assert_equal(Truth.resolve(unknown, Truth.Policy.TreatFalse), false,
        "a conservative site reads Unknown as no")
    T.assert_equal(Truth.resolve(unknown, Truth.Policy.TreatTrue), true,
        "a permissive site reads Unknown as yes")
    T.assert_nil(Truth.resolve(unknown, Truth.Policy.Block),
        "a blocking site refuses to decide at all")
end

--- Policy governs Unknown ONLY. A predicate that read its data must never be overridden by
--- the call site's tolerance for ignorance.
function M.test_policy_never_overrides_a_readable_predicate()
    local cond = healthy_player({ ["player.health_pct"] = 0.31 })
    T.assert_equal(Truth.resolve(cond.health_below(0.30), Truth.Policy.TreatTrue), false,
        "TreatTrue must not flip a predicate that actually answered False")
end

-- ============================================================================
-- TYPE BEHAVIOUR: TreatTrue ANNOUNCES ITSELF
-- ============================================================================

local function with_diagnostic_sink(fn)
    local previous = Truth.on_diagnostic
    local seen = {}
    Truth.on_diagnostic = function(d) seen[#seen + 1] = d end
    local ok, err = pcall(fn, seen)
    Truth.on_diagnostic = previous
    if not ok then error(err, 0) end
    return seen
end

--- The fail-open direction is allowed, but never silent. This is the only way a reviewer
--- learns that a gate proceeded on data nobody could read.
function M.test_treat_true_emits_a_diagnostic_for_a_real_unknown()
    with_diagnostic_sink(function(seen)
        local cond = healthy_player()
        Truth.resolve(cond.unit_health_below(Cond.UNIT_PET, 0.30), Truth.Policy.TreatTrue)
        T.assert_equal(#seen, 1, "TreatTrue over an Unknown must emit exactly one diagnostic")
        T.assert_equal(seen[1].kind, "unknown_treated_as_true", "the diagnostic must be named")
    end)
end

--- And stays quiet when nothing was unknown, so the signal keeps its meaning. A diagnostic
--- that fires on every tick is a diagnostic nobody reads.
function M.test_treat_true_stays_silent_when_the_predicate_was_readable()
    with_diagnostic_sink(function(seen)
        local cond = healthy_player({ ["player.health_pct"] = 0.10 })
        T.assert_equal(Truth.resolve(cond.health_below(0.30), Truth.Policy.TreatTrue), true,
            "precondition: a readable True")
        T.assert_equal(#seen, 0, "no Unknown was treated as true, so nothing to announce")
    end)
end

-- ============================================================================
-- THE __toboolean TRAP
-- ============================================================================
--
-- Lua has no __toboolean, so `if predicate() then` cannot be made to raise. What CAN be
-- done is documented in kernel/truth.lua: all three values are truthy tables, so a careless
-- `if` is uniformly wrong on the very first case instead of correct-looking until the one
-- tick the data goes unreadable. These assert that property survives the trip through a
-- predicate, and that the near misses around it are loud.

--- The honest limit, asserted rather than hoped for: a careless `if` is wrong EVERY time,
--- including on a plain False. Wrong-every-time is what makes it findable.
function M.test_a_careless_truthiness_test_is_wrong_on_the_very_first_false()
    local cond = healthy_player({ ["player.health_pct"] = 1.0 })
    local definitely_not_low = cond.health_below(0.30)
    T.assert_equal(definitely_not_low, Truth.False, "precondition: a readable False")
    -- The mistake, written out. It takes the wrong branch immediately.
    local took_the_branch = false
    if definitely_not_low then took_the_branch = true end
    T.assert_true(took_the_branch,
        "a Truth.False is still a truthy table -- the careless `if` must fail LOUDLY and "
        .. "immediately, not silently on the rare unreadable tick")
end

--- The near misses. Someone reaching for `.value`, `.ok`, or a comparison gets an error
--- rather than a plausible nil.
function M.test_the_near_misses_around_a_predicate_result_all_raise()
    local result = healthy_player().health_below(0.30)
    T.assert_false(pcall(function() return result.value end), "field access must raise")
    T.assert_false(pcall(function() return result.ok end), "so must the other plausible name")
    T.assert_false(result == true, "a Truth is never == true")
    T.assert_false(result == false, "a Truth is never == false")
    T.assert_false(pcall(function() return "hp: " .. tostring(result) .. result end),
        "concatenating a Truth must raise")
end

--- A typo'd predicate name must not evaluate to nil and then be called (which yields a
--- confusing "attempt to call a nil value" far from the cause) -- the namespace names the
--- mistake and lists what it does have.
function M.test_an_unknown_predicate_name_raises_with_the_name_in_it()
    local cond = healthy_player()
    local ok, err = pcall(function() return cond.helth_below end)
    T.assert_false(ok, "a misspelt predicate must raise on ACCESS, not yield nil")
    T.assert_true(tostring(err):find("helth_below") ~= nil,
        "the error must quote the misspelt name, got: " .. tostring(err))
end

-- ============================================================================
-- THE SINGLE CONVERSION POINT, ENFORCED
-- ============================================================================

--- The brief requires the conversion to live in exactly one place. A comment saying so is
--- not a mechanism, so this scans the tree for stray scale factors.
---
--- NOTE ON SCOPE -- this is the defect shape that produced three bugs this phase (an audit
--- right about what it saw and wrong about what it looked at). The file list is globbed, so
--- a glob that silently returns nothing would make this pass vacuously. It therefore
--- asserts the scan actually found the files it is supposed to cover.
function M.test_no_stray_scale_factors_outside_the_boundary_module()
    local pipe = io.popen('find sentinel/kernel/cond -type f -name "*.lua" 2>/dev/null | sort')
    local files = {}
    if pipe then
        for line in pipe:lines() do files[#files + 1] = line end
        pipe:close()
    end

    T.assert_true(#files >= 2,
        "the scan found " .. #files .. " files under kernel/cond -- a glob that returns "
        .. "nothing would pass this test vacuously")
    T.assert_true(T.table_contains(files, "sentinel/kernel/cond/init.lua"),
        "the scan must cover the predicate module itself")
    T.assert_true(T.table_contains(files, "sentinel/kernel/cond/fraction.lua"),
        "the scan must cover the boundary module itself")

    local offenders = {}
    for _, path in ipairs(files) do
        local handle = io.open(path, "r")
        if handle then
            local line_number = 0
            for line in handle:lines() do
                line_number = line_number + 1
                -- Whole-line comments only, matching tests/kernel/audit_scope.lua's rule:
                -- stripping a trailing comment correctly means knowing whether the `--`
                -- sits inside a string, and a lint that guesses trades a clear false
                -- positive for a silent false negative.
                if not line:match("^%s*%-%-")
                    and (line:match("[/%*]%s*100") or line:match("100%s*[/%*]")) then
                    offenders[#offenders + 1] = path .. ":" .. line_number .. "  " .. line
                end
            end
            handle:close()
        end
    end

    -- The invariant is CONFINEMENT, not a head count: fraction.lua legitimately mentions
    -- the factor more than once (the conversion itself, and the "did you mean 0.3?" hint
    -- in the threshold error). What must never happen is a second file learning it.
    T.assert_true(#offenders >= 1,
        "the scan found no scale factor at all -- fraction.lua contains one by construction, "
        .. "so zero findings means the scan itself is broken, not that the tree is clean")
    for _, offender in ipairs(offenders) do
        T.assert_true(offender:find("cond/fraction%.lua") ~= nil,
            "every scale factor under kernel/cond must live in the boundary module; found: "
            .. offender)
    end
end

-- ============================================================================
-- GUARDS THAT MUTATION TESTING FOUND UNTESTED
-- ============================================================================
--
-- Every case below exists because a mutant SURVIVED the suite above. They are not
-- speculative hardening: each one names a specific edit that used to pass.

--- `available` is the AUTHORITY, not a hint. Deleting the availability gate in `field`
--- survived the whole suite, because no fixture ever put a value next to an
--- `available = false`. If a future sensor ever leaves a stale vital behind when a handle
--- dies mid-capture, this is what stops the predicate believing it.
function M.test_a_value_sitting_next_to_available_false_is_still_unreadable()
    local cond = Cond.bind(snap({
        ["player.available"] = false,
        ["player.health_pct"] = 0.10,  -- stale: describes a unit that is no longer readable
        ["player.in_combat"] = true,
        ["player.level"] = 70,
    }))
    T.assert_equal(cond.health_below(0.30), Truth.Unknown,
        "a vital next to available=false describes a unit we could not confirm -- Unknown, "
        .. "not a confident True")
    T.assert_equal(cond.in_combat(), Truth.Unknown, "same for a nullable boolean")
    T.assert_equal(cond.level_at_least(70), Truth.Unknown, "same for a scalar")
end

--- Invariant 2: predicates take symbolic refs, never handles -- and never a raw key
--- prefix either, which would let a caller read any unit tier it could spell.
function M.test_a_unit_ref_that_is_not_symbolic_raises()
    local cond = healthy_player()
    T.assert_false(pcall(cond.unit_available, "player"),
        "a raw snapshot prefix is not a symbolic ref")
    T.assert_false(pcall(cond.unit_available, nil), "nil is not a unit ref")
    T.assert_false(pcall(cond.unit_available, { object = {} }),
        "a handle-shaped table is exactly what a ref exists to keep out")
    T.assert_true(pcall(cond.unit_available, Cond.UNIT_PLAYER), "the symbolic ref works")
end

--- The mirror of the fraction guard, and the reason it must be SCOPED: someone writing
--- `level_at_least(0.7)` meaning "70" is making the same mistake in the other direction.
function M.test_a_fractional_level_threshold_raises()
    local cond = healthy_player()
    T.assert_false(pcall(cond.level_at_least, 0.7), "0.7 is not a level")
    T.assert_false(pcall(cond.level_at_least, 0), "there is no level 0")
    T.assert_false(pcall(cond.level_at_least, -1), "there is no negative level")
    T.assert_false(pcall(cond.target_level_at_least, 70.5), "levels are integers")
    T.assert_true(pcall(cond.level_at_least, 70), "70 is a level")
end

function M.test_a_negative_or_non_numeric_range_raises()
    local cond = healthy_player()
    T.assert_false(pcall(cond.target_within, -5), "a negative distance is not a range")
    T.assert_false(pcall(cond.target_within, "30"), "a string is not a range")
    T.assert_true(pcall(cond.target_within, 0), "zero yards is a legal, if strict, range")
end

--- HONEST LIMIT, asserted rather than claimed.
---
--- LuaJIT fires `__newindex` only for keys ABSENT from the table, so a metatable can stop
--- a predicate being ADDED but not one being OVERWRITTEN. kernel/snapshot.lua documents
--- the identical limitation for its read side and declines to pretend otherwise; this does
--- the same rather than shipping a "sealed" namespace that is not.
---
--- What contains the gap is lifetime, not the metatable: `Cond.bind` builds a fresh
--- namespace from the frozen snapshot every tick, so an overwrite survives exactly one
--- tick and cannot persist into the next decision.
function M.test_adding_a_predicate_at_runtime_raises()
    local cond = healthy_player()
    T.assert_false(pcall(function() cond.brand_new = function() end end),
        "adding a predicate at runtime must raise")
end

function M.test_an_overwritten_predicate_does_not_survive_the_next_bind()
    local cond = healthy_player({ ["player.health_pct"] = 1.0 })
    -- The limit: LuaJIT cannot intercept this, and asserting that it raises would be a
    -- test asserting a guarantee the language does not provide.
    cond.health_below = function() return Truth.True end
    T.assert_equal(cond.health_below(0.30), Truth.True, "the overwrite does take effect")

    local next_tick = healthy_player({ ["player.health_pct"] = 1.0 })
    T.assert_equal(next_tick.health_below(0.30), Truth.False,
        "but the next bind rebuilds the namespace, so the patch cannot outlive one tick")
end

--- Ties the predicates to the boundary module rather than to a copy of its numbers.
function M.test_the_predicates_use_the_shared_boundary_module()
    T.assert_equal(Cond.FRACTION, Fraction,
        "kernel/cond must expose the very boundary module it validates through, so a "
        .. "second private copy of the pin cannot drift from it")
end

return M
