-- tests/kernel/test_intent_executors.lua
-- Casting becomes real (ADR 08 §3.2, §6.3, justified by §2.6).
--
-- §2.6, on the call this layer wraps: "`core.input.cast_target_spell` performs ZERO validation --
-- no range, no facing, no ready check; it only sends a packet. That is exactly the gap the commit
-- stage exists to fill."
--
-- So the tests here are not "does a cast happen". They are "does a cast that SHOULD NOT happen get
-- refused, by name, at the gate". Three things must hold before a packet leaves:
--   1. a lease authorised it            (generation check, §6.1)
--   2. the GCD is not running           (kernel/timing.lua, §2.5)
--   3. the SDK agrees it is castable    (range + facing, §2.6)
--
-- §6.3's band -> spell_queue mapping is pinned here too, including the colon call convention that
-- every `common/` module uses.

local IntentQueue = require("kernel/intent_queue")
local Executors = require("kernel/intent_executors")
local Timing = require("kernel/timing")
local ControlBroker = require("kernel/control_broker")
local EventBus = require("core/event_bus")
local Bands = require("kernel/bands")
local Units = require("kernel/units")
local Snapshot = require("kernel/snapshot")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- Doubles
-- ---------------------------------------------------------------------------

--- A spell_queue double that records HOW it was called, not just that it was. The colon convention
--- is load-bearing (§2.6: "it also uses the colon call convention, as do all `common/` modules"), so
--- the double asserts on the receiver rather than discarding it.
local function spell_queue_double()
    local sq = { calls = {}, position_calls = {}, fast_calls = {}, fast_position_calls = {} }
    function sq:queue_spell_target_fast(spell_id, target, priority, message)
        self.fast_calls[#self.fast_calls + 1] = {
            receiver_ok = (self == sq),
            spell_id = spell_id, target = target, priority = priority, message = message,
        }
        return true
    end
    function sq:queue_spell_position_fast(spell_id, position, priority, message)
        self.fast_position_calls[#self.fast_position_calls + 1] = {
            receiver_ok = (self == sq),
            spell_id = spell_id, position = position, priority = priority, message = message,
        }
        return true
    end
    function sq:queue_spell_target(spell_id, target, priority, message)
        self.calls[#self.calls + 1] = {
            receiver_ok = (self == sq),
            spell_id = spell_id, target = target, priority = priority, message = message,
        }
        return true
    end
    --- The ground-targeted form. Recorded SEPARATELY from `calls`, because "a cast happened" is not
    --- the assertion that matters -- a point cast routed through `queue_spell_target` would send the
    --- position where a unit handle belongs, and a shared log could not tell the two apart.
    function sq:queue_spell_position(spell_id, position, priority, message)
        self.position_calls[#self.position_calls + 1] = {
            receiver_ok = (self == sq),
            spell_id = spell_id, position = position, priority = priority, message = message,
        }
        return true
    end
    return sq
end

local PLAYER = { id = "player", get_guid = function() return "guid-player" end }
local TARGET = { id = "target", get_guid = function() return "guid-target" end }

---@param opts table { castable?, timing?, gcd_spell? }
local function harness(opts)
    opts = opts or {}
    local queue = IntentQueue:new()
    local timing = opts.timing or Timing:new({ now_ms = function() return 0 end })
    local sq = spell_queue_double()
    local castable_calls = {}
    --- Units addressable only by guid: the secondary enemy Polymorph picks, the low-health add
    --- Fire Blast finishes. Neither is nameable in the closed symbolic vocabulary.
    local units_by_guid = {
        ["guid-add-1"] = { id = "low-health-add", get_guid = function() return "guid-add-1" end },
        ["guid-player"] = PLAYER,
    }

    Executors.install({
        intent_queue = queue,
        timing = timing,
        spell_queue = sq,
        object_manager = {
            get_local_player = function() return PLAYER end,
            get_object_from_guid = function(guid) return units_by_guid[guid] end,
        },
        unit_target = function() return TARGET end,
        spell_helper = {
            is_spell_castable = function(spell_id, caster, target, skip_facing, skip_range)
                castable_calls[#castable_calls + 1] = {
                    spell_id = spell_id, caster = caster, target = target,
                    skip_facing = skip_facing, skip_range = skip_range,
                }
                if opts.castable == nil then return true end
                return opts.castable
            end,
        },
        input = { set_target = function(unit) sq.last_set_target = unit return true end },
    })

    return {
        queue = queue, timing = timing, sq = sq,
        castable_calls = castable_calls, units_by_guid = units_by_guid,
    }
end

local function cast_intent(overrides)
    local intent = {
        type = "cast", owner = "rotations.mage_frost", band = Bands.BANDS.COMBAT.min,
        payload = { spell_id = 116, unit = "target" },
    }
    for k, v in pairs(overrides or {}) do intent[k] = v end
    return intent
end

local function first_rejection(report)
    local r = report.rejected[1]
    if not r then return nil end
    return r.gate, r.reason
end

--- The tick the guid-addressed tests below mint and commit under.
---
--- A guid ref carries a generation stamp re-checked at commit (see the UnitRef section further
--- down), so a test that means to pin RESOLUTION has to carry a valid stamp -- otherwise it stops
--- at `unstamped_unit_ref` and measures the freshness check instead of the thing it was written
--- for. One constant so the two cannot drift apart per-test.
local TICK = 1
local function this_tick() return Snapshot.empty(TICK) end

-- ---------------------------------------------------------------------------
-- The band -> spell_queue mapping (§6.3)
-- ---------------------------------------------------------------------------

function M.test_a_combat_band_cast_queues_at_spell_queue_priority_1()
    local h = harness()
    h.queue:submit(cast_intent())
    local report = h.queue:commit({})

    T.assert_equal(#report.committed, 1, "a well-formed cast must commit")
    T.assert_equal(#h.sq.calls, 1)
    T.assert_equal(h.sq.calls[1].priority, 1, "§6.3: bands <= 69 map to spell_queue priority 1")
    T.assert_equal(h.sq.calls[1].spell_id, 116)
    T.assert_true(h.sq.calls[1].target == TARGET)
end

function M.test_a_survival_band_cast_queues_at_spell_queue_priority_7()
    local h = harness()
    h.queue:submit(cast_intent({ band = Bands.BANDS.SURVIVAL.min }))
    h.queue:commit({})
    T.assert_equal(h.sq.calls[1].priority, 7,
        "§6.3: survival and safety map to 7, the documented interrupt slot")
end

function M.test_a_safety_band_cast_queues_at_spell_queue_priority_7()
    local h = harness()
    h.queue:submit(cast_intent({ band = Bands.BANDS.SAFETY.min }))
    h.queue:commit({})
    T.assert_equal(h.sq.calls[1].priority, 7)
end

--- §2.6: every `common/` module uses `mod:fn()`. Calling with a dot silently shifts every argument
--- by one, which would put the spell id where the receiver belongs.
function M.test_the_spell_queue_is_called_with_the_colon_convention()
    local h = harness()
    h.queue:submit(cast_intent())
    h.queue:commit({})
    T.assert_true(h.sq.calls[1].receiver_ok,
        "spell_queue must receive itself as the receiver, not the spell id")
end

--- Priority 9 is reserved for manual player input (§6.3, and the SDK's own docs). The kernel must
--- never emit it, whatever band arithmetic produces.
function M.test_the_kernel_never_emits_the_reserved_manual_priority()
    for _, band in ipairs({ 0, 25, 49, 50, 69, 70, 89, 90, 99 }) do
        T.assert_true(Bands.spell_queue_priority(band) ~= 9,
            "band " .. band .. " must not map to the reserved manual-input priority 9")
    end
end

-- ---------------------------------------------------------------------------
-- The GCD gate (§2.5)
-- ---------------------------------------------------------------------------

--- The failure mode the whole Timing service exists to prevent.
function M.test_a_second_cast_inside_the_gcd_is_rejected()
    local clock = { ms = 0 }
    local timing = Timing:new({ now_ms = function() return clock.ms end })
    local saved = _G.core
    _G.core = { spell_book = { get_global_cooldown = function() return 1.5 end } }

    local ok, err = pcall(function()
        local h = harness({ timing = timing })

        h.queue:submit(cast_intent())
        T.assert_equal(#h.queue:commit({}).committed, 1, "the first cast goes through")

        clock.ms = 500
        h.queue:submit(cast_intent({ payload = { spell_id = 133, unit = "target" } }))
        local report = h.queue:commit({})

        T.assert_equal(#report.committed, 0, "the second cast must NOT reach the spell queue")
        local gate, reason = first_rejection(report)
        T.assert_equal(gate, "gcd")
        T.assert_equal(reason, "gcd_running")
        T.assert_equal(#h.sq.calls, 1, "and exactly one packet was sent, not two")

        clock.ms = 1500
        h.queue:submit(cast_intent({ payload = { spell_id = 133, unit = "target" } }))
        T.assert_equal(#h.queue:commit({}).committed, 1, "once the window closes it commits")
    end)

    _G.core = saved
    if not ok then error(err, 0) end
end

--- Ice Block is off-GCD. Gating it behind a GCD it does not use makes the panic button unreachable
--- exactly when it is needed.
function M.test_an_off_gcd_cast_is_not_held_by_the_gcd_gate()
    local clock = { ms = 0 }
    local timing = Timing:new({ now_ms = function() return clock.ms end })
    local saved = _G.core
    _G.core = { spell_book = { get_global_cooldown = function() return 1.5 end } }

    local ok, err = pcall(function()
        local h = harness({ timing = timing })
        h.queue:submit(cast_intent())
        h.queue:commit({})

        clock.ms = 200
        h.queue:submit(cast_intent({
            band = Bands.BANDS.SURVIVAL.min,
            payload = { spell_id = 45438, unit = "player", off_gcd = true },
        }))
        local report = h.queue:commit({})
        T.assert_equal(#report.committed, 1, "an off-GCD cast must pass the GCD gate")
    end)

    _G.core = saved
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------
-- The castable gate: range and facing (§2.6)
-- ---------------------------------------------------------------------------

--- The ADR's exact justification for two-phase commit. `cast_target_spell` would have sent this.
function M.test_an_out_of_range_cast_is_rejected_at_the_gate()
    local h = harness({ castable = false })
    h.queue:submit(cast_intent())
    local report = h.queue:commit({})

    T.assert_equal(#report.committed, 0)
    T.assert_equal(#h.sq.calls, 0, "no packet may leave for an uncastable spell")
    local gate, reason = first_rejection(report)
    T.assert_equal(gate, "castable")
    T.assert_equal(reason, "not_castable")
end

--- The gate must actually ASK about facing and range rather than skipping both checks, which would
--- make it a gate in name only.
function M.test_the_gate_asks_the_sdk_about_both_facing_and_range()
    local h = harness()
    h.queue:submit(cast_intent())
    h.queue:commit({})

    T.assert_equal(#h.castable_calls, 1)
    local call = h.castable_calls[1]
    T.assert_equal(call.spell_id, 116)
    T.assert_true(call.caster == PLAYER)
    T.assert_true(call.target == TARGET)
    T.assert_false(call.skip_facing, "skipping the facing check defeats the gate")
    T.assert_false(call.skip_range, "skipping the range check defeats the gate")
end

--- A self-cast has no meaningful facing or range. Forcing those checks would reject buffs.
function M.test_a_self_cast_skips_facing_and_range()
    local h = harness()
    h.queue:submit(cast_intent({ payload = { spell_id = 168, unit = "player" } }))
    h.queue:commit({})

    local call = h.castable_calls[1]
    T.assert_true(call.caster == PLAYER)
    T.assert_true(call.target == PLAYER)
    T.assert_true(call.skip_facing)
    T.assert_true(call.skip_range)
end

--- `shared/spell_helper.lua` returns the STRING `SpellHelper.UNKNOWN` when the spell-book helper is
--- unresolved -- deliberately, so callers can tell "no" from "cannot say". A truthy string is not
--- permission: anything other than a literal `true` must fail closed, or an unresolved helper
--- becomes a licence to cast at anything from anywhere.
function M.test_an_unknown_castability_verdict_is_refused_rather_than_trusted()
    local h = harness({ castable = "UNKNOWN" })
    h.queue:submit(cast_intent())
    local report = h.queue:commit({})

    T.assert_equal(#report.committed, 0, "an UNKNOWN verdict must not commit")
    T.assert_equal(#h.sq.calls, 0)
    local gate, reason = first_rejection(report)
    T.assert_equal(gate, "castable")
    T.assert_equal(reason, "not_castable")
end

--- A target reference that resolves to nothing must be refused, not passed as nil into an SDK call
--- that "only sends a packet".
function M.test_a_cast_at_a_vanished_target_is_refused()
    local queue = IntentQueue:new()
    Executors.install({
        intent_queue = queue,
        timing = Timing:new({ now_ms = function() return 0 end }),
        spell_queue = spell_queue_double(),
        object_manager = { get_local_player = function() return PLAYER end },
        unit_target = function() return nil end,
        spell_helper = { is_spell_castable = function() return true end },
        input = {},
    })

    queue:submit(cast_intent())
    local report = queue:commit({})
    T.assert_equal(#report.committed, 0)
    local gate, reason = first_rejection(report)
    T.assert_equal(gate, "castable")
    T.assert_equal(reason, "unit_unresolved")
end

-- ---------------------------------------------------------------------------
-- Ground-targeted casts, and units the closed vocabulary cannot name
-- ---------------------------------------------------------------------------
-- Both gaps were found by RE-MEASURING the frost cast path for Phase 4c D4 rather than by reading
-- the kernel. The rotation has 38 cast sites; the `cast` intent as built could express 30 of them.
--
--   * SIX are GROUND-TARGETED (Blizzard x3, Flamestrike x3). `cast_executor` only ever called
--     `queue_spell_target`, so a point cast had no route through the kernel at all -- even though
--     the SDK documents `spell_queue:queue_spell_position(spell_id, position, priority, message)`.
--   * TWO name a unit that is neither the player, the current target, nor the pet: Polymorph picks
--     a secondary enemy and `finish_low_add` casts at `combat.low_health_add`. The symbolic
--     vocabulary is closed (`player`/`target`/`pet`) and a handle may never ride in a payload
--     (§2.7), so there was no way to say "that one".
--
-- A GUID is the resolution: it is a VALUE, so it satisfies §2.7, and the executor turns it back
-- into a handle at commit -- inside the tick, at the moment of use, which is what the SDK asks for.

local POINT = { x = 10.5, y = -20.25, z = 3.0 }

function M.test_a_ground_targeted_cast_reaches_queue_spell_position()
    local h = harness()
    h.queue:submit(cast_intent({ payload = { spell_id = 10, point = POINT } }))
    local report = h.queue:commit({})

    T.assert_equal(#report.committed, 1, "a well-formed point cast must commit")
    T.assert_equal(#h.sq.position_calls, 1, "and must reach queue_spell_position, not _target")
    T.assert_equal(#h.sq.calls, 0, "a point cast is not a unit cast")
    T.assert_equal(h.sq.position_calls[1].spell_id, 10)
    T.assert_equal(h.sq.position_calls[1].position.x, 10.5)
    T.assert_equal(h.sq.position_calls[1].priority, 1, "§6.3 band mapping applies to points too")
    T.assert_true(h.sq.position_calls[1].receiver_ok, "colon convention, same as every common/ module")
end

function M.test_a_ground_targeted_cast_with_a_malformed_point_is_refused_by_name()
    local h = harness()
    h.queue:submit(cast_intent({ payload = { spell_id = 10, point = { x = 1, y = 2 } } }))
    local report = h.queue:commit({})
    T.assert_equal(#report.committed, 0)
    local gate, reason = first_rejection(report)
    T.assert_equal(gate, "castable")
    T.assert_equal(reason, "malformed_point")
end

--- The reduced check, stated rather than implied. `is_spell_castable` takes a TARGET UNIT; a patch
--- of ground is not one. So a point cast is asked the only question the SDK can answer about it --
--- do I know this spell and is it off cooldown -- with facing and range skipped. Range TO THE POINT
--- is NOT verified by the kernel, and pretending otherwise would be worse than saying so.
function M.test_a_ground_targeted_cast_is_still_asked_whether_the_spell_is_castable_at_all()
    local h = harness()
    h.queue:submit(cast_intent({ payload = { spell_id = 10, point = POINT } }))
    h.queue:commit({})

    T.assert_equal(#h.castable_calls, 1, "the spell itself must still be checked")
    local call = h.castable_calls[1]
    T.assert_equal(call.spell_id, 10)
    T.assert_true(call.caster == PLAYER)
    T.assert_true(call.skip_facing, "no unit to face")
    T.assert_true(call.skip_range, "the SDK cannot answer range to a point through this call")
end

function M.test_a_ground_targeted_cast_the_spellbook_refuses_does_not_reach_the_queue()
    local h = harness({ castable = false })
    h.queue:submit(cast_intent({ payload = { spell_id = 10, point = POINT } }))
    local report = h.queue:commit({})
    T.assert_equal(#report.committed, 0)
    T.assert_equal(#h.sq.position_calls, 0)
    local _, reason = first_rejection(report)
    T.assert_equal(reason, "not_castable")
end

function M.test_a_cast_addressed_by_guid_resolves_the_unit_at_commit()
    local h = harness()
    h.queue:submit(cast_intent({
        payload = { spell_id = 116, unit_guid = "guid-add-1", unit_ref_tick = TICK },
    }))
    local report = h.queue:commit(this_tick())

    T.assert_equal(#report.committed, 1)
    T.assert_equal(#h.sq.calls, 1)
    T.assert_true(h.sq.calls[1].target == h.units_by_guid["guid-add-1"],
        "the guid must resolve to the live handle the object manager hands back")
end

--- A guid whose object has gone -- the add died between the rotation choosing it and COMMIT running
--- -- must be refused, not passed as nil into a call that "only sends a packet". This is the whole
--- reason the guid is resolved at commit rather than at submit.
--- Self-ness is decided by the KERNEL, not asserted by the caller.
---
--- A self-buff addressed by guid must still skip facing and range, or every one of them is refused
--- for not facing itself. The plugin cannot make that call without reading `player.object` off the
--- blackboard -- a raw handle read the namespace audit counts, and one the kernel does not need it
--- to make, because the executor is already holding the player.
function M.test_a_guid_that_resolves_to_the_player_is_treated_as_a_self_cast()
    local h = harness()
    h.queue:submit(cast_intent({
        payload = { spell_id = 27088, unit_guid = "guid-player", unit_ref_tick = TICK },
    }))
    h.queue:commit(this_tick())

    T.assert_equal(#h.castable_calls, 1)
    T.assert_true(h.castable_calls[1].skip_facing, "a self-cast has no facing to check")
    T.assert_true(h.castable_calls[1].skip_range, "nor any range")
end

function M.test_a_guid_that_resolves_to_someone_else_is_not_a_self_cast()
    local h = harness()
    h.queue:submit(cast_intent({
        payload = { spell_id = 116, unit_guid = "guid-add-1", unit_ref_tick = TICK },
    }))
    h.queue:commit(this_tick())
    T.assert_false(h.castable_calls[1].skip_facing, "facing must be checked on another unit")
    T.assert_false(h.castable_calls[1].skip_range)
end

function M.test_a_cast_addressed_by_a_guid_that_no_longer_resolves_is_refused()
    local h = harness()
    h.queue:submit(cast_intent({
        payload = { spell_id = 116, unit_guid = "guid-vanished", unit_ref_tick = TICK },
    }))
    local report = h.queue:commit(this_tick())
    T.assert_equal(#report.committed, 0)
    T.assert_equal(#h.sq.calls, 0)
    local gate, reason = first_rejection(report)
    T.assert_equal(gate, "castable")
    T.assert_equal(reason, "unit_unresolved")
end

--- Naming a unit two ways at once is a bug in the caller, not a preference to resolve silently.
function M.test_a_cast_naming_both_a_point_and_a_unit_is_refused()
    local h = harness()
    h.queue:submit(cast_intent({ payload = { spell_id = 10, point = POINT, unit = "target" } }))
    local report = h.queue:commit({})
    T.assert_equal(#report.committed, 0)
    local _, reason = first_rejection(report)
    T.assert_equal(reason, "overspecified_cast_destination")
end

--- The third gap the re-measurement found. `spell_dispatcher.lua` routes `opts.fast` to
--- `queue_spell_target_fast`, and three frost entries use it (Ice Barrier, Icy Veins, Cold Snap) --
--- instants where the dispatcher's post-queue snapshot verification costs more than it proves.
--- Without a `fast` payload the conversion would have quietly downgraded all three to the verifying
--- form, which is a behaviour change wearing no name.
function M.test_a_fast_cast_reaches_the_fast_queue_verb()
    local h = harness()
    h.queue:submit(cast_intent({ payload = { spell_id = 27101, unit = "player", fast = true } }))
    local report = h.queue:commit({})

    T.assert_equal(#report.committed, 1)
    T.assert_equal(#h.sq.fast_calls, 1, "a fast cast must reach queue_spell_target_fast")
    T.assert_equal(#h.sq.calls, 0, "and must not also take the verifying path")
    T.assert_equal(h.sq.fast_calls[1].spell_id, 27101)
end

function M.test_a_fast_ground_targeted_cast_reaches_the_fast_position_verb()
    local h = harness()
    h.queue:submit(cast_intent({ payload = { spell_id = 10, point = POINT, fast = true } }))
    h.queue:commit({})
    T.assert_equal(#h.sq.fast_position_calls, 1)
    T.assert_equal(#h.sq.position_calls, 0)
end

--- An SDK without the fast verb must be REFUSED, not silently served by the slow one. A rotation
--- that asked for `fast` did so because the verifying round-trip was the cost it was avoiding.
function M.test_a_fast_cast_is_refused_when_the_sdk_has_no_fast_verb()
    local queue = IntentQueue:new()
    Executors.install({
        intent_queue = queue,
        timing = Timing:new({ now_ms = function() return 0 end }),
        spell_queue = { queue_spell_target = function() return true end },
        object_manager = { get_local_player = function() return PLAYER end },
        unit_target = function() return TARGET end,
        spell_helper = { is_spell_castable = function() return true end },
        input = {},
    })
    queue:submit(cast_intent({ payload = { spell_id = 27101, unit = "player", fast = true } }))
    local report = queue:commit({})
    T.assert_equal(#report.committed, 0)
    T.assert_equal(report.failed[1].reason, "no_spell_queue")
end

--- The SDK's `message` argument is a debugging breadcrumb ("Leave Breadcrumbs", input.md §137), and
--- the dispatcher era filled it with the ACTION name -- `frostbolt`, `emergency_blink`. Sending the
--- plugin id instead would make every cast in the log read `sentinel.rotation.mage_frost`, which
--- identifies the plugin and not the decision. ADR §13.1 item 16 already notes that named refusals
--- observed by nobody are worth little; anonymising the accepted ones too would be the same loss.
function M.test_a_cast_carries_its_action_label_as_the_sdk_breadcrumb()
    local h = harness()
    h.queue:submit(cast_intent({
        payload = { spell_id = 116, unit = "target", label = "ice_lance_frozen" },
    }))
    h.queue:commit({})
    T.assert_equal(h.sq.calls[1].message, "ice_lance_frozen")
end

function M.test_a_cast_without_a_label_falls_back_to_the_owner()
    local h = harness()
    h.queue:submit(cast_intent())
    h.queue:commit({})
    T.assert_equal(h.sq.calls[1].message, "rotations.mage_frost",
        "an unlabelled cast is still attributable, just less precisely")
end

function M.test_a_cast_naming_no_destination_at_all_is_refused()
    local h = harness()
    h.queue:submit(cast_intent({ payload = { spell_id = 10 } }))
    local report = h.queue:commit({})
    T.assert_equal(#report.committed, 0)
    local _, reason = first_rejection(report)
    T.assert_equal(reason, "no_cast_destination")
end

-- ---------------------------------------------------------------------------
-- Only a lease may cast (§6.1)
-- ---------------------------------------------------------------------------

--- Phase 2 established this; Phase 4 makes casting real, so it is re-pinned against the executor
--- that now actually sends packets.
function M.test_a_cast_without_a_lease_never_reaches_the_spell_queue()
    local bus = EventBus:new(function() end)
    local queue = IntentQueue:new()
    local broker = ControlBroker:new({ event_bus = bus, intent_queue = queue })
    queue:set_generation_validator(function(intent)
        return broker:is_generation_valid(intent)
    end)

    local sq = spell_queue_double()
    Executors.install({
        intent_queue = queue,
        timing = Timing:new({ now_ms = function() return 0 end }),
        spell_queue = sq,
        object_manager = { get_local_player = function() return PLAYER end },
        unit_target = function() return TARGET end,
        spell_helper = { is_spell_castable = function() return true end },
        input = {},
    })

    -- Submitted directly, bypassing any caretaker: no generation stamp.
    queue:submit(cast_intent())
    local report = queue:commit({})

    T.assert_equal(#report.committed, 0)
    T.assert_equal(#sq.calls, 0, "an unleased cast must not send a packet")
    local gate = first_rejection(report)
    T.assert_equal(gate, "generation")
end

-- ---------------------------------------------------------------------------
-- Targeting
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- The `core.input` blast radius
-- ---------------------------------------------------------------------------

--- Phase 2 established that the kernel had exactly ONE `core.input.*` resolution site
--- (kernel/movement_release.lua). Making casting real is the obvious moment for that to sprawl, so
--- the count is pinned mechanically rather than re-audited by hand each phase.
---
--- It did not grow, and the reason is structural: casts go through `spell_queue`, not
--- `core.input.cast_target_spell`, and the executors take `input` as an INJECTED dependency
--- resolved at the composition root. A kernel file reaching for the live `core.input` table itself
--- is what this test forbids.
function M.test_the_kernel_resolves_core_input_in_exactly_one_place()
    local files = {}
    local find = io.popen('find sentinel/kernel -type f -name "*.lua" | sort')
    if find then
        for line in find:lines() do files[#files + 1] = line end
        find:close()
    end
    T.assert_true(#files > 0, "expected kernel sources to audit")

    -- Comment stripping happens HERE rather than in a shell pipeline, because most `core.input`
    -- mentions in the kernel are prose explaining why a file does NOT call it -- including trailing
    -- comments on lines of real code, which no line-oriented grep filter handles correctly.
    local sites = {}
    for _, path in ipairs(files) do
        local handle = io.open(path, "r")
        if handle then
            local line_number = 0
            for line in handle:lines() do
                line_number = line_number + 1
                local code = line:match("^(.-)%-%-") or line
                if code:find("core%.input") then
                    sites[#sites + 1] = path .. ":" .. line_number .. ":" .. line
                end
            end
            handle:close()
        end
    end

    T.assert_equal(#sites, 1,
        "the kernel must resolve `core.input` in exactly one place; found:\n  "
        .. table.concat(sites, "\n  "))
    T.assert_true(sites[1]:find("movement_release") ~= nil,
        "and that place must remain kernel/movement_release.lua, got: " .. tostring(sites[1]))
end

function M.test_a_target_intent_routes_through_input_set_target()
    local h = harness()
    h.queue:submit({
        type = "target", owner = "rotations.mage_frost", band = Bands.BANDS.COMBAT.min,
        payload = { unit = "target" },
    })
    local report = h.queue:commit({})
    T.assert_equal(#report.committed, 1)
    T.assert_true(h.sq.last_set_target == TARGET)
end

-- ===========================================================================
-- THE FOUR INTENT TYPES ADDED IN PHASE 4b (face, move, use_item, pet_command)
-- ===========================================================================
--
-- ONE INTENT TYPE PER CHANNEL. An intent is authorised by exactly one lease, because the
-- commit stage re-validates the generation of the lease that produced it. An intent spanning
-- two channels would have no single authorising lease -- and FACING and MOVEMENT are separate
-- channels precisely so a rotation can face while an activity moves (§6.1's kiting case).
--
-- EACH GATE VALIDATES ITS OWN PRECONDITIONS. `use_item` asking `get_item_cooldown` about a bag
-- item is not the same check as `cast` asking `get_spell_cooldown` about a spellbook entry,
-- even though the two rhyme. A shared gate would have to weaken to the union of what both can
-- verify, which means checking neither properly.
--
-- WHAT THE OLD CODE DID, AND WHY THIS IS THE POINT. Every converted call site was
-- `pcall(core.input.<fn>, ...)` with the result DISCARDED -- fail-silent, the exact shape §12
-- names in LazyBot. A named rejection from the commit stage is the whole return on this work.

local MovementRelease = require("kernel/movement_release")

local PET = { id = "pet" }

---@param opts table { pet?, pet_alive?, has_item?, item_cooldown?, omit? }
local function verbs_harness(opts)
    opts = opts or {}
    local queue = IntentQueue:new()
    local calls = {}

    local pet = opts.pet
    if pet == nil then pet = PET end

    local player = {
        get_pet = function() return pet end,
        has_item = function(_self, item_id)
            calls[#calls + 1] = { verb = "has_item", item_id = item_id }
            if opts.has_item == nil then return true end
            return opts.has_item
        end,
        get_item_cooldown = function(_self, item_id)
            return opts.item_cooldown or 0
        end,
    }
    if opts.omit_has_item then player.has_item = nil end
    if opts.omit_item_cooldown then player.get_item_cooldown = nil end

    if pet then
        pet.is_alive = function() return opts.pet_alive ~= false end
    end

    local input = {
        look_at = function(point) calls[#calls + 1] = { verb = "look_at", point = point } return true end,
        use_item = function(item_id) calls[#calls + 1] = { verb = "use_item", item_id = item_id } return true end,
        pet_attack = function(unit) calls[#calls + 1] = { verb = "pet_attack", unit = unit } return true end,
        pet_cast_target_spell = function(spell_id, unit)
            calls[#calls + 1] = { verb = "pet_cast", spell_id = spell_id, unit = unit }
            return true
        end,
        set_pet_passive = function() calls[#calls + 1] = { verb = "set_pet_passive" } return true end,
        set_pet_follow = function() calls[#calls + 1] = { verb = "set_pet_follow" } return true end,
        set_target = function() return true end,
    }
    for _, name in ipairs(opts.omit or {}) do input[name] = nil end

    Executors.install({
        intent_queue = queue,
        timing = Timing:new({ now_ms = function() return 0 end }),
        spell_queue = spell_queue_double(),
        object_manager = { get_local_player = function() return player end },
        unit_target = function() return TARGET end,
        spell_helper = { is_spell_castable = function() return true end },
        input = input,
    })

    return { queue = queue, calls = calls, input = input, player = player }
end

local function submit_and_commit(h, intent)
    intent.owner = intent.owner or "rotations.mage_frost"
    intent.band = intent.band or Bands.BANDS.COMBAT.min
    h.queue:submit(intent)
    return h.queue:commit({})
end

local function called(h, verb)
    for _, c in ipairs(h.calls) do
        if c.verb == verb then return c end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- face -- FACING
-- ---------------------------------------------------------------------------

function M.test_a_face_intent_looks_at_the_point()
    local h = verbs_harness()
    local report = submit_and_commit(h, {
        type = "face", payload = { point = { x = 1, y = 2, z = 3 } },
    })

    T.assert_equal(#report.committed, 1, "a well-formed point must commit")
    local call = called(h, "look_at")
    T.assert_true(call ~= nil, "look_at must be reached")
    T.assert_equal(call.point.x, 1)
    T.assert_equal(call.point.z, 3)
end

--- The gate is deliberately THIN: a well-formed point is all this layer can honestly verify.
--- It does not know where the character may legally look, and inventing a check it cannot
--- perform would be worse than admitting the limit.
function M.test_a_malformed_point_is_refused_by_name()
    for _, bad in ipairs({
        { point = nil },
        { point = { x = 1, y = 2 } },
        { point = { x = "north", y = 2, z = 3 } },
        { point = "over there" },
    }) do
        local h = verbs_harness()
        local report = submit_and_commit(h, { type = "face", payload = bad })
        T.assert_equal(#report.rejected, 1, "a malformed point must be refused")
        T.assert_equal(report.rejected[1].gate, "face")
        T.assert_equal(report.rejected[1].reason, "malformed_point")
        T.assert_true(called(h, "look_at") == nil, "and must never reach the SDK")
    end
end

function M.test_a_face_intent_is_refused_when_the_sdk_lacks_look_at()
    local h = verbs_harness({ omit = { "look_at" } })
    local report = submit_and_commit(h, {
        type = "face", payload = { point = { x = 1, y = 2, z = 3 } },
    })
    T.assert_equal(#report.failed, 1, "an absent SDK verb is a named failure, not a silent no-op")
    T.assert_equal(report.failed[1].reason, "no_look_at")
end

-- ---------------------------------------------------------------------------
-- move -- MOVEMENT, and DECLARATIVE
-- ---------------------------------------------------------------------------

--- The heart of the declarative model: committing a `move` presses NOTHING. It records what
--- the holder wants; the reconciler drives the keys afterwards. There is no start/stop pair in
--- plugin hands, so there is no half of one to leak.
function M.test_a_move_intent_sets_desired_state_and_presses_no_key_at_commit()
    local h = verbs_harness()
    MovementRelease.release_all({})   -- known-stopped

    local pressed = {}
    local key_input = {
        move_forward_start = function() pressed[#pressed + 1] = "start" end,
        move_forward_stop = function() pressed[#pressed + 1] = "stop" end,
    }

    local report = submit_and_commit(h, {
        type = "move", payload = { keys = { move_forward = true } },
    })
    T.assert_equal(#report.committed, 1)
    T.assert_equal(#pressed, 0, "commit must not touch a key -- the reconciler does that")

    local desired = MovementRelease.desired()
    T.assert_true(desired ~= nil and desired.move_forward == true,
        "the desire must be recorded")

    MovementRelease.reconcile(key_input)
    T.assert_equal(#pressed, 1, "the reconciler is what presses")
    T.assert_equal(pressed[1], "start")

    MovementRelease.release_all(key_input)
end

function M.test_a_move_intent_with_stop_clears_the_desire()
    local h = verbs_harness()
    MovementRelease.set_desired({ move_forward = true })

    local report = submit_and_commit(h, { type = "move", payload = { stop = true } })
    T.assert_equal(#report.committed, 1)
    T.assert_true(MovementRelease.desired() == nil, "stop must clear the desire")
end

function M.test_a_move_intent_naming_an_unknown_key_is_refused_by_name()
    local h = verbs_harness()
    MovementRelease.release_all({})
    local report = submit_and_commit(h, {
        type = "move", payload = { keys = { jump = true } },
    })
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].gate, "move")
    T.assert_equal(report.rejected[1].reason, "unknown_movement_key")
    T.assert_true(MovementRelease.desired() == nil, "a refused move must not set a desire")
end

function M.test_a_move_intent_must_say_either_keys_or_stop()
    local h = verbs_harness()
    local report = submit_and_commit(h, { type = "move", payload = {} })
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].reason, "move_states_nothing")
end

-- ---------------------------------------------------------------------------
-- use_item -- ITEMS
-- ---------------------------------------------------------------------------

function M.test_a_use_item_intent_reaches_the_sdk()
    local h = verbs_harness()
    local report = submit_and_commit(h, { type = "use_item", payload = { item_id = 22829 } })

    T.assert_equal(#report.committed, 1)
    local call = called(h, "use_item")
    T.assert_true(call ~= nil)
    T.assert_equal(call.item_id, 22829)
end

function M.test_an_item_the_player_does_not_have_is_refused()
    local h = verbs_harness({ has_item = false })
    local report = submit_and_commit(h, { type = "use_item", payload = { item_id = 22829 } })
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].gate, "item")
    T.assert_equal(report.rejected[1].reason, "item_absent")
    T.assert_true(called(h, "use_item") == nil)
end

--- The old code tracked the 2-minute potion cooldown itself, on the blackboard. The SDK knows
--- the real answer, and a second source of truth is one that drifts.
function M.test_an_item_on_cooldown_is_refused()
    local h = verbs_harness({ item_cooldown = 42 })
    local report = submit_and_commit(h, { type = "use_item", payload = { item_id = 22829 } })
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].reason, "item_on_cooldown")
end

function M.test_a_use_item_intent_without_an_item_id_is_refused()
    local h = verbs_harness()
    local report = submit_and_commit(h, { type = "use_item", payload = {} })
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].reason, "missing_item_id")
end

--- Fail CLOSED, and say which check was missing. Same rule as `no_castable_check`: an absent
--- validator is not permission.
function M.test_a_missing_item_check_fails_closed_rather_than_assuming_yes()
    local h = verbs_harness({ omit_has_item = true })
    local report = submit_and_commit(h, { type = "use_item", payload = { item_id = 22829 } })
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].reason, "no_item_check")
end

-- ---------------------------------------------------------------------------
-- pet_command -- PET
-- ---------------------------------------------------------------------------

--- The unit is named SYMBOLICALLY and resolved here, one stage after the rotation asked. A
--- handle is valid only for the tick that produced it, so an intent that carried one would
--- reintroduce the exact staleness the frozen snapshot exists to prevent -- just wearing an
--- intent's clothes.
function M.test_a_pet_attack_resolves_the_symbolic_target_at_commit()
    local h = verbs_harness()
    local report = submit_and_commit(h, {
        type = "pet_command", payload = { command = "attack", unit = "target" },
    })

    T.assert_equal(#report.committed, 1)
    local call = called(h, "pet_attack")
    T.assert_true(call ~= nil)
    T.assert_true(call.unit == TARGET, "the symbolic ref must resolve to the live handle here")
end

function M.test_a_pet_cast_carries_its_spell_and_target()
    local h = verbs_harness()
    local report = submit_and_commit(h, {
        type = "pet_command", payload = { command = "cast", spell_id = 33395, unit = "target" },
    })
    T.assert_equal(#report.committed, 1)
    local call = called(h, "pet_cast")
    T.assert_equal(call.spell_id, 33395)
    T.assert_true(call.unit == TARGET)
end

function M.test_pet_passive_and_follow_are_separate_commands()
    local h = verbs_harness()
    submit_and_commit(h, { type = "pet_command", payload = { command = "passive" } })
    submit_and_commit(h, { type = "pet_command", payload = { command = "follow" } })

    T.assert_true(called(h, "set_pet_passive") ~= nil)
    T.assert_true(called(h, "set_pet_follow") ~= nil)
end

--- This is the conversion's entire return. Every one of these calls used to be
--- `pcall(core.input.pet_attack, target)` with the result thrown away: with no pet at all, the
--- old code did nothing and reported success.
function M.test_a_pet_command_without_a_pet_is_refused_by_name()
    local h = verbs_harness({ pet = false })
    local report = submit_and_commit(h, {
        type = "pet_command", payload = { command = "attack", unit = "target" },
    })
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].gate, "pet")
    T.assert_equal(report.rejected[1].reason, "no_pet")
    T.assert_true(called(h, "pet_attack") == nil)
end

function M.test_a_command_to_a_dead_pet_is_refused()
    local h = verbs_harness({ pet_alive = false })
    local report = submit_and_commit(h, {
        type = "pet_command", payload = { command = "attack", unit = "target" },
    })
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].reason, "pet_dead")
end

--- A closed vocabulary, for the same reason the unit reference is closed: an open one would be
--- an unvalidated string reaching an SDK surface from inside the commit stage.
function M.test_an_unknown_pet_command_is_refused()
    local h = verbs_harness()
    local report = submit_and_commit(h, {
        type = "pet_command", payload = { command = "dance" },
    })
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].reason, "unknown_pet_command")
end

function M.test_a_pet_attack_at_a_vanished_target_is_refused()
    local queue = IntentQueue:new()
    Executors.install({
        intent_queue = queue,
        timing = Timing:new({ now_ms = function() return 0 end }),
        spell_queue = spell_queue_double(),
        object_manager = {
            get_local_player = function()
                return { get_pet = function() return { is_alive = function() return true end } end }
            end,
        },
        unit_target = function() return nil end,
        spell_helper = { is_spell_castable = function() return true end },
        input = { pet_attack = function() error("must not be reached", 0) end },
    })
    queue:submit({
        type = "pet_command", owner = "rotations.mage_frost", band = Bands.BANDS.COMBAT.min,
        payload = { command = "attack", unit = "target" },
    })
    local report = queue:commit({})
    T.assert_equal(#report.rejected, 1)
    T.assert_equal(report.rejected[1].reason, "unit_unresolved")
end

-- ---------------------------------------------------------------------------
-- The generation-stamped UnitRef (ADR 08 §2.7, §6.1; Phase 4d D5)
-- ---------------------------------------------------------------------------
--
-- ================================================================================
-- WHAT THESE PIN, AND WHY THE LEASE GENERATION DOES NOT ALREADY COVER IT
-- ================================================================================
-- A guid is a VALUE, so it may ride in a payload -- but a value has no expiry, and that is the
-- whole hole. The lease generation cannot close it: a lease legitimately spans many ticks (its TTL
-- is counted in ticks), so an intent submitted in tick N+5 under a lease granted in tick N passes
-- the generation check by design. A guid CACHED in tick N and submitted in tick N+5 therefore
-- commits a packet aimed by reasoning five ticks old, and every existing check says yes.
--
-- So the ref carries its OWN stamp, minted by the kernel against the tick's frozen snapshot and
-- re-checked at commit against the snapshot COMMIT is running under. Two tests, deliberately a
-- pair: the refusal alone could be satisfied by a blanket no, and a blanket no would silently
-- disable every guid-addressed cast in the frost rotation.
--
-- ================================================================================
-- WHAT THESE TESTS CANNOT SEE
-- ================================================================================
--   * THEY SAY NOTHING ABOUT THE UNIT. A ref minted this tick proves only WHEN it was minted. The
--     mob may have died, moved out of range, or been replaced by another entity that inherited
--     nothing but the guid's stability. `unit_unresolved` (pinned separately, above) is the only
--     check that speaks to existence, and even that is a resolve, not a liveness proof.
--   * THEY DO NOT PROVE THE ROTATION MINTS. `frost_support.name_unit` is covered on its own side;
--     these drive the kernel through hand-built payloads, which is what makes the refusal
--     attributable to the executor rather than to the caller.

local ADD = { id = "low-health-add", get_guid = function() return "guid-add-1" end }

--- Mint through the KERNEL, exactly as a plugin would. Built by hand nowhere: a test that
--- hand-writes `{ unit_guid = ..., unit_ref_tick = ... }` would keep passing after the mint site
--- stopped producing that shape.
local function mint(unit, tick)
    return Units:new():mint_ref(Snapshot.empty(tick), unit)
end

function M.test_a_unit_ref_minted_last_tick_is_refused()
    local h = harness()
    local guid, stamp = mint(ADD, 7)
    h.queue:submit(cast_intent({
        payload = { spell_id = 116, unit_guid = guid, unit_ref_tick = stamp },
    }))
    -- COMMIT runs one tick later. The lease is irrelevant here -- the point is that a ref which
    -- survived into the next tick is refused even though everything else about the intent is fine.
    local report = h.queue:commit(Snapshot.empty(8))

    T.assert_equal(#report.committed, 0, "a ref minted last tick must not commit")
    T.assert_equal(#h.sq.calls, 0, "and nothing may reach the SDK boundary")
    local gate, reason = first_rejection(report)
    T.assert_equal(gate, "castable", "the refusal must name the gate that made it")
    T.assert_equal(reason, "stale_unit_ref",
        "with a reason distinguishable from `unit_unresolved` (the unit is gone) and "
        .. "`unstamped_unit_ref` (the caller never minted)")
end

--- THE POSITIVE TWIN. Without it, `stale_unit_ref` could be implemented as a blanket refusal of
--- every guid-addressed cast and this suite would still be green -- while the frost rotation, which
--- names EVERY cast target by guid, would stop casting entirely.
function M.test_a_unit_ref_minted_this_tick_commits()
    local h = harness()
    local guid, stamp = mint(ADD, 7)
    h.queue:submit(cast_intent({
        payload = { spell_id = 116, unit_guid = guid, unit_ref_tick = stamp },
    }))
    local report = h.queue:commit(Snapshot.empty(7))

    T.assert_equal(#report.committed, 1, "a ref minted this tick must commit: " ..
        tostring(report.rejected[1] and report.rejected[1].reason))
    T.assert_equal(#h.sq.calls, 1)
    T.assert_true(h.sq.calls[1].target == h.units_by_guid["guid-add-1"],
        "and must still resolve to the live handle, not to the guid string")
end

--- THE ESCAPE HATCH, CLOSED. An unstamped guid is the shape that existed before this deliverable:
--- resolved verbatim in any tick. It is refused rather than grandfathered, for the reason
--- `no_castable_check` is refused -- an absent check is not permission, and a stamp that may be
--- omitted is a stamp that is never enforced.
function M.test_a_guid_carried_without_a_generation_stamp_is_refused()
    local h = harness()
    h.queue:submit(cast_intent({ payload = { spell_id = 116, unit_guid = "guid-add-1" } }))
    local report = h.queue:commit(Snapshot.empty(7))

    T.assert_equal(#report.committed, 0)
    local gate, reason = first_rejection(report)
    T.assert_equal(gate, "castable")
    T.assert_equal(reason, "unstamped_unit_ref")
end

--- A snapshot that cannot say what tick it is fails CLOSED. The alternative -- treating an
--- unanswerable tick as "close enough" -- would make the whole check evaporate wherever the
--- snapshot is a stub, which is precisely where nobody is looking.
function M.test_a_ref_is_refused_when_the_snapshot_cannot_name_the_tick()
    local h = harness()
    local guid, stamp = mint(ADD, 7)
    h.queue:submit(cast_intent({
        payload = { spell_id = 116, unit_guid = guid, unit_ref_tick = stamp },
    }))
    local report = h.queue:commit({})

    T.assert_equal(#report.committed, 0)
    local _, reason = first_rejection(report)
    T.assert_equal(reason, "no_tick_index")
end

--- THE STAMP IS THE KERNEL'S, NOT THE CALLER'S. The caller hands over a handle and a snapshot; it
--- never chooses the number. Handing an OLD snapshot is therefore not a bypass -- it yields an old
--- stamp, which commit then refuses -- and that is the property this asserts.
function M.test_the_kernel_stamps_the_ref_from_the_snapshots_tick_index()
    local guid, stamp = mint(ADD, 42)
    T.assert_equal(guid, "guid-add-1")
    T.assert_equal(stamp, 42, "the stamp must be the snapshot's tick index, nothing else")

    local _, older = mint(ADD, 41)
    T.assert_equal(older, 41, "a caller reasoning against an older snapshot gets an older stamp")
end

--- FLAT SCALARS, NOT A NESTED REF TABLE. `IntentQueue:dedupe_key` flattens exactly ONE level with
--- `tostring(payload[k])`, so a `{ guid, generation }` table would key on its ADDRESS: two refs to
--- the SAME unit would dedupe as distinct, and the same ref submitted twice would not dedupe at
--- all. Pinned on the mint's return shape because that is what decides how callers store it.
function M.test_a_minted_ref_is_two_scalars_so_it_survives_dedupe()
    local guid, stamp = mint(ADD, 7)
    T.assert_true(type(guid) ~= "table", "the guid must be a scalar, not a wrapper table")
    T.assert_equal(type(stamp), "number", "and the stamp a plain number")

    -- Two intents naming the same unit in the same tick must collapse to one packet.
    local h = harness()
    for _ = 1, 2 do
        h.queue:submit(cast_intent({
            payload = { spell_id = 116, unit_guid = guid, unit_ref_tick = stamp },
        }))
    end
    local report = h.queue:commit(Snapshot.empty(7))
    T.assert_equal(#report.committed, 1, "identical refs must dedupe to one")
    T.assert_equal(#report.deduped, 1)
end

--- A handle with no `get_guid` mints NOTHING rather than a half-formed ref. The caller then has no
--- payload to build, which is the loud failure -- a ref carrying a stamp and a nil guid would be
--- refused one stage later as `no_cast_destination`, blaming the wrong thing.
function M.test_a_handle_that_cannot_name_itself_mints_no_ref()
    local guid, stamp = Units:new():mint_ref(Snapshot.empty(7), { id = "no-guid-here" })
    T.assert_nil(guid)
    T.assert_nil(stamp)

    local nothing = Units:new():mint_ref(Snapshot.empty(7), nil)
    T.assert_nil(nothing)
end

-- ---------------------------------------------------------------------------
-- The taxonomy itself
-- ---------------------------------------------------------------------------

--- ONE INTENT TYPE PER CHANNEL (§3.2). If this map ever gained a second channel for one type,
--- that intent would have no single authorising lease and the generation re-check at commit
--- would have nothing well-defined to validate against.
function M.test_every_intent_type_binds_to_exactly_one_channel()
    local ControlBrokerChannels = {}
    for _, c in ipairs(ControlBroker.CHANNELS) do ControlBrokerChannels[c] = true end

    local expected = {
        cast = "CASTING",
        target = "TARGETING",
        pet_command = "PET",
        use_item = "ITEMS",
        face = "FACING",
        move = "MOVEMENT",
    }

    for intent_type, channel in pairs(expected) do
        T.assert_equal(Executors.CHANNEL_FOR[intent_type], channel,
            intent_type .. " must be bound to " .. channel)
        T.assert_true(ControlBrokerChannels[channel] == true,
            channel .. " must be a real ControlBroker channel")
    end

    local count = 0
    for _ in pairs(Executors.CHANNEL_FOR) do count = count + 1 end
    T.assert_equal(count, 6, "six intent types, no more -- a seventh needs its own channel")
end

return M
