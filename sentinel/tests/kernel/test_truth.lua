-- tests/kernel/test_truth.lua
-- The Truth tri-state and its Kleene combinators (ADR 07 §5.1.2, ADR 08 §8.4).
--
-- Individual `test*` functions rather than a `run()` aggregator ON PURPOSE: the offline
-- runner counts a `run()` suite as ONE unit, which hides how many cases actually exist.
-- Phase 4b Deliverable 0 was bitten by exactly that.

local Truth = require("kernel/truth")
local T = require("tests/test_util")

local M = {}

-- ============================================================================
-- REPRESENTATION -- the whole point is that this is NOT a boolean and NOT nil
-- ============================================================================

--- ADR 07 §5.1.2: "the failed state is truthy in Lua". A tri-state stored as
--- true/false/nil collapses Unknown onto False at the first `if`, which is the
--- fail-open this type exists to kill. So none of the three may BE a boolean or nil.
function M.test_truth_values_are_neither_boolean_nor_nil()
    for _, case in ipairs({
        { name = "True", value = Truth.True },
        { name = "False", value = Truth.False },
        { name = "Unknown", value = Truth.Unknown },
    }) do
        T.assert_true(case.value ~= nil, "Truth." .. case.name .. " must not be nil")
        T.assert_true(type(case.value) ~= "boolean",
            "Truth." .. case.name .. " must not be a boolean underneath")
    end
end

function M.test_the_three_values_are_distinct_singletons()
    T.assert_true(Truth.True ~= Truth.False, "True and False must differ")
    T.assert_true(Truth.True ~= Truth.Unknown, "True and Unknown must differ")
    T.assert_true(Truth.False ~= Truth.Unknown, "False and Unknown must differ")
    -- Identity, not structural equality: two Unknowns from different call sites are the
    -- same Unknown, so `==` is a safe test everywhere.
    T.assert_equal(Truth.of(nil), Truth.Unknown, "Truth.of(nil) must be THE Unknown singleton")
end

--- A careless `truth.value` or `truth.ok` must not quietly read nil and route the caller
--- down a plausible branch. Field access is a mistake, so it raises.
function M.test_field_access_raises_rather_than_returning_nil()
    local ok = pcall(function() return Truth.Unknown.value end)
    T.assert_false(ok, "reading a field off a Truth must raise, not yield nil")
end

function M.test_truth_values_are_immutable()
    local ok = pcall(function() Truth.Unknown.value = true end)
    T.assert_false(ok, "a Truth singleton must not be mutable")
end

--- Diagnostics and blocked_reason strings have to be able to name the value.
function M.test_truth_values_are_printable()
    T.assert_equal(tostring(Truth.True), "Truth.True", "True must print its name")
    T.assert_equal(tostring(Truth.False), "Truth.False", "False must print its name")
    T.assert_equal(tostring(Truth.Unknown), "Truth.Unknown", "Unknown must print its name")
end

-- ============================================================================
-- CONSTRUCTION
-- ============================================================================

function M.test_of_maps_booleans_and_nil()
    T.assert_equal(Truth.of(true), Truth.True, "true maps to Truth.True")
    T.assert_equal(Truth.of(false), Truth.False, "false maps to Truth.False")
    T.assert_equal(Truth.of(nil), Truth.Unknown, "nil maps to Truth.Unknown -- unreadable is not false")
end

--- A Truth passed back through `of` is idempotent, so wrapping twice is harmless.
function M.test_of_is_idempotent_on_truth_values()
    T.assert_equal(Truth.of(Truth.Unknown), Truth.Unknown, "of(Unknown) is Unknown")
    T.assert_equal(Truth.of(Truth.True), Truth.True, "of(True) is True")
end

--- Anything else is a programming error, not data to coerce. A number or string
--- reaching here means a predicate returned raw SDK output without deciding.
function M.test_of_rejects_non_boolean_values()
    T.assert_false(pcall(Truth.of, 0), "of(0) must raise -- 0 is truthy in Lua and means nothing here")
    T.assert_false(pcall(Truth.of, "yes"), "of(string) must raise")
end

function M.test_is_recognises_only_truth_values()
    T.assert_true(Truth.is(Truth.Unknown), "Unknown is a Truth")
    T.assert_false(Truth.is(true), "a boolean is not a Truth")
    T.assert_false(Truth.is(nil), "nil is not a Truth")
    T.assert_false(Truth.is({}), "an arbitrary table is not a Truth")
end

-- ============================================================================
-- KLEENE LOGIC -- the part a boolean port silently gets wrong
-- ============================================================================

--- False DOMINATES conjunction. `and_(False, Unknown)` is False, not Unknown: one
--- definitely-unsatisfied conjunct settles the whole thing regardless of what the
--- unreadable one would have said. Collapsing this to Unknown would block a decision
--- that is actually knowable.
function M.test_and_is_kleene()
    T.assert_equal(Truth.and_(Truth.True, Truth.True), Truth.True, "T and T = T")
    T.assert_equal(Truth.and_(Truth.True, Truth.False), Truth.False, "T and F = F")
    T.assert_equal(Truth.and_(Truth.False, Truth.False), Truth.False, "F and F = F")

    T.assert_equal(Truth.and_(Truth.False, Truth.Unknown), Truth.False,
        "F and U = F -- a known-false conjunct settles it")
    T.assert_equal(Truth.and_(Truth.Unknown, Truth.False), Truth.False,
        "U and F = F -- order must not matter")
    T.assert_equal(Truth.and_(Truth.True, Truth.Unknown), Truth.Unknown,
        "T and U = U -- the unreadable conjunct still decides")
    T.assert_equal(Truth.and_(Truth.Unknown, Truth.Unknown), Truth.Unknown, "U and U = U")
end

--- True dominates disjunction, symmetrically.
function M.test_or_is_kleene()
    T.assert_equal(Truth.or_(Truth.False, Truth.False), Truth.False, "F or F = F")
    T.assert_equal(Truth.or_(Truth.True, Truth.False), Truth.True, "T or F = T")

    T.assert_equal(Truth.or_(Truth.True, Truth.Unknown), Truth.True,
        "T or U = T -- a known-true disjunct settles it")
    T.assert_equal(Truth.or_(Truth.Unknown, Truth.True), Truth.True,
        "U or T = T -- order must not matter")
    T.assert_equal(Truth.or_(Truth.False, Truth.Unknown), Truth.Unknown,
        "F or U = U -- the unreadable disjunct still decides")
    T.assert_equal(Truth.or_(Truth.Unknown, Truth.Unknown), Truth.Unknown, "U or U = U")
end

--- Negating "I cannot tell" yields "I cannot tell". A boolean `not_` turns Unknown into
--- its opposite, inventing certainty out of ignorance.
function M.test_not_preserves_unknown()
    T.assert_equal(Truth.not_(Truth.True), Truth.False, "not T = F")
    T.assert_equal(Truth.not_(Truth.False), Truth.True, "not F = T")
    T.assert_equal(Truth.not_(Truth.Unknown), Truth.Unknown,
        "not U = U -- negation must never manufacture certainty")
end

function M.test_and_or_accept_more_than_two_operands()
    T.assert_equal(Truth.and_(Truth.True, Truth.True, Truth.False), Truth.False, "variadic and_")
    T.assert_equal(Truth.or_(Truth.False, Truth.False, Truth.True), Truth.True, "variadic or_")
    T.assert_equal(Truth.and_(Truth.True, Truth.Unknown, Truth.True), Truth.Unknown,
        "one Unknown among Trues carries")
end

--- Identity elements, so folding an empty condition list is well defined.
function M.test_empty_conjunction_and_disjunction()
    T.assert_equal(Truth.and_(), Truth.True, "empty and_ is vacuously True")
    T.assert_equal(Truth.or_(), Truth.False, "empty or_ is vacuously False")
end

--- Combinators are part of the type, so they refuse raw booleans: a predicate that
--- forgot to return a Truth must fail at the seam, not be silently coerced.
function M.test_combinators_reject_raw_booleans()
    T.assert_false(pcall(Truth.and_, true, Truth.True), "and_ must reject a raw boolean")
    T.assert_false(pcall(Truth.or_, Truth.False, false), "or_ must reject a raw boolean")
    T.assert_false(pcall(Truth.not_, true), "not_ must reject a raw boolean")
end

-- ============================================================================
-- UNKNOWN POLICY -- ADR 07 §5.1.2, adjacently tagged {type, payload}
-- ============================================================================

--- Known values ignore the policy entirely: policy only governs Unknown.
function M.test_known_values_resolve_regardless_of_policy()
    for _, policy in ipairs({
        Truth.Policy.Block, Truth.Policy.TreatFalse, Truth.Policy.TreatTrue,
    }) do
        T.assert_equal(Truth.resolve(Truth.True, policy), true, "True resolves true")
        T.assert_equal(Truth.resolve(Truth.False, policy), false, "False resolves false")
    end
end

function M.test_treat_false_proceeds_as_unsatisfied()
    local decision, reason = Truth.resolve(Truth.Unknown, Truth.Policy.TreatFalse)
    T.assert_equal(decision, false, "TreatFalse resolves Unknown to false")
    T.assert_nil(reason, "TreatFalse is a decision, not a deferral")
end

--- The fail-open direction. It must work, and it must announce itself every time.
function M.test_treat_true_resolves_open_but_always_emits_a_diagnostic()
    local seen = {}
    local prev = Truth.on_diagnostic
    Truth.on_diagnostic = function(d) seen[#seen + 1] = d end

    local decision = Truth.resolve(Truth.Unknown, Truth.Policy.TreatTrue)

    Truth.on_diagnostic = prev
    T.assert_equal(decision, true, "TreatTrue resolves Unknown to true")
    T.assert_equal(#seen, 1, "TreatTrue on Unknown must emit exactly one diagnostic")
end

--- ...and it must NOT emit when the value was knowable: a diagnostic on every call
--- would be noise, and noise gets filtered, which is how fail-open goes unnoticed.
function M.test_treat_true_is_silent_on_known_values()
    local count = 0
    local prev = Truth.on_diagnostic
    Truth.on_diagnostic = function() count = count + 1 end

    Truth.resolve(Truth.True, Truth.Policy.TreatTrue)
    Truth.resolve(Truth.False, Truth.Policy.TreatTrue)

    Truth.on_diagnostic = prev
    T.assert_equal(count, 0, "TreatTrue must be silent when nothing was unknown")
end

function M.test_block_refuses_to_decide_and_names_a_reason()
    local decision, reason = Truth.resolve(Truth.Unknown, Truth.Policy.Block)
    T.assert_nil(decision, "Block must not hand back a decision")
    T.assert_equal(reason, "blocked", "Block must name itself as the blocked_reason")
end

function M.test_defer_yields_without_deciding()
    local decision, reason = Truth.resolve(Truth.Unknown, Truth.Policy.Defer(30))
    T.assert_nil(decision, "Defer must not hand back a decision")
    T.assert_equal(reason, "defer", "Defer must say it is yielding, not blocking")
end

--- "TreatTrue is never a default" -- so there IS no default. Omitting the policy is a
--- programming error, not an invitation to pick one.
function M.test_resolve_requires_an_explicit_policy()
    T.assert_false(pcall(Truth.resolve, Truth.Unknown),
        "resolve without a policy must raise -- every call site declares its own")
    T.assert_false(pcall(Truth.resolve, Truth.Unknown, { type = "Whatever" }),
        "an unrecognised policy must raise rather than fall through to a default")
end

function M.test_policies_are_adjacently_tagged()
    -- Same wire shape as ADR 07's UnknownPolicy, so the Rust side and this side agree.
    T.assert_equal(Truth.Policy.Block.type, "Block", "Block carries its tag")
    T.assert_equal(Truth.Policy.TreatTrue.type, "TreatTrue", "TreatTrue carries its tag")
    local defer = Truth.Policy.Defer(60)
    T.assert_equal(defer.type, "Defer", "Defer carries its tag")
    T.assert_equal(defer.payload.budget_ticks, 60, "Defer carries its budget in the payload")
end

-- ============================================================================
-- DEFER BUDGET -- "after unknown_budget ticks escalates to Block"
-- ============================================================================

function M.test_defer_escalates_to_block_once_the_budget_is_spent()
    local gate = Truth.gate(Truth.Policy.Defer(2))

    local _, r1 = gate:decide(Truth.Unknown)
    T.assert_equal(r1, "defer", "first unknown tick defers")
    local _, r2 = gate:decide(Truth.Unknown)
    T.assert_equal(r2, "defer", "second unknown tick defers")

    local d3, r3 = gate:decide(Truth.Unknown)
    T.assert_nil(d3, "an exhausted budget still refuses to decide")
    T.assert_equal(r3, "blocked", "a spent Defer budget escalates to Block, it does not fail open")
end

--- A knowable answer in between resets the budget: the budget counts CONSECUTIVE
--- unreadable ticks, not lifetime ones. Otherwise a long-running gate eventually blocks
--- on data that has been readable all along.
function M.test_a_known_answer_resets_the_defer_budget()
    local gate = Truth.gate(Truth.Policy.Defer(2))

    gate:decide(Truth.Unknown)
    gate:decide(Truth.Unknown)
    T.assert_equal(gate:decide(Truth.True), true, "a readable tick decides normally")

    local _, reason = gate:decide(Truth.Unknown)
    T.assert_equal(reason, "defer", "the budget must have reset after a readable tick")
end

function M.test_gate_passes_through_non_defer_policies()
    local blocking = Truth.gate(Truth.Policy.Block)
    local _, reason = blocking:decide(Truth.Unknown)
    T.assert_equal(reason, "blocked", "a Block gate blocks immediately, with no budget")

    local open = Truth.gate(Truth.Policy.TreatFalse)
    T.assert_equal(open:decide(Truth.Unknown), false, "a TreatFalse gate decides false")
end

return M
