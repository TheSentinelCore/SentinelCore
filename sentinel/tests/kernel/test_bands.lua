-- tests/kernel/test_bands.lua
-- ADR 08 §6.2: "Fixed bands so numbers are not folklore. Bare integers are the documented
-- failure mode in extensible systems -- LazyBot's priorities are magic numbers scattered
-- across state classes with nothing preventing collisions."
--
--   90-99  SAFETY      death, corpse run, stuck, zone transition, loading screen
--   70-89  SURVIVAL    defensive CDs, emergency heal, flee, escape
--   50-69  COMBAT      rotation, pull
--   30-49  GOAL        the active activity: grind / quest / gather
--   10-29  HOUSEKEEP   loot, vendor, repair, mail, mount
--    0-9   IDLE        rest, buff, afk
--
-- Two contracts:
--   * A caller declares { band = "COMBAT", offset = 0 } -- never a bare 55.
--   * "the kernel REJECTS a manifest requesting a band its tier is not permitted -- an
--     Ambient plugin cannot declare SAFETY." Refusal is by name, not by nil.

local Bands = require("kernel/bands")
local T = require("tests/test_util")

local M = {}

function M.test_the_six_bands_tile_0_to_99_without_gaps_or_overlap()
    local covered = {}
    for _, band in ipairs(Bands.ORDER) do
        local range = Bands.BANDS[band]
        T.assert_not_nil(range, band .. " must have a range")
        for p = range.min, range.max do
            T.assert_nil(covered[p], "priority " .. p .. " is claimed by two bands")
            covered[p] = band
        end
    end
    for p = 0, 99 do
        T.assert_not_nil(covered[p], "priority " .. p .. " belongs to no band")
    end
    T.assert_equal(#Bands.ORDER, 6)
end

function M.test_order_runs_highest_authority_first()
    T.assert_equal(Bands.ORDER[1], "SAFETY")
    T.assert_equal(Bands.ORDER[#Bands.ORDER], "IDLE")
end

function M.test_resolve_turns_a_named_band_and_offset_into_a_priority()
    T.assert_equal(Bands.resolve({ band = "COMBAT", offset = 0 }), 50)
    T.assert_equal(Bands.resolve({ band = "COMBAT", offset = 5 }), 55)
    T.assert_equal(Bands.resolve({ band = "SAFETY", offset = 9 }), 99)
    T.assert_equal(Bands.resolve({ band = "IDLE" }), 0, "a missing offset defaults to 0")
end

function M.test_an_offset_past_the_band_ceiling_is_refused_by_name()
    local priority, reason = Bands.resolve({ band = "COMBAT", offset = 20 })
    T.assert_nil(priority, "offset 20 in a 20-wide band overflows into SURVIVAL")
    T.assert_equal(reason, "offset_out_of_band")
end

function M.test_a_negative_offset_is_refused()
    local priority, reason = Bands.resolve({ band = "COMBAT", offset = -1 })
    T.assert_nil(priority)
    T.assert_equal(reason, "offset_out_of_band")
end

function M.test_an_unknown_band_is_refused_by_name()
    local priority, reason = Bands.resolve({ band = "URGENT", offset = 0 })
    T.assert_nil(priority)
    T.assert_equal(reason, "unknown_band")
end

--- A bare integer is exactly what §6.2 exists to prevent.
function M.test_a_bare_integer_priority_is_refused()
    local priority, reason = Bands.resolve(55)
    T.assert_nil(priority, "a bare integer must not be accepted as a priority declaration")
    T.assert_equal(reason, "band_must_be_named")

    local p2, r2 = Bands.resolve({ priority = 55 })
    T.assert_nil(p2)
    T.assert_equal(r2, "band_must_be_named")
end

function M.test_name_for_maps_a_priority_back_to_its_band()
    T.assert_equal(Bands.name_for(99), "SAFETY")
    T.assert_equal(Bands.name_for(90), "SAFETY")
    T.assert_equal(Bands.name_for(89), "SURVIVAL")
    T.assert_equal(Bands.name_for(55), "COMBAT")
    T.assert_equal(Bands.name_for(30), "GOAL")
    T.assert_equal(Bands.name_for(10), "HOUSEKEEP")
    T.assert_equal(Bands.name_for(0), "IDLE")
    T.assert_nil(Bands.name_for(100), "out-of-range priorities belong to no band")
    T.assert_nil(Bands.name_for(-1))
end

-- ---------------------------------------------------------------------------
-- Tier permissions (ADR 08 §6.2)
-- ---------------------------------------------------------------------------

--- The one hard constraint the ADR states outright.
function M.test_an_ambient_plugin_cannot_declare_safety()
    local ok, reason = Bands.permits("ambient", "SAFETY")
    T.assert_false(ok, "ADR 08 §6.2: an Ambient plugin cannot declare SAFETY")
    T.assert_equal(reason, "band_not_permitted_for_tier")
end

--- ASSERTION CHANGED, deliberately. This test previously read
--- `assert_true(Bands.permits("ambient", "IDLE"))`, granting the ambient tier the IDLE band.
--- That was wrong: an ambient plugin which cannot acquire ANY channel is precisely why that
--- tier is safe to load arbitrarily -- it can observe and advise but cannot move, cast, target
--- or open a window. Granting it IDLE would make "ambient" a privilege level rather than the
--- absence of one, and the argument for loading unknown ambient plugins freely would collapse.
function M.test_ambient_may_declare_no_band_at_all()
    for _, band in ipairs(Bands.ORDER) do
        local ok, reason = Bands.permits("ambient", band)
        T.assert_false(ok, "ambient must not be permitted " .. band)
        T.assert_equal(reason, "band_not_permitted_for_tier")
    end
end

--- The same property, stated as the thing that actually matters: an ambient manifest cannot
--- resolve a priority, so it can never reach the broker with one.
function M.test_an_ambient_tier_cannot_resolve_any_priority()
    for _, band in ipairs(Bands.ORDER) do
        local priority = Bands.resolve({ band = band, offset = 0, tier = "ambient" })
        T.assert_nil(priority, "ambient must not resolve a priority in " .. band)
    end
end

--- `strategy` is the other tier that holds nothing (§5.3: strategies choose, they do not act).
function M.test_strategy_may_declare_no_band_either()
    for _, band in ipairs(Bands.ORDER) do
        T.assert_false(Bands.permits("strategy", band), "strategy must not be permitted " .. band)
    end
end

--- Behaviours are where the safety net lives (§5.2: anti-stuck and corpse recovery run at
--- band 90-99 "even though they are plugins").
function M.test_a_behavior_may_declare_safety()
    T.assert_true(Bands.permits("behavior", "SAFETY"))
end

function M.test_a_rotation_may_declare_combat_and_survival_but_not_goal()
    T.assert_true(Bands.permits("rotation", "COMBAT"))
    T.assert_true(Bands.permits("rotation", "SURVIVAL"), "defensive cooldowns are 70-89")
    T.assert_false(Bands.permits("rotation", "GOAL"), "a rotation is not the goal")
end

function M.test_an_unknown_tier_is_refused_rather_than_permitted()
    local ok, reason = Bands.permits("wizard", "IDLE")
    T.assert_false(ok, "an unrecognised tier must fail closed")
    T.assert_equal(reason, "unknown_tier")
end

function M.test_resolve_enforces_tier_when_one_is_given()
    local priority, reason = Bands.resolve({ band = "SAFETY", offset = 0, tier = "ambient" })
    T.assert_nil(priority)
    T.assert_equal(reason, "band_not_permitted_for_tier")

    T.assert_equal(Bands.resolve({ band = "SAFETY", offset = 0, tier = "behavior" }), 90)
end

-- ---------------------------------------------------------------------------
-- spell_queue mapping (ADR 08 §6.3) -- exposed as DATA, not used yet
-- ---------------------------------------------------------------------------

function M.test_spell_queue_mapping_is_available_as_data()
    T.assert_equal(Bands.SPELL_QUEUE_PRIORITY.SAFETY, 7, "documented as the interrupt slot")
    T.assert_equal(Bands.SPELL_QUEUE_PRIORITY.SURVIVAL, 7, "reactive, must not queue behind rotation")
    T.assert_equal(Bands.SPELL_QUEUE_PRIORITY.COMBAT, 1, 'the documented "everything you author" value')
    T.assert_equal(Bands.SPELL_QUEUE_PRIORITY.GOAL, 1)
    T.assert_equal(Bands.SPELL_QUEUE_PRIORITY.HOUSEKEEP, 1)
    T.assert_equal(Bands.SPELL_QUEUE_PRIORITY.IDLE, 1)
end

--- Priority 9 belongs to the human at the keyboard and Sentinel never emits it.
function M.test_nine_is_reserved_and_never_produced()
    T.assert_equal(Bands.RESERVED_PLAYER_SPELL_QUEUE_PRIORITY, 9)
    for p = 0, 99 do
        T.assert_true(Bands.spell_queue_priority(p) ~= 9,
            "priority " .. p .. " must never map to the player's reserved slot")
    end
end

function M.test_spell_queue_priority_agrees_with_the_band_table()
    for _, band in ipairs(Bands.ORDER) do
        local range = Bands.BANDS[band]
        T.assert_equal(Bands.spell_queue_priority(range.min), Bands.SPELL_QUEUE_PRIORITY[band],
            band .. " min must map consistently")
        T.assert_equal(Bands.spell_queue_priority(range.max), Bands.SPELL_QUEUE_PRIORITY[band],
            band .. " max must map consistently")
    end
end

--- The Phase 1 IntentQueue shipped its own copy of this mapping. There must be exactly one
--- authority for it, or the two drift and gating silently disagrees with arbitration.
function M.test_intent_queue_delegates_to_this_single_authority()
    local IntentQueue = require("kernel/intent_queue")
    for p = 0, 99 do
        T.assert_equal(IntentQueue.spell_queue_priority(p), Bands.spell_queue_priority(p),
            "IntentQueue and Bands must not hold independent copies of the §6.3 mapping")
    end
end

return M
