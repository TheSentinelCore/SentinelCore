-- tests/kernel/test_spell_catalog_gcd_truth.lua
-- The catalog's two GCD flags, pinned against the GAME DATA rather than against intuition.
--
-- ================================================================================
-- WHY THIS SUITE EXISTS: THE CATALOG IS AN AUTHORITY, AND IT WAS WRONG
-- ================================================================================
-- `frost_support.catalog_confirms_off_gcd` will not honour a rotation's `off_gcd` request unless
-- the catalog corroborates it. That makes the catalog load-bearing: an entry wrongly marked
-- `ogcd = true` is one action-side declaration away from sending a packet into a live global
-- cooldown, where the SERVER refuses it and the kernel's own tick report says it went fine.
--
-- Phase 4e audited all 64 catalog entries carrying ids against `spell_template` in
-- tbcmangos.sqlite (TBC 2.4.3). FOUR were wrong -- not the one that surfaced.
--
-- ================================================================================
-- THE TWO FLAGS ARE NOT COMPLEMENTS, AND THAT IS THE WHOLE POINT
-- ================================================================================
-- They answer different questions, and MaNGOS answers them from different columns:
--
--   `gcd`  -- "does casting this OPEN a global cooldown?"  Player::AddGCD reads
--             StartRecoveryTime and returns early when it is 0
--             (Emulators/Mangos - Classic TBC/src/game/Entities/Player.cpp).
--   `ogcd` -- "may this be sent WHILE one is running?"     WorldObject::HasGCD looks the spell's
--             own StartRecoveryCategory up in the live category map
--             (.../src/game/Entities/Object.cpp) -- so category 0 is never blocked, and category
--             133 is blocked by every ordinary 1.5s spell.
--
-- Avenging Wrath is the witness that they are independent: StartRecoveryCategory 133,
-- StartRecoveryTime 0. It opens NO global cooldown and is still BLOCKED by one. Treating either
-- flag as `not` the other gets it wrong in one direction or the other.
--
-- MEASURED (Id, StartRecoveryCategory, StartRecoveryTime):
--
--     Judgement        20271     0     0    opens none, never blocked   -> off the GCD
--     Counterspell      2139     0     0    opens none, never blocked   -> off the GCD
--     Cold Snap        11958     0     0    opens none, never blocked   -> off the GCD
--     Icy Veins        12472     0     0    opens none, never blocked   -> off the GCD
--     Avenging Wrath   31884   133     0    opens none, BLOCKED         -> NOT off the GCD
--     Ice Barrier      11426   133  1500    opens one,  BLOCKED         -> NOT off the GCD
--                      (13031/13032/13033/27134/33405 identical)
--
-- ================================================================================
-- WHAT THIS SUITE CANNOT SEE
-- ================================================================================
--  1. THE OTHER 60 ENTRIES. It pins the four the audit found wrong plus the two it confirmed
--     right. The audit that covered all 64 was a one-off script against a 300 MB sqlite file; it
--     is NOT re-run here, because the offline suite must load inside the Sylvannas sandbox, which
--     has no database and no `io`. A new entry added tomorrow is unaudited and this will not say so.
--  2. WHETHER THE SERVER AGREES. These are the values MaNGOS reads. A different core, a patched
--     database, or Blizzlike retail would answer differently, and nothing here would notice.
--  3. WHETHER ANY ROTATION ASKS. It pins what the catalog answers, not that a caller consults it.
--     `tests/rotations/mage_frost/test_frost_cast_intents.lua` owns the other authority.

local SpellCatalog = require("kernel/catalogs/spell")
local T = require("tests/test_util")

local M = {}

local function catalog()
    return SpellCatalog:new()
end

-- ---------------------------------------------------------------------------
-- The entry that surfaced
-- ---------------------------------------------------------------------------

--- Ice Barrier was `gcd = false, ogcd = true`, and BOTH halves were wrong.
---
--- It is a mage shield, and every mage shield triggers the global cooldown in TBC: all six ranks
--- carry StartRecoveryCategory 133 and StartRecoveryTime 1500. `frost_actions.queue_ice_barrier`
--- deliberately does not declare `off_gcd`, which is the only reason the wrong entry never granted a
--- live bypass -- one word added to that action and it would have.
function M.test_ice_barrier_is_on_the_global_cooldown()
    local c = catalog()
    T.assert_false(c:is_ogcd_spell("ice_barrier"),
        "Ice Barrier is StartRecoveryCategory 133 -- it may NOT be sent during a GCD")
    T.assert_true(c:is_gcd_spell("ice_barrier"),
        "and StartRecoveryTime 1500 -- casting it opens one")
end

--- Every rank, not just the one the audit printed. `resolve_best_rank` picks by level, so a level
--- gate could hand the executor a rank the catalog never checked.
function M.test_every_ice_barrier_rank_is_on_the_global_cooldown()
    local c = catalog()
    for _, id in ipairs({ 11426, 13031, 13032, 13033, 27134, 33405 }) do
        T.assert_false(c:is_ogcd_spell(id), "rank " .. id .. " must not claim the bypass")
    end
end

-- ---------------------------------------------------------------------------
-- The witness that the two flags are independent
-- ---------------------------------------------------------------------------

--- THE ENTRY THAT PROVES THE FLAGS CANNOT BE DERIVED FROM ONE ANOTHER.
---
--- Avenging Wrath opens no global cooldown (StartRecoveryTime 0) yet is blocked by one
--- (StartRecoveryCategory 133). If anyone ever "simplifies" the catalog by making `ogcd` mean
--- `not gcd`, this is the case that breaks -- and it breaks in the dangerous direction, granting a
--- bypass to a spell the server will refuse.
function M.test_avenging_wrath_opens_no_gcd_and_is_still_blocked_by_one()
    local c = catalog()
    T.assert_false(c:is_gcd_spell("avenging_wrath"),
        "StartRecoveryTime 0 -- casting it opens no global cooldown")
    T.assert_false(c:is_ogcd_spell("avenging_wrath"),
        "StartRecoveryCategory 133 -- and it is still BLOCKED by one. Both false, deliberately.")
end

function M.test_the_two_flags_are_not_complements()
    local c = catalog()
    T.assert_equal(c:is_gcd_spell("avenging_wrath"), c:is_ogcd_spell("avenging_wrath"),
        "at least one entry must answer the SAME to both, or the pair is derivable and the "
        .. "distinction this catalog draws is fictional")
end

-- ---------------------------------------------------------------------------
-- The genuinely off-GCD abilities
-- ---------------------------------------------------------------------------

--- Judgement and Counterspell are off the global cooldown in TBC -- StartRecoveryCategory 0 and
--- StartRecoveryTime 0 both. The catalog had them as `gcd = true`, which made the kernel open a
--- 1.5-second window after a cast that costs none: over-gating, so the safe direction, but it holds
--- the paladin's next ability for a window the server never imposed.
function M.test_judgement_is_off_the_global_cooldown()
    local c = catalog()
    T.assert_false(c:is_gcd_spell("judgement"), "StartRecoveryTime 0 -- it opens no GCD")
    T.assert_true(c:is_ogcd_spell("judgement"), "StartRecoveryCategory 0 -- it is never blocked")
end

function M.test_counterspell_is_off_the_global_cooldown()
    local c = catalog()
    T.assert_false(c:is_gcd_spell("counterspell"), "StartRecoveryTime 0 -- it opens no GCD")
    T.assert_true(c:is_ogcd_spell("counterspell"), "StartRecoveryCategory 0 -- never blocked")
end

--- The two the audit CONFIRMED, kept so a future edit cannot quietly flip them while fixing the
--- others. These are the only two abilities in the frost off-GCD tree that may legally bypass.
function M.test_cold_snap_and_icy_veins_really_are_off_the_gcd()
    local c = catalog()
    for _, key in ipairs({ "cold_snap", "icy_veins" }) do
        T.assert_true(c:is_ogcd_spell(key), key .. " is StartRecoveryCategory 0")
        T.assert_false(c:is_gcd_spell(key), key .. " is StartRecoveryTime 0")
    end
end

-- ---------------------------------------------------------------------------
-- The predicate the rotation is required to ask
-- ---------------------------------------------------------------------------

--- `frost_support` asks `is_ogcd_spell`, never `is_gcd_spell`, and the choice is load-bearing:
--- both return a plain boolean and neither can say "I have never heard of this key", but they
--- default in OPPOSITE directions. An unknown key is exactly what a renamed spell or a stale
--- catalog produces.
function M.test_an_unknown_key_refuses_the_bypass_rather_than_granting_it()
    local c = catalog()
    T.assert_false(c:is_ogcd_spell("no_such_spell_key"),
        "an unknown key must read as 'not off the GCD' -- the safe default")
    T.assert_false(c:is_gcd_spell("no_such_spell_key"),
        "whereas is_gcd_spell answers false too, which would read as 'not on the GCD' and GRANT "
        .. "the bypass -- which is why the rotation must not ask this one")
end

return M
