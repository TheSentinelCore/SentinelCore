-- tests/kernel/test_intent_queue.lua
-- ADR 08 §3.2: "Plugins never call core.cast / core.input.* directly. They emit intents;
-- the kernel dedupes, gates (GCD / range / LoS / facing / rate), logs, and commits."
--
-- Justified independently by ADR 08 §2.6: "core.input.cast_target_spell performs ZERO
-- validation -- no range, no facing, no ready check; it only sends a packet. That is
-- exactly the gap the commit stage exists to fill."
--
-- PHASE 1 SCOPE: the structure and the commit stage's gate hooks. This queue is
-- deliberately NOT wired to real casting -- that is Phase 2/3, after the ControlBroker
-- exists to issue the leases that authorize an intent in the first place.
--
-- The behaviour under test that matters most is FAIL-CLOSED REFUSAL. ADR 08 §12 on
-- LazyBot: "GrindingProfile.LoadFile is eight independent try {} catch {} blocks with
-- EMPTY CATCH BODIES, each falling back to a hardcoded default, so a profile can be 90%
-- broken and still 'load'." Nothing in this queue may drop an intent silently. Every
-- rejection carries a named reason and is observable.

local IntentQueue = require("kernel/intent_queue")
local Snapshot = require("kernel/snapshot")
local T = require("tests/test_util")

local M = {}

--- A queue with a pass-through "cast" executor already registered.
--- Without one, EVERY intent is correctly refused with `no_executor` (that is the
--- fail-closed contract, asserted separately below), which would make the dedupe and
--- ordering assertions below vacuous.
local function q()
    local queue = IntentQueue:new()
    queue:register_executor("cast", function() return true end)
    return queue
end

local function cast(overrides)
    local intent = {
        type = "cast",
        owner = "test.rotation",
        band = 55,
        payload = { spell_id = 116, target = "target" },
    }
    for k, v in pairs(overrides or {}) do intent[k] = v end
    return intent
end

local function commit(queue, snap)
    return queue:commit(snap or Snapshot.empty(1))
end

-- ---------------------------------------------------------------------------
-- Submission
-- ---------------------------------------------------------------------------

function M.test_submit_accepts_a_well_formed_intent()
    local queue = q()
    local ok, err = queue:submit(cast())
    T.assert_true(ok, "a well-formed intent must be accepted: " .. tostring(err))
    T.assert_equal(queue:pending_count(), 1)
end

--- A malformed intent is refused AT SUBMISSION with a reason. It never reaches commit.
function M.test_submit_refuses_malformed_intents_with_named_reasons()
    local queue = q()
    -- Built explicitly rather than via cast{}: `pairs` skips nil values, so an override
    -- table cannot express "remove this field".
    local cases = {
        { { owner = "o", band = 50 }, "missing_type" },
        { { type = "cast", band = 50 }, "missing_owner" },
        { { type = "cast", owner = "o" }, "missing_band" },
        { { type = "cast", owner = "o", band = 500 }, "band_out_of_range" },
        { { type = "cast", owner = "o", band = -1 }, "band_out_of_range" },
        { "not even a table", "not_a_table" },
    }
    for _, case in ipairs(cases) do
        local ok, reason = queue:submit(case[1])
        T.assert_false(ok, "malformed intent must be refused")
        T.assert_equal(reason, case[2])
    end
    T.assert_equal(queue:pending_count(), 0, "nothing malformed may sit in the queue")
end

-- ---------------------------------------------------------------------------
-- Dedupe
-- ---------------------------------------------------------------------------

--- Two plugins asking for the same thing in one tick is ONE action, not two packets.
function M.test_identical_intents_dedupe_within_a_tick()
    local queue = q()
    queue:submit(cast())
    queue:submit(cast())
    queue:submit(cast({ owner = "other.rotation" }))

    local report = commit(queue)
    T.assert_equal(#report.committed, 1, "the same action must commit once")
    T.assert_equal(#report.deduped, 2, "the duplicates must be reported, not vanish")
end

--- ...and the HIGHER band wins the dedupe, because that is the one with authority.
function M.test_dedupe_keeps_the_highest_band()
    local queue = q()
    queue:submit(cast({ owner = "rotation", band = 55 }))
    queue:submit(cast({ owner = "survival", band = 80 }))

    local report = commit(queue)
    T.assert_equal(#report.committed, 1)
    T.assert_equal(report.committed[1].owner, "survival", "the higher band must own the surviving intent")
end

function M.test_different_intents_do_not_dedupe()
    local queue = q()
    queue:submit(cast({ payload = { spell_id = 116, target = "target" } }))
    queue:submit(cast({ payload = { spell_id = 133, target = "target" } }))

    local report = commit(queue)
    T.assert_equal(#report.committed, 2)
end

-- ---------------------------------------------------------------------------
-- Ordering
-- ---------------------------------------------------------------------------

--- ADR 08 §6.2 bands: safety outranks survival outranks combat outranks the goal.
function M.test_commit_runs_in_descending_band_order()
    local queue = q()
    queue:submit(cast({ owner = "goal", band = 35, payload = { spell_id = 1 } }))
    queue:submit(cast({ owner = "safety", band = 95, payload = { spell_id = 2 } }))
    queue:submit(cast({ owner = "combat", band = 55, payload = { spell_id = 3 } }))

    local report = commit(queue)
    T.assert_equal(report.committed[1].owner, "safety")
    T.assert_equal(report.committed[2].owner, "combat")
    T.assert_equal(report.committed[3].owner, "goal")
end

--- Submission order breaks ties, so a tick is deterministic and replayable.
function M.test_equal_bands_preserve_submission_order()
    local queue = q()
    queue:submit(cast({ owner = "first", payload = { spell_id = 1 } }))
    queue:submit(cast({ owner = "second", payload = { spell_id = 2 } }))

    local report = commit(queue)
    T.assert_equal(report.committed[1].owner, "first")
    T.assert_equal(report.committed[2].owner, "second")
end

-- ---------------------------------------------------------------------------
-- Gates
-- ---------------------------------------------------------------------------

function M.test_a_gate_can_reject_with_a_named_reason()
    local queue = q()
    queue:add_gate("range", function(intent)
        if intent.payload.spell_id == 116 then return false, "out_of_range" end
        return true
    end)
    queue:submit(cast())

    local report = commit(queue)
    T.assert_equal(#report.committed, 0)
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].gate, "range")
    T.assert_equal(report.rejected[1].reason, "out_of_range")
end

--- A gate that rejects without saying why still produces a named record. "It just didn't
--- happen" is the failure mode this whole design exists to prevent.
function M.test_a_reasonless_rejection_still_gets_a_name()
    local queue = q()
    queue:add_gate("mystery", function() return false end)
    queue:submit(cast())

    local report = commit(queue)
    T.assert_equal(report.rejected[1].reason, "gate_rejected",
        "a gate that gives no reason must still yield an attributable one")
end

function M.test_gates_receive_the_frozen_snapshot()
    local queue = q()
    local seen_health = nil
    queue:add_gate("vitals", function(_intent, snap)
        seen_health = snap:get("player.health_pct")
        return true
    end)
    queue:submit(cast())

    local b = Snapshot.builder({ tick_index = 3 })
    b:put("player.health_pct", 0.42)
    commit(queue, b:freeze())

    T.assert_near(seen_health, 0.42, 0.0001, "gates must evaluate against the tick's frozen snapshot")
end

--- FAIL CLOSED. A gate that throws must not let the intent through -- the whole point of
--- the commit stage is that core.input validates nothing (ADR 08 §2.6).
function M.test_a_throwing_gate_rejects_the_intent_rather_than_admitting_it()
    local queue = q()
    queue:add_gate("broken", function() error("gate exploded", 0) end)
    queue:submit(cast())

    local report = commit(queue)
    T.assert_equal(#report.committed, 0, "a broken gate must never fail open")
    T.assert_equal(report.rejected[1].gate, "broken")
    T.assert_equal(report.rejected[1].reason, "gate_error")
end

function M.test_first_failing_gate_short_circuits()
    local queue = q()
    local second_ran = false
    queue:add_gate("first", function() return false, "nope" end)
    queue:add_gate("second", function() second_ran = true; return true end)
    queue:submit(cast())

    commit(queue)
    T.assert_false(second_ran, "no point evaluating further gates once one has refused")
end

-- ---------------------------------------------------------------------------
-- Executors -- fail closed
-- ---------------------------------------------------------------------------

--- The LazyBot lesson, encoded: an intent with nowhere to go is REFUSED LOUDLY.
function M.test_intent_with_no_executor_is_refused_not_dropped()
    local queue = q()
    queue:submit(cast({ type = "teleport_to_moon" }))

    local report = commit(queue)
    T.assert_equal(#report.committed, 0)
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].reason, "no_executor",
        "an unhandled intent type must be named, never silently dropped")
end

function M.test_registered_executor_receives_the_intent_and_snapshot()
    local queue = q()
    local received = nil
    queue:register_executor("cast", function(intent, snap)
        received = { intent = intent, tick = snap:tick_index() }
        return true
    end)
    queue:submit(cast())

    local report = commit(queue, Snapshot.empty(9))
    T.assert_equal(#report.committed, 1)
    T.assert_equal(received.intent.payload.spell_id, 116)
    T.assert_equal(received.tick, 9)
end

--- A throwing executor is a fault, not a success.
function M.test_a_throwing_executor_is_reported_as_failed()
    local queue = q()
    queue:register_executor("cast", function() error("cast blew up", 0) end)
    queue:submit(cast())

    local report = commit(queue)
    T.assert_equal(#report.committed, 0)
    T.assert_equal(#report.failed, 1)
    T.assert_equal(report.failed[1].reason, "executor_error")
end

--- An executor returning false is a refusal it must be able to explain.
function M.test_executor_can_refuse_with_a_reason()
    local queue = q()
    queue:register_executor("cast", function() return false, "spell_not_ready" end)
    queue:submit(cast())

    local report = commit(queue)
    T.assert_equal(#report.failed, 1)
    T.assert_equal(report.failed[1].reason, "spell_not_ready")
end

-- ---------------------------------------------------------------------------
-- Generation check (ControlBroker seam, Phase 2)
-- ---------------------------------------------------------------------------

--- ADR 08 §6.1: "Every lease carries a monotonic generation, re-checked at the commit
--- point. This closes the revocation race where an intent emitted under a now-dead lease
--- still commits." The broker is Phase 2; the seam it plugs into is here now.
function M.test_a_stale_generation_is_rejected_at_commit()
    local queue = q()
    queue:set_generation_validator(function(intent)
        return intent.generation == 7
    end)
    queue:submit(cast({ generation = 6 }))
    queue:submit(cast({ generation = 7, payload = { spell_id = 999 } }))

    local report = commit(queue)
    T.assert_equal(#report.committed, 1)
    T.assert_equal(report.committed[1].generation, 7)
    T.assert_equal(report.rejected[1].reason, "stale_generation")
end

--- With no broker installed nothing is stale -- but the check is a real stage, not absent.
function M.test_without_a_validator_every_generation_passes()
    local queue = q()
    queue:submit(cast({ generation = 123 }))
    local report = commit(queue)
    T.assert_equal(#report.committed, 1)
end

-- ---------------------------------------------------------------------------
-- immediate flag
-- ---------------------------------------------------------------------------

--- ADR 08 §3.2: "an immediate = true flag on the intent, RESTRICTED TO LEASES AT BAND >= 70,
--- still routed through the same gates."
function M.test_immediate_is_refused_below_band_70()
    local queue = q()
    local ok, reason = queue:submit(cast({ immediate = true, band = 55 }))
    T.assert_false(ok, "immediate below band 70 must be refused at submission")
    T.assert_equal(reason, "immediate_requires_band_70")
end

function M.test_immediate_is_allowed_at_band_70_and_above()
    local queue = q()
    T.assert_true(queue:submit(cast({ immediate = true, band = 70 })))
    T.assert_true(queue:submit(cast({ immediate = true, band = 95, payload = { spell_id = 2 } })))
end

--- ...and it must still pass every gate. "Immediate" buys ordering, not impunity.
function M.test_immediate_intents_are_still_gated()
    local queue = q()
    queue:add_gate("range", function() return false, "out_of_range" end)
    queue:submit(cast({ immediate = true, band = 90 }))

    local report = commit(queue)
    T.assert_equal(#report.committed, 0, "immediate must not bypass gating")
    T.assert_equal(report.rejected[1].reason, "out_of_range")
end

-- ---------------------------------------------------------------------------
-- spell_queue band mapping (ADR 08 §6.3)
-- ---------------------------------------------------------------------------

--- The kernel does NOT own the bottom of the casting stack. It maps onto the injector's
--- documented convention: 7 is the interrupt slot, 1 is "everything you author", and 9 is
--- reserved for manual player input and must never be emitted.
function M.test_band_maps_onto_the_injector_spell_queue_convention()
    T.assert_equal(IntentQueue.spell_queue_priority(99), 7, "safety -> interrupt slot")
    T.assert_equal(IntentQueue.spell_queue_priority(90), 7)
    T.assert_equal(IntentQueue.spell_queue_priority(89), 7, "survival -> interrupt slot")
    T.assert_equal(IntentQueue.spell_queue_priority(70), 7)
    T.assert_equal(IntentQueue.spell_queue_priority(69), 1, "combat -> the authored value")
    T.assert_equal(IntentQueue.spell_queue_priority(50), 1)
    T.assert_equal(IntentQueue.spell_queue_priority(49), 1)
    T.assert_equal(IntentQueue.spell_queue_priority(0), 1)
end

function M.test_priority_9_is_never_emitted()
    for band = 0, 99 do
        T.assert_true(IntentQueue.spell_queue_priority(band) ~= 9,
            "band " .. band .. " must never map to 9 -- that slot is the player's")
    end
end

-- ---------------------------------------------------------------------------
-- Tick lifecycle
-- ---------------------------------------------------------------------------

--- The queue is per-tick. An intent that did not commit this tick does not linger into the
--- next one carrying a stale world view with it.
function M.test_commit_drains_the_queue()
    local queue = q()
    queue:submit(cast())
    commit(queue)
    T.assert_equal(queue:pending_count(), 0)

    local report = commit(queue)
    T.assert_equal(#report.committed, 0, "a second commit with nothing pending must be a clean no-op")
end

function M.test_commit_with_an_empty_queue_is_a_no_op()
    local report = commit(q())
    T.assert_equal(#report.committed, 0)
    T.assert_equal(#report.rejected, 0)
    T.assert_equal(#report.failed, 0)
end

return M
