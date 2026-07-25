-- tests/kernel/test_control_broker.lua
-- ADR 08 §6 -- the arbiter. Everything after Phase 2 depends on this being right.
--
-- The object-capability property (§6.1): "All game-affecting calls hang off the lease, not
-- off a global. Unauthorised action becomes STRUCTURALLY IMPOSSIBLE rather than merely
-- discouraged. Authority travels with the reference, no ambient authority."
--
-- The exit criterion from §12 is a literal test here:
--   test_exit_criterion_two_plugins_contend_for_movement_loser_keys_are_released
--
-- The safety property from §2.8 is the one that has a physical consequence in the game, so
-- it is asserted from four directions: on_revoke absent, on_revoke throwing, on_revoke
-- returning false, and TTL expiry with a wedged holder that never cooperates at all.

local ControlBroker = require("kernel/control_broker")
local Channel = ControlBroker.Channel
local MovementRelease = require("kernel/movement_release")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------

--- A recording `core.input` double. The broker's force-release must drive this.
local function make_input()
    local stopped = {}
    local input = {}
    for _, key in ipairs(MovementRelease.KEYS) do
        input[key .. "_stop"] = function() stopped[#stopped + 1] = key; return true end
        input[key .. "_start"] = function() end
    end
    return input, stopped
end

local function make_broker(opts)
    opts = opts or {}
    local input, stopped = make_input()
    local bus = EventBus:new(function() end)
    local broker = ControlBroker:new({
        event_bus = bus,
        input = input,
        cooldown_ticks = opts.cooldown_ticks,
    })
    broker:arbitrate(1) -- establish tick 1
    return broker, stopped, bus
end

--- A dummy plugin, in the ADR's sense: an owner id, a band, and a revocation record.
local function make_plugin(id, band, offset)
    return {
        id = id,
        band = band,
        offset = offset or 0,
        revocations = {},
        on_revoke = function(self, reason)
            self.revocations[#self.revocations + 1] = reason
        end,
    }
end

local function acquire(broker, plugin, channels, ttl)
    local request = {
        owner = plugin.id,
        band = plugin.band,
        offset = plugin.offset,
        ttl_ticks = ttl or 5,
        on_revoke = function(reason) plugin.on_revoke(plugin, reason) end,
    }
    if type(channels) == "table" then request.channels = channels else request.channel = channels end
    return broker:acquire(request)
end

-- ---------------------------------------------------------------------------
-- Channels (ADR 08 §2.1 / §2.2)
-- ---------------------------------------------------------------------------

function M.test_exactly_seven_channels()
    local expected = {
        "MOVEMENT", "FACING", "CASTING", "TARGETING", "INTERACTION", "ITEMS", "MODAL_UI",
    }
    T.assert_equal(#ControlBroker.CHANNELS, 7)
    for _, name in ipairs(expected) do
        T.assert_not_nil(Channel[name], name .. " must be a channel")
    end
end

--- ADR 08 §2.1: "rg -ni camera over the entire docs tree returns only an unrelated WMO
--- collision flag. There is no camera control API." A CAMERA channel would be a lease
--- nothing could ever act on.
function M.test_there_is_no_camera_channel()
    T.assert_nil(Channel.CAMERA, "no camera API exists in Sylvanas -- there must be no CAMERA channel")
    for _, name in ipairs(ControlBroker.CHANNELS) do
        T.assert_false(name == "CAMERA", "CAMERA must not appear in the channel set")
    end
end

function M.test_an_unknown_channel_is_refused_by_name()
    local broker = make_broker()
    local lease, reason = broker:acquire({
        channel = "TELEPATHY", owner = "p", band = "GOAL", ttl_ticks = 2,
    })
    T.assert_nil(lease)
    T.assert_equal(reason, "unknown_channel")
end

-- ---------------------------------------------------------------------------
-- Acquisition basics
-- ---------------------------------------------------------------------------

function M.test_acquire_a_free_channel_succeeds()
    local broker = make_broker()
    local plugin = make_plugin("activity.grind", "GOAL")
    local caretaker = acquire(broker, plugin, Channel.MOVEMENT)

    T.assert_not_nil(caretaker, "a free channel must be grantable")
    T.assert_true(caretaker:is_valid())
    T.assert_equal(caretaker:owner(), "activity.grind")
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.grind")
end

function M.test_who_owns_reports_nil_for_a_free_channel()
    local broker = make_broker()
    T.assert_nil(broker:who_owns(Channel.CASTING))
end

--- ADR 08 §6.2 -- bands are named. A bare integer is the failure mode the band table exists
--- to prevent, so the broker refuses one even though ADR §6.1's sample sketches
--- `priority = 60`. §6.2 is the more specific statement: "the manifest declares
--- { band = "COMBAT", offset = 0 }".
function M.test_a_bare_integer_priority_is_refused()
    local broker = make_broker()
    local lease, reason = broker:acquire({
        channel = Channel.CASTING, owner = "p", priority = 60, ttl_ticks = 2,
    })
    T.assert_nil(lease)
    T.assert_equal(reason, "band_must_be_named")
end

function M.test_the_lease_carries_the_resolved_integer_priority()
    local broker = make_broker()
    local caretaker = acquire(broker, make_plugin("r", "COMBAT", 5), Channel.CASTING)
    T.assert_equal(caretaker:priority(), 55, "COMBAT+5 resolves to 55")
    T.assert_equal(caretaker:band(), "COMBAT")
end

function M.test_a_tier_that_may_not_hold_the_band_is_refused_by_name()
    local broker = make_broker()
    local lease, reason = broker:acquire({
        channel = Channel.MOVEMENT, owner = "amb", band = "SAFETY", tier = "ambient", ttl_ticks = 2,
    })
    T.assert_nil(lease)
    T.assert_equal(reason, "band_not_permitted_for_tier")
end

function M.test_missing_owner_is_refused()
    local broker = make_broker()
    local lease, reason = broker:acquire({ channel = Channel.MOVEMENT, band = "GOAL", ttl_ticks = 2 })
    T.assert_nil(lease)
    T.assert_equal(reason, "missing_owner")
end

function M.test_ttl_is_required()
    local broker = make_broker()
    local lease, reason = broker:acquire({ channel = Channel.MOVEMENT, owner = "p", band = "GOAL" })
    T.assert_nil(lease, "a lease with no TTL could be held forever by a wedged plugin")
    T.assert_equal(reason, "missing_ttl_ticks")
end

-- ---------------------------------------------------------------------------
-- Channel independence -- this is what buys kiting (ADR 08 §6.1)
-- ---------------------------------------------------------------------------

--- "This is what buys kiting: the rotation holds CASTING+TARGETING while the activity keeps
--- MOVEMENT and backpedals. The current fixed-priority module design cannot express that
--- at all."
function M.test_channels_arbitrate_independently()
    local broker = make_broker()
    local activity = make_plugin("activity.grind", "GOAL")
    local rotation = make_plugin("rotation.frost", "COMBAT")

    local a = acquire(broker, activity, Channel.MOVEMENT)
    local r = acquire(broker, rotation, { Channel.CASTING, Channel.TARGETING })

    T.assert_not_nil(a, "the activity must keep MOVEMENT")
    T.assert_not_nil(r, "the higher-band rotation must get CASTING+TARGETING")
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.grind")
    T.assert_equal(broker:who_owns(Channel.CASTING), "rotation.frost")
    T.assert_equal(#activity.revocations, 0,
        "holding a different channel is not a conflict -- no revocation may fire")
end

-- ---------------------------------------------------------------------------
-- Multi-channel atomicity
-- ---------------------------------------------------------------------------

--- "Partial acquisition is how you get two plugins each holding one channel and deadlocking
--- on the other."
function M.test_multi_channel_acquire_fails_atomically_with_no_partial_hold()
    local broker = make_broker()
    local incumbent = make_plugin("rotation.holder", "SURVIVAL") -- 70, outranks the challenger
    acquire(broker, incumbent, Channel.TARGETING)

    local challenger = make_plugin("rotation.challenger", "COMBAT") -- 50
    local caretaker, reason = acquire(broker, challenger, { Channel.CASTING, Channel.TARGETING })

    T.assert_nil(caretaker, "the request must fail as a whole")
    T.assert_equal(reason, "channel_held")
    T.assert_nil(broker:who_owns(Channel.CASTING),
        "CASTING must NOT be held -- a partial grant is the deadlock this rule prevents")
    T.assert_equal(broker:who_owns(Channel.TARGETING), "rotation.holder")
end

--- A failed multi-channel request must not revoke anything either -- a revocation is a side
--- effect, and an atomic failure has no side effects.
function M.test_a_failed_multi_channel_acquire_revokes_nothing()
    local broker = make_broker()
    local weak = make_plugin("activity.weak", "HOUSEKEEP")     -- 10, preemptible
    local strong = make_plugin("behavior.strong", "SAFETY")     -- 90, blocks
    acquire(broker, weak, Channel.MOVEMENT)
    acquire(broker, strong, Channel.CASTING)

    local challenger = make_plugin("rotation.mid", "COMBAT")    -- 50
    local caretaker = acquire(broker, challenger, { Channel.MOVEMENT, Channel.CASTING })

    T.assert_nil(caretaker)
    T.assert_equal(#weak.revocations, 0,
        "the preemptible channel must not be revoked when the request fails on another channel")
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.weak")
end

function M.test_multi_channel_acquire_grants_all_or_nothing_on_success()
    local broker = make_broker()
    local caretaker = acquire(broker, make_plugin("r", "COMBAT"),
        { Channel.CASTING, Channel.TARGETING, Channel.FACING })

    T.assert_not_nil(caretaker)
    for _, ch in ipairs({ Channel.CASTING, Channel.TARGETING, Channel.FACING }) do
        T.assert_equal(broker:who_owns(ch), "r", ch .. " must be held")
        T.assert_true(caretaker:has(ch))
    end
    T.assert_false(caretaker:has(Channel.MOVEMENT))
end

-- ---------------------------------------------------------------------------
-- Same-owner renewal (ADR 08 §6.1)
-- ---------------------------------------------------------------------------

--- "Re-acquire by the same owner is a RENEWAL, not a conflict." Getting this wrong causes
--- revocation thrash that looks like a scheduler bug.
function M.test_same_owner_reacquire_renews_without_firing_on_revoke()
    local broker = make_broker()
    local plugin = make_plugin("activity.grind", "GOAL")
    local first = acquire(broker, plugin, Channel.MOVEMENT, 3)
    local generation = first:generation()

    local second = acquire(broker, plugin, Channel.MOVEMENT, 3)

    T.assert_not_nil(second, "a renewal must succeed")
    T.assert_equal(#plugin.revocations, 0, "a renewal must NOT fire on_revoke")
    T.assert_equal(second:generation(), generation,
        "a renewal keeps the generation -- intents already emitted this tick stay valid")
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.grind")
end

function M.test_renewal_extends_the_ttl()
    local broker = make_broker({})
    local plugin = make_plugin("activity.grind", "GOAL")
    acquire(broker, plugin, Channel.MOVEMENT, 2) -- expires at tick 3

    broker:arbitrate(2)
    acquire(broker, plugin, Channel.MOVEMENT, 2) -- renewed at tick 2, now expires at tick 4
    broker:arbitrate(3)

    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.grind",
        "the renewal must have pushed the expiry out")
    T.assert_equal(#plugin.revocations, 0)
end

--- A renewal must not silently drop channels the owner already held.
function M.test_renewing_a_subset_does_not_release_the_rest()
    local broker = make_broker()
    local plugin = make_plugin("r", "COMBAT")
    acquire(broker, plugin, { Channel.CASTING, Channel.TARGETING })
    acquire(broker, plugin, Channel.CASTING)

    T.assert_equal(broker:who_owns(Channel.TARGETING), "r",
        "renewing CASTING must not quietly hand TARGETING back")
end

-- ---------------------------------------------------------------------------
-- THE EXIT CRITERION (ADR 08 §12 Phase 2)
-- ---------------------------------------------------------------------------

--- "Two dummy plugins contend for MOVEMENT; preempted holder's keys are force-released."
function M.test_exit_criterion_two_plugins_contend_for_movement_loser_keys_are_released()
    local broker, stopped = make_broker()

    -- Plugin A: the goal activity, running somewhere. Holds MOVEMENT at band GOAL (30).
    local grind = make_plugin("activity.grind", "GOAL")
    local held = acquire(broker, grind, Channel.MOVEMENT)
    T.assert_not_nil(held, "precondition: the activity holds MOVEMENT")
    T.assert_equal(#stopped, 0, "precondition: nothing has been force-stopped yet")

    -- Plugin B: the corpse-run safety net at band SAFETY (90). It wants MOVEMENT.
    local recover = make_plugin("behavior.corpse_run", "SAFETY")
    local pending, reason = acquire(broker, recover, Channel.MOVEMENT)

    -- The loser is revoked immediately...
    T.assert_equal(#grind.revocations, 1, "the lower-band holder must be revoked")
    T.assert_equal(grind.revocations[1], "preempted")
    T.assert_false(held:is_valid(), "the preempted caretaker must go inert at once")

    -- ...and its keys are force-released by the KERNEL, not by its cooperation.
    T.assert_equal(#stopped, #MovementRelease.KEYS,
        "every movement key must be force-released on MOVEMENT revocation, got " .. #stopped)

    -- ADR 08 §6.1 / the livelock guard: no same-tick handover.
    T.assert_nil(pending, "preemption must not hand the channel over inside the same tick")
    T.assert_equal(reason, "preemption_pending")
    T.assert_nil(broker:who_owns(Channel.MOVEMENT), "the channel is free but cooling")

    -- Next tick the winner takes it.
    broker:arbitrate(2)
    local won = acquire(broker, recover, Channel.MOVEMENT)
    T.assert_not_nil(won, "the preemptor must get the channel on the following tick")
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "behavior.corpse_run")
end

-- ---------------------------------------------------------------------------
-- Enforced revocation -- asserted from four directions (ADR 08 §2.8)
-- ---------------------------------------------------------------------------

--- The prompt's named requirement: a plugin whose on_revoke THROWS still ends up stopped.
function M.test_a_holder_whose_on_revoke_throws_is_still_force_stopped()
    local broker, stopped = make_broker()
    local caretaker = broker:acquire({
        channel = Channel.MOVEMENT, owner = "activity.buggy", band = "GOAL", ttl_ticks = 5,
        on_revoke = function() error("my on_revoke is broken", 0) end,
    })
    T.assert_not_nil(caretaker)

    local ok = pcall(function()
        return broker:acquire({
            channel = Channel.MOVEMENT, owner = "behavior.safety", band = "SAFETY", ttl_ticks = 5,
        })
    end)

    T.assert_true(ok, "a throwing on_revoke must not propagate out of acquire")
    T.assert_equal(#stopped, #MovementRelease.KEYS,
        "keys MUST still be released when on_revoke throws -- this is the entire point")
    T.assert_false(caretaker:is_valid(), "the lease is gone regardless of the callback failing")
    T.assert_nil(broker:who_owns(Channel.MOVEMENT))
end

--- No on_revoke at all is the same story.
function M.test_a_holder_with_no_on_revoke_is_still_force_stopped()
    local broker, stopped = make_broker()
    broker:acquire({ channel = Channel.MOVEMENT, owner = "activity.silent", band = "GOAL", ttl_ticks = 5 })
    broker:acquire({ channel = Channel.MOVEMENT, owner = "behavior.safety", band = "SAFETY", ttl_ticks = 5 })

    T.assert_equal(#stopped, #MovementRelease.KEYS,
        "an absent on_revoke must not leave the character running")
end

--- A holder that returns false -- i.e. declines -- does not get a veto.
function M.test_a_holder_that_declines_revocation_has_no_veto()
    local broker, stopped = make_broker()
    broker:acquire({
        channel = Channel.MOVEMENT, owner = "activity.stubborn", band = "GOAL", ttl_ticks = 5,
        on_revoke = function() return false end,
    })
    broker:acquire({ channel = Channel.MOVEMENT, owner = "behavior.safety", band = "SAFETY", ttl_ticks = 5 })

    T.assert_nil(broker:who_owns(Channel.MOVEMENT), "revocation is not a request")
    T.assert_equal(#stopped, #MovementRelease.KEYS)
end

--- Revoking a NON-movement channel must not stop the character. Releasing movement keys
--- because a CASTING lease expired would cancel the activity's travel for no reason.
function M.test_revoking_a_non_movement_channel_does_not_touch_movement_keys()
    local broker, stopped = make_broker()
    broker:acquire({ channel = Channel.CASTING, owner = "r.low", band = "GOAL", ttl_ticks = 5 })
    broker:acquire({ channel = Channel.CASTING, owner = "r.high", band = "SAFETY", ttl_ticks = 5 })

    T.assert_equal(#stopped, 0, "CASTING revocation must not release movement keys")
end

--- ...but a multi-channel lease that INCLUDED movement must release on revocation.
function M.test_revoking_a_multi_channel_lease_containing_movement_releases_keys()
    local broker, stopped = make_broker()
    broker:acquire({
        channels = { Channel.CASTING, Channel.MOVEMENT },
        owner = "activity.low", band = "GOAL", ttl_ticks = 5,
    })
    broker:acquire({ channel = Channel.CASTING, owner = "b.high", band = "SAFETY", ttl_ticks = 5 })

    T.assert_equal(#stopped, #MovementRelease.KEYS,
        "revoking any lease that held MOVEMENT must force-release, even via another channel")
end

-- ---------------------------------------------------------------------------
-- TTL (ADR 08 §6.1) -- authority reverts without the holder's cooperation
-- ---------------------------------------------------------------------------

--- "A plugin that faults mid-tick cannot permanently hold MOVEMENT. Authority reverts at
--- term end WITHOUT the holder's cooperation, which is exactly why a wedged holder cannot
--- deadlock the resource."
function M.test_ttl_expiry_frees_a_channel_from_a_wedged_holder()
    local broker, stopped = make_broker()
    -- A wedged holder: never renews, never releases, and its on_revoke throws.
    local caretaker = broker:acquire({
        channel = Channel.MOVEMENT, owner = "activity.wedged", band = "GOAL", ttl_ticks = 2,
        on_revoke = function() error("wedged", 0) end,
    })
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.wedged")

    broker:arbitrate(2)
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.wedged", "still inside its term")

    broker:arbitrate(3)
    T.assert_nil(broker:who_owns(Channel.MOVEMENT),
        "the lease must expire with zero cooperation from the holder")
    T.assert_false(caretaker:is_valid())
    T.assert_equal(#stopped, #MovementRelease.KEYS,
        "TTL expiry on MOVEMENT must force-release keys too -- a wedged holder is exactly the "
        .. "case where the character would otherwise keep running")
end

function M.test_ttl_expiry_fires_on_revoke_with_its_own_reason()
    local broker = make_broker()
    local plugin = make_plugin("activity.grind", "GOAL")
    acquire(broker, plugin, Channel.CASTING, 1)

    broker:arbitrate(2)
    T.assert_equal(#plugin.revocations, 1)
    T.assert_equal(plugin.revocations[1], "ttl_expired", "the reason must distinguish expiry from preemption")
end

function M.test_expiry_is_evaluated_on_arbitrate_not_lazily_on_acquire()
    local broker = make_broker()
    acquire(broker, make_plugin("a", "GOAL"), Channel.ITEMS, 1)
    broker:arbitrate(2)
    T.assert_nil(broker:who_owns(Channel.ITEMS),
        "ARBITRATE is where TTLs expire -- not on next contention")
end

-- ---------------------------------------------------------------------------
-- Release
-- ---------------------------------------------------------------------------

function M.test_release_frees_every_channel_of_the_lease()
    local broker = make_broker()
    local plugin = make_plugin("r", "COMBAT")
    local caretaker = acquire(broker, plugin, { Channel.CASTING, Channel.TARGETING })

    T.assert_true(broker:release(caretaker))
    T.assert_nil(broker:who_owns(Channel.CASTING))
    T.assert_nil(broker:who_owns(Channel.TARGETING))
    T.assert_false(caretaker:is_valid())
end

--- A voluntary release is the holder cooperating, so on_revoke is not a revocation event --
--- but movement keys still get released, because the holder is no longer authorised to hold
--- them down and we cannot verify that it let go.
function M.test_voluntary_release_of_movement_still_releases_keys()
    local broker, stopped = make_broker()
    local plugin = make_plugin("activity.grind", "GOAL")
    local caretaker = acquire(broker, plugin, Channel.MOVEMENT)

    broker:release(caretaker)
    T.assert_equal(#plugin.revocations, 0, "a voluntary release is not a revocation")
    T.assert_equal(#stopped, #MovementRelease.KEYS,
        "but the keys must not be left held by a lease that no longer exists")
end

function M.test_releasing_twice_is_a_no_op()
    local broker = make_broker()
    local caretaker = acquire(broker, make_plugin("r", "COMBAT"), Channel.CASTING)
    T.assert_true(broker:release(caretaker))
    T.assert_false(broker:release(caretaker), "a second release must report no-op, not throw")
end

function M.test_releasing_a_foreign_object_is_refused_not_fatal()
    local broker = make_broker()
    local ok, result = pcall(function() return broker:release({ not_a = "caretaker" }) end)
    T.assert_true(ok, "release must not throw on garbage input")
    T.assert_false(result)
end

-- ---------------------------------------------------------------------------
-- Caretaker vs lease (ADR 08 §6.1)
-- ---------------------------------------------------------------------------

--- "Plugins receive a per-tick wrapper whose `revoked` flag the kernel flips at tick end,
--- not the lease itself. A stashed reference becomes INERT rather than merely impolite."
function M.test_a_stashed_caretaker_from_tick_n_is_inert_in_tick_n_plus_1()
    local broker = make_broker()
    local plugin = make_plugin("activity.grind", "GOAL")
    local stashed = acquire(broker, plugin, Channel.MOVEMENT, 10)
    T.assert_true(stashed:is_valid(), "valid in the tick it was issued")

    broker:end_tick()
    broker:arbitrate(2)

    T.assert_false(stashed:is_valid(),
        "a caretaker stashed across the tick boundary must be inert")
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.grind",
        "the LEASE survives -- only the caretaker went stale")
end

--- Isolates `end_tick()` itself.
---
--- Caretaker inertness has TWO independent mechanisms: the issued-tick comparison (automatic
--- the moment the tick index moves) and the flag `end_tick()` flips. The test above passes on
--- the first mechanism alone, so it does NOT prove the second works -- verified by mutation:
--- deleting the `_invalidate()` call leaves it green. ADR 08 §6.1 specifies the flag ("the
--- kernel flips its `revoked` flag at tick end"), so it needs its own assertion, taken
--- WITHOUT advancing the tick so the other mechanism cannot mask it.
function M.test_end_tick_invalidates_caretakers_within_the_same_tick()
    local broker = make_broker()
    local caretaker = acquire(broker, make_plugin("activity.grind", "GOAL"), Channel.MOVEMENT, 10)
    T.assert_true(caretaker:is_valid())

    broker:end_tick() -- no arbitrate(), so the tick index is unchanged

    T.assert_false(caretaker:is_valid(),
        "end_tick() alone must make the caretaker inert -- ADR 08 §6.1's stated mechanism")
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "activity.grind",
        "and the lease must be untouched by it")
end

--- The other half: renewing in the next tick must work even though the old caretaker died.
function M.test_a_renewal_is_not_broken_by_the_previous_caretaker_being_invalidated()
    local broker = make_broker()
    local plugin = make_plugin("activity.grind", "GOAL")
    local old = acquire(broker, plugin, Channel.MOVEMENT, 10)
    local generation = old:generation()

    broker:end_tick()
    broker:arbitrate(2)
    T.assert_false(old:is_valid(), "precondition: last tick's caretaker is inert")

    local fresh = acquire(broker, plugin, Channel.MOVEMENT, 10)
    T.assert_not_nil(fresh, "the owner must still be able to renew")
    T.assert_true(fresh:is_valid())
    T.assert_equal(fresh:generation(), generation,
        "the underlying lease is the same grant, so the generation must not change")
    T.assert_equal(#plugin.revocations, 0, "renewal across a tick boundary is not a revocation")
end

--- A stale caretaker must not be usable as authority either.
function M.test_a_stale_caretaker_cannot_submit_an_intent()
    local submitted = {}
    local broker = make_broker()
    broker:set_intent_queue({ submit = function(_s, intent) submitted[#submitted + 1] = intent; return true end })

    local caretaker = acquire(broker, make_plugin("r", "COMBAT"), Channel.CASTING, 10)
    T.assert_true(caretaker:submit({ type = "cast", payload = { spell_id = 1 } }))
    T.assert_equal(#submitted, 1)

    broker:end_tick()
    broker:arbitrate(2)

    local ok, reason = caretaker:submit({ type = "cast", payload = { spell_id = 2 } })
    T.assert_false(ok, "a stale caretaker must not be able to act")
    T.assert_equal(reason, "caretaker_stale")
    T.assert_equal(#submitted, 1, "nothing may reach the queue through a dead caretaker")
end

--- The capability model: "If a plugin can reach the lease, the capability model is already
--- broken." The caretaker must expose no field that leads to the lease or its callback.
function M.test_the_caretaker_does_not_expose_the_lease()
    local broker = make_broker()
    local plugin = make_plugin("activity.grind", "GOAL")
    local caretaker = acquire(broker, plugin, Channel.MOVEMENT)

    for key, value in pairs(caretaker) do
        T.assert_false(type(value) == "table" and value.on_revoke ~= nil,
            "caretaker field '" .. tostring(key) .. "' leaks something lease-shaped")
        T.assert_false(type(value) == "table" and value.channels ~= nil and value.generation ~= nil,
            "caretaker field '" .. tostring(key) .. "' leaks the lease")
    end
end

--- ...and it must not expose a movement verb either. In Phase 2 the only core.input call
--- site is the kernel's force-release; a caretaker that could press a key would be a second
--- one, i.e. ambient authority handed straight back to plugins.
function M.test_the_caretaker_exposes_no_direct_input_verb()
    local broker = make_broker()
    local caretaker = acquire(broker, make_plugin("a", "GOAL"), Channel.MOVEMENT)
    for _, verb in ipairs({ "move_forward_start", "move_forward_stop", "cast", "look_at", "jump" }) do
        T.assert_nil(caretaker[verb],
            "caretaker must not expose '" .. verb .. "' -- Phase 2 acts only through intents")
    end
end

-- ---------------------------------------------------------------------------
-- Generation counters (ADR 08 §6.1) -- closing the revocation race
-- ---------------------------------------------------------------------------

function M.test_generations_are_monotonic_across_grants()
    local broker = make_broker()
    local a = acquire(broker, make_plugin("a", "GOAL"), Channel.MOVEMENT)
    local b = acquire(broker, make_plugin("b", "COMBAT"), Channel.CASTING)
    T.assert_true(b:generation() > a:generation(), "each grant must take a higher generation")
end

--- "This closes the revocation race where an intent emitted under a NOW-DEAD lease still
--- commits." The exact sequence: emit early in the tick, get revoked later in the same tick.
function M.test_an_intent_emitted_before_revocation_is_invalid_after_it()
    local broker = make_broker()
    local grind = make_plugin("activity.grind", "GOAL")
    local caretaker = acquire(broker, grind, Channel.MOVEMENT)

    -- Early in the tick the activity emits an intent stamped with its live generation.
    local intent = { type = "move_to", owner = "activity.grind", band = 30,
                     generation = caretaker:generation(), payload = { x = 1 } }
    T.assert_true(broker:is_generation_valid(intent), "valid while the lease is live")

    -- Later in the SAME tick, safety preempts it.
    broker:acquire({ channel = Channel.MOVEMENT, owner = "behavior.safety", band = "SAFETY", ttl_ticks = 5 })

    T.assert_false(broker:is_generation_valid(intent),
        "the intent must NOT commit -- its lease was revoked after it was emitted")
end

function M.test_a_generation_from_a_released_lease_is_invalid()
    local broker = make_broker()
    local caretaker = acquire(broker, make_plugin("r", "COMBAT"), Channel.CASTING)
    local intent = { owner = "r", generation = caretaker:generation() }
    broker:release(caretaker)
    T.assert_false(broker:is_generation_valid(intent))
end

--- An intent with no generation has no lease behind it, which means no authority. Fencing
--- ambient authority means this is a refusal, not a pass.
function M.test_an_intent_with_no_generation_is_invalid()
    local broker = make_broker()
    T.assert_false(broker:is_generation_valid({ owner = "r" }),
        "no generation means no lease means no authority")
    T.assert_false(broker:is_generation_valid(nil))
end

function M.test_a_generation_belonging_to_a_different_owner_is_invalid()
    local broker = make_broker()
    local caretaker = acquire(broker, make_plugin("real.owner", "COMBAT"), Channel.CASTING)
    T.assert_false(broker:is_generation_valid({ owner = "impostor", generation = caretaker:generation() }),
        "a generation is not a bearer token -- it must match its owner")
end

function M.test_a_renewed_lease_keeps_its_intents_valid()
    local broker = make_broker()
    local plugin = make_plugin("activity.grind", "GOAL")
    local first = acquire(broker, plugin, Channel.MOVEMENT, 5)
    local intent = { owner = "activity.grind", generation = first:generation() }

    broker:end_tick()
    broker:arbitrate(2)
    acquire(broker, plugin, Channel.MOVEMENT, 5)

    T.assert_true(broker:is_generation_valid(intent),
        "a renewal is the same grant -- it must not invalidate in-flight intents")
end

-- ---------------------------------------------------------------------------
-- Preemption cool-down / livelock guard
-- ---------------------------------------------------------------------------

--- The failure mode named in the prompt: "A holder that renews every tick and a preempting
--- acquirer that retries every tick can livelock." Without a cool-down the loser can win the
--- race at handover and trigger preemption again, forever.
function M.test_a_renewing_holder_and_a_retrying_preemptor_converge_rather_than_livelock()
    local broker, stopped = make_broker()
    local holder = make_plugin("activity.grind", "GOAL")       -- renews every tick
    local preemptor = make_plugin("behavior.safety", "SAFETY") -- retries every tick

    acquire(broker, holder, Channel.MOVEMENT, 2)

    local winner_at = nil
    for tick = 1, 6 do
        broker:arbitrate(tick)
        -- The holder asks FIRST every tick -- the adversarial ordering.
        acquire(broker, holder, Channel.MOVEMENT, 2)
        local got = acquire(broker, preemptor, Channel.MOVEMENT, 2)
        if got and winner_at == nil then winner_at = tick end
        broker:end_tick()
    end

    T.assert_not_nil(winner_at, "the higher band must eventually win -- this is the livelock")
    T.assert_equal(broker:who_owns(Channel.MOVEMENT), "behavior.safety")
    T.assert_true(#stopped >= #MovementRelease.KEYS, "the loser's keys were released")
    -- One preemption, not one per tick: the cool-down must stop the thrash.
    T.assert_equal(#holder.revocations, 1,
        "the holder must be revoked ONCE, not re-revoked every tick (got "
        .. #holder.revocations .. ")")
end

--- The specific mechanism: the preempted owner cannot immediately re-take the channel and
--- restart the cycle.
function M.test_a_preempted_owner_is_backed_off_from_immediate_reacquisition()
    local broker = make_broker()
    local holder = make_plugin("activity.grind", "GOAL")
    local preemptor = make_plugin("behavior.safety", "SAFETY")
    acquire(broker, holder, Channel.MOVEMENT)
    acquire(broker, preemptor, Channel.MOVEMENT) -- preempts, channel now cooling

    broker:arbitrate(2)
    local retaken, reason = acquire(broker, holder, Channel.MOVEMENT)
    T.assert_nil(retaken, "the preempted owner must not win the handover race")
    T.assert_equal(reason, "preempted_backoff")

    local won = acquire(broker, preemptor, Channel.MOVEMENT)
    T.assert_not_nil(won, "the preemptor gets it")
end

--- During the cool-down nobody takes the channel -- that is what makes handover not
--- same-tick.
function M.test_nobody_acquires_a_cooling_channel()
    local broker = make_broker()
    acquire(broker, make_plugin("a", "GOAL"), Channel.MOVEMENT)
    acquire(broker, make_plugin("b", "SAFETY"), Channel.MOVEMENT) -- preempt -> cooling

    local third, reason = acquire(broker, make_plugin("c", "SURVIVAL"), Channel.MOVEMENT)
    T.assert_nil(third, "a cooling channel is unavailable to everyone")
    T.assert_equal(reason, "channel_cooling")
end

-- ---------------------------------------------------------------------------
-- Equal priority
-- ---------------------------------------------------------------------------

--- Equal priority does not preempt. Ties going to the incumbent is what stops two same-band
--- plugins trading a channel every tick.
function M.test_equal_priority_does_not_preempt()
    local broker = make_broker()
    local first = make_plugin("r.one", "COMBAT")
    local second = make_plugin("r.two", "COMBAT")
    acquire(broker, first, Channel.CASTING)

    local got, reason = acquire(broker, second, Channel.CASTING)
    T.assert_nil(got)
    T.assert_equal(reason, "channel_held")
    T.assert_equal(#first.revocations, 0, "the incumbent keeps a tie")
end

function M.test_lower_priority_cannot_preempt_higher()
    local broker = make_broker()
    local high = make_plugin("b.safety", "SAFETY")
    acquire(broker, high, Channel.MOVEMENT)

    local got, reason = acquire(broker, make_plugin("a.grind", "GOAL"), Channel.MOVEMENT)
    T.assert_nil(got)
    T.assert_equal(reason, "channel_held")
    T.assert_equal(#high.revocations, 0)
end

-- ---------------------------------------------------------------------------
-- revoke_below -- what an ActivityStack push at band 90 needs
-- ---------------------------------------------------------------------------

function M.test_revoke_below_clears_lower_priority_holders_only()
    local broker, stopped = make_broker()
    local low = make_plugin("activity.grind", "GOAL")        -- 30
    local mid = make_plugin("rotation.frost", "COMBAT")      -- 50
    local high = make_plugin("behavior.safety", "SAFETY")    -- 90
    acquire(broker, low, Channel.MOVEMENT)
    acquire(broker, mid, Channel.CASTING)
    acquire(broker, high, Channel.ITEMS)

    local revoked = broker:revoke_below(90, "activity_push")

    T.assert_equal(revoked, 2, "both sub-90 leases must go")
    T.assert_nil(broker:who_owns(Channel.MOVEMENT))
    T.assert_nil(broker:who_owns(Channel.CASTING))
    T.assert_equal(broker:who_owns(Channel.ITEMS), "behavior.safety", "band 90 must survive")
    T.assert_equal(low.revocations[1], "activity_push")
    T.assert_equal(#stopped, #MovementRelease.KEYS, "the movement holder was force-released")
end

-- ---------------------------------------------------------------------------
-- Events + observability
-- ---------------------------------------------------------------------------

function M.test_revocation_is_published()
    local broker, _, bus = make_broker()
    local events = {}
    bus:subscribe("control:revoked", function(p) events[#events + 1] = p end)

    acquire(broker, make_plugin("a", "GOAL"), Channel.MOVEMENT)
    acquire(broker, make_plugin("b", "SAFETY"), Channel.MOVEMENT)

    T.assert_equal(#events, 1)
    T.assert_equal(events[1].owner, "a")
    T.assert_equal(events[1].reason, "preempted")
    T.assert_true(events[1].movement_released, "the audit trail must record the force-release")
end

function M.test_holdings_report_is_readable_for_the_cockpit()
    local broker = make_broker()
    acquire(broker, make_plugin("activity.grind", "GOAL"), Channel.MOVEMENT)
    acquire(broker, make_plugin("rotation.frost", "COMBAT"), Channel.CASTING)

    local holdings = broker:holdings()
    T.assert_equal(holdings.MOVEMENT.owner, "activity.grind")
    T.assert_equal(holdings.MOVEMENT.band, "GOAL")
    T.assert_equal(holdings.CASTING.owner, "rotation.frost")
    T.assert_nil(holdings.ITEMS)
end

return M
