local SpellCatalog = {}
SpellCatalog.__index = SpellCatalog

-- ============================================================================
-- `gcd` AND `ogcd` ARE TWO DIFFERENT QUESTIONS, NOT ONE FLAG AND ITS NEGATION
-- ============================================================================
-- This is stated HERE, at the data, and not only where it is enforced -- the rule was previously
-- discoverable only by reading `frost_support.catalog_confirms_off_gcd`, which is a plugin, in a
-- different package, that a catalog editor has no reason to open.
--
--   `gcd`  -- does casting this OPEN a global cooldown?   MaNGOS `Player::AddGCD` takes its
--             duration from StartRecoveryTime and returns early when it is 0.
--   `ogcd` -- may this be sent WHILE one is running?      MaNGOS `WorldObject::HasGCD` looks the
--             spell's own StartRecoveryCategory up in the live category map, so category 0 is
--             never blocked and category 133 is blocked by every ordinary 1.5s spell.
--
-- AVENGING WRATH IS THE WITNESS THAT THEY ARE INDEPENDENT: category 133, recovery time 0. It opens
-- no global cooldown AND is blocked by one -- both flags false. Deriving either from the other gets
-- this wrong, and gets it wrong in the direction that sends a packet the server refuses.
--
-- ============================================================================
-- THE TWO-AUTHORITY RULE THIS TABLE IS ONE HALF OF
-- ============================================================================
-- An off-GCD bypass requires BOTH authorities to agree: the rotation's action declares
-- `opts.off_gcd`, AND this table corroborates it via `is_ogcd_spell`. The `AND` is directional --
-- either authority being wrong on its own CLOSES the gate, so drift can only ever cost a delayed
-- cast, never an illegal one. Do not "simplify" it to one list: a catalog-only rule would have
-- granted Ice Barrier a bypass for three phases, and a rotation-only list is the drift this table
-- exists to prevent.
--
-- Callers must ask `is_ogcd_spell`, never `is_gcd_spell`, for a bypass decision. Both return a
-- plain boolean and neither can say "unknown key", but they default in opposite directions:
-- `is_gcd_spell("typo")` is false, which reads as "not on the GCD" and GRANTS the bypass.
--
-- ============================================================================
-- AUDITED IN PHASE 4E -- FOUR OF THE 64 ENTRIES WITH IDS WERE WRONG
-- ============================================================================
-- Every id here was cross-checked against `spell_template` in tbcmangos.sqlite (TBC 2.4.3):
--
--     Judgement       20271     cat 0    time    0   ->  gcd=false ogcd=true   (was gcd=true)
--     Counterspell     2139     cat 0    time    0   ->  gcd=false ogcd=true   (was gcd=true)
--     Avenging Wrath  31884     cat 133  time    0   ->  gcd=false ogcd=FALSE  (was ogcd=true)
--     Ice Barrier     11426+    cat 133  time 1500   ->  gcd=TRUE  ogcd=FALSE  (was both inverted)
--
-- The pattern is worth naming: the flags had been set from intuition about whether something felt
-- like a rotational ability, not from the data. `tests/kernel/test_spell_catalog_gcd_truth.lua`
-- pins all six, and states what that audit could not see.
--
-- WHAT THIS TABLE CANNOT SEE: the audit was a one-off script against a 300 MB sqlite file, and it
-- is not re-runnable from the offline suite -- the Sylvannas sandbox has no database and no `io`.
-- An entry added after Phase 4e is UNAUDITED, and nothing here will say so.
--
-- ============================================================================
-- THE `ranks` ARRAYS ARE NOW PINNED TOO -- FOUR OF THE 37 WERE WRONG
-- ============================================================================
-- The Phase 4e audit above covered the FLAGS, not the arrays, and the arrays were worse. Order and
-- membership are both load-bearing: `resolve_best_rank` / `resolve_known_rank` walk the array from
-- the HIGHEST INDEX down through `core.spell_book`, so an id the player cannot know is skipped in
-- silence and a rank the array omits is unreachable. Nothing raises. Measured against `spell_chain`
-- joined to `spell_template`:
--
--     seal_of_righteousness   held 3 JUDGEMENT of Righteousness ids + the hidden proc rank 9, and
--                             omitted real ranks 7-9  ->  a level-70 paladin cast RANK 6 (level 42)
--     fireball                omitted rank 14 (38692, level 70)   ->  cast rank 13
--     frost_ward              omitted rank 6  (32796, level 70)   ->  cast rank 5
--     conjure_water           had the 37420/27090 tail INVERTED   ->  conjured rank 8, not 9
--
-- `tests/kernel/test_catalog_rank_chains.lua` now compares EVERY array in this file and in
-- aura.lua against `tests/fixtures/spell_chain_tbc243.lua`, which
-- `sentinel/tools/regen_catalog_chain_fixture.py` generates from the database. An array added
-- without a fixture entry FAILS rather than passing unaudited -- that is the hole Phase 4e left.
-- What the fixture cannot prove is drift against a swapped database; only `--check` sees that.
local SPELLS = {
    seal_of_blood = { key = "seal_of_blood", id = 31892, gcd = true, description = "Seal of Blood" },
    seal_of_command = { key = "seal_of_command", ranks = { 20375, 20915, 20918, 20919, 20920, 27170 }, gcd = true, description = "Seal of Command" },
    -- Ten ranks, and the array here had FIVE of them wrong. 20284/20285/20286 are JUDGEMENT of
    -- Righteousness 6-8 -- a different spell -- and 27156 is the hidden BaseLevel-0 rank 9 from the
    -- SECOND same-named chain (first_spell 25742, Attributes 2359296), the seal's damage proc, never
    -- in a spellbook. Real ranks 7-9 (20292 lvl 50, 20293 lvl 58, 27155 lvl 66) were absent, so a
    -- level-70 paladin fell past four unreachable ids to 20291 -- Rank 6, level 42. 21084 is rank 2:
    -- it has no `spell_chain` row of its own and is reachable only as 20287's prev_spell.
    seal_of_righteousness = { key = "seal_of_righteousness", ranks = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293, 27155 }, gcd = true, description = "Seal of Righteousness" },
    judgement = { key = "judgement", id = 20271, gcd = false, ogcd = true, description = "Judgement" },  -- cat 0 / time 0: off the GCD in TBC
    judgement_of_blood = { key = "judgement_of_blood", id = 31898, gcd = false, description = "Judgement of Blood proc" },
    judgement_of_command = { key = "judgement_of_command", id = 27171, gcd = false, description = "Judgement of Command proc" },
    crusader_strike = { key = "crusader_strike", id = 35395, gcd = true, description = "Crusader Strike" },
    avenging_wrath = { key = "avenging_wrath", id = 31884, gcd = false, ogcd = false, description = "Avenging Wrath" },  -- cat 133 / time 0: opens no GCD, still BLOCKED by one
    consecration = { key = "consecration", ranks = { 26573, 20116, 20922, 20923, 20924, 27173 }, gcd = true, description = "Consecration" },
    blessing_of_might = { key = "blessing_of_might", ranks = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140 }, gcd = true, description = "Blessing of Might" },
    blessing_of_kings = { key = "blessing_of_kings", id = 20217, gcd = true, description = "Blessing of Kings" },
    retribution_aura = { key = "retribution_aura", ranks = { 7294, 10298, 10299, 10300, 10301, 27150 }, gcd = true, description = "Retribution Aura" },
    vengeance_talent = { key = "vengeance_talent", ranks = { 20049, 20056, 20057, 20058, 20059 }, gcd = false, description = "Vengeance talent" },
    vengeance_proc = { key = "vengeance_proc", ranks = { 20050, 20052, 20053, 20054, 20055 }, gcd = false, description = "Vengeance proc aura" },
    hammer_of_wrath = { key = "hammer_of_wrath", ranks = { 24275, 24274, 24239, 27180 }, gcd = true, description = "Hammer of Wrath" },
    hammer_of_justice = { key = "hammer_of_justice", ranks = { 853, 5588, 5589, 10308 }, gcd = true, description = "Hammer of Justice" },
    repentance = { key = "repentance", id = 20066, gcd = true, description = "Repentance" },

    -- Mage: Frost Combat
    frostbolt = { key = "frostbolt", ranks = { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304, 27071, 27072, 38697 }, gcd = true, description = "Frostbolt" },
    frost_nova = { key = "frost_nova", ranks = { 122, 865, 6131, 10230, 27088 }, gcd = true, description = "Frost Nova" },
    cone_of_cold = { key = "cone_of_cold", ranks = { 120, 8492, 10159, 10160, 10161, 27087 }, gcd = true, description = "Cone of Cold" },
    blizzard = { key = "blizzard", ranks = { 10, 6141, 8427, 10185, 10186, 10187, 27085 }, gcd = true, description = "Blizzard" },
    ice_lance = { key = "ice_lance", id = 30455, gcd = true, description = "Ice Lance" },

    -- Mage: Fire/Arcane Combat
    -- Rank 14 (38692, level 70) was missing: the array stopped at rank 13, level 66.
    fireball = { key = "fireball", ranks = { 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306, 27070, 38692 }, gcd = true, description = "Fireball" },
    fire_blast = { key = "fire_blast", ranks = { 2136, 2137, 2138, 8412, 8413, 10197, 10199, 27078, 27079 }, gcd = true, description = "Fire Blast" },
    counterspell = { key = "counterspell", id = 2139, gcd = false, ogcd = true, description = "Counterspell" },  -- cat 0 / time 0: off the GCD in TBC

    -- Mage: Defensive
    ice_barrier = { key = "ice_barrier", ranks = { 11426, 13031, 13032, 13033, 27134, 33405 }, gcd = true, ogcd = false, description = "Ice Barrier" },  -- cat 133 / time 1500: a mage shield is ON the GCD
    ice_block = { key = "ice_block", id = 45438, gcd = true, description = "Ice Block" },
    blink = { key = "blink", id = 1953, gcd = true, description = "Blink" },
    mana_shield = { key = "mana_shield", ranks = { 1463, 8494, 8495, 10191, 10192, 10193, 27131 }, gcd = true, description = "Mana Shield" },

    -- Mage: Cooldowns
    evocation = { key = "evocation", id = 12051, gcd = true, description = "Evocation" },
    cold_snap = { key = "cold_snap", id = 11958, gcd = false, ogcd = true, description = "Cold Snap" },
    icy_veins = { key = "icy_veins", id = 12472, gcd = false, ogcd = true, description = "Icy Veins" },

    -- Mage: Buffs
    frost_armor = { key = "frost_armor", ranks = { 168, 7300, 7301 }, gcd = true, description = "Frost Armor" },
    ice_armor = { key = "ice_armor", ranks = { 7302, 7320, 10219, 10220, 27124 }, gcd = true, description = "Ice Armor" },
    arcane_intellect = { key = "arcane_intellect", ranks = { 1459, 1460, 1461, 10156, 10157, 27126 }, gcd = true, description = "Arcane Intellect" },

    -- Mage: Conjure
    conjure_food = { key = "conjure_food", ranks = { 587, 597, 990, 6129, 10144, 10145, 28612, 33717 }, gcd = true, description = "Conjure Food" },
    -- The tail was INVERTED. 37420 is rank 8 (level 65) and 27090 is rank 9 (level 70) -- id order
    -- is not rank order across the TBC id ranges. The resolvers read the highest INDEX as the
    -- highest RANK, so the old array made a level-70 mage conjure rank 8 water.
    conjure_water = { key = "conjure_water", ranks = { 5504, 5505, 5506, 6127, 10138, 10139, 10140, 37420, 27090 }, gcd = true, description = "Conjure Water" },

    -- Mage: CC / AoE / Utility
    polymorph = { key = "polymorph", ranks = { 118, 12824, 12825, 12826 }, gcd = true, description = "Polymorph" },
    spellsteal = { key = "spellsteal", id = 30449, gcd = true, description = "Spellsteal" },
    arcane_explosion = { key = "arcane_explosion", ranks = { 1449, 8437, 8438, 8439, 10201, 10202, 27080, 27082 }, gcd = true, description = "Arcane Explosion" },
    flamestrike = { key = "flamestrike", ranks = { 2120, 2121, 8422, 8423, 10215, 10216, 27086 }, gcd = true, description = "Flamestrike" },
    scorch = { key = "scorch", ranks = { 2948, 8444, 8445, 8446, 10205, 10206, 10207, 27073, 27074 }, gcd = true, description = "Scorch" },
    dragons_breath = { key = "dragons_breath", ranks = { 31661, 33041, 33042, 33043 }, gcd = true, description = "Dragon's Breath" },
    summon_water_elemental = { key = "summon_water_elemental", id = 31687, gcd = true, description = "Summon Water Elemental" },

    -- Mage: Defensive / Utility
    -- Rank 6 (32796, level 70) was missing: the array stopped at rank 5, level 60.
    frost_ward = { key = "frost_ward", ranks = { 6143, 8461, 8462, 10177, 28609, 32796 }, gcd = true, description = "Frost Ward" },
    fire_ward = { key = "fire_ward", ranks = { 543, 8457, 8458, 10223, 10225, 27128 }, gcd = true, description = "Fire Ward" },
    invisibility = { key = "invisibility", id = 66, gcd = true, description = "Invisibility" },
    mage_armor = { key = "mage_armor", ranks = { 6117, 22782, 22783, 27125 }, gcd = true, description = "Mage Armor" },
    molten_armor = { key = "molten_armor", id = 30482, gcd = true, description = "Molten Armor" },

    -- Mage: Conjure Mana Gems
    conjure_mana_agate = { key = "conjure_mana_agate", id = 759, gcd = true, description = "Conjure Mana Agate" },
    conjure_mana_jade = { key = "conjure_mana_jade", id = 3552, gcd = true, description = "Conjure Mana Jade" },
    conjure_mana_citrine = { key = "conjure_mana_citrine", id = 10053, gcd = true, description = "Conjure Mana Citrine" },
    conjure_mana_ruby = { key = "conjure_mana_ruby", id = 10054, gcd = true, description = "Conjure Mana Ruby" },
    conjure_mana_emerald = { key = "conjure_mana_emerald", id = 27101, gcd = true, description = "Conjure Mana Emerald" },

    -- Warlock: Affliction TBC leveling (Unit D)
    -- Rank arrays extracted from tbcmangos.sqlite via the regen query documented above
    -- (SELECT spell_id, rank FROM spell_chain WHERE first_spell = <base_id> ORDER BY rank),
    -- run per-spell as:
    --   SELECT c.spell_id, c.rank FROM spell_chain c JOIN spell_template t ON t.Id=c.spell_id
    --   WHERE t.SpellName='<NAME>' ORDER BY c.rank;
    -- Corruption anchor verified: 172,6222,6223,7648,11671,11672,25311,27216 (rank 1..8).
    corruption = { key = "corruption", ranks = { 172, 6222, 6223, 7648, 11671, 11672, 25311, 27216 }, gcd = true, description = "Corruption" },
    curse_of_agony = { key = "curse_of_agony", ranks = { 980, 1014, 6217, 11711, 11712, 11713, 27218 }, gcd = true, description = "Curse of Agony" },
    immolate = { key = "immolate", ranks = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309, 27215 }, gcd = true, description = "Immolate" },
    shadow_bolt = { key = "shadow_bolt", ranks = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307, 27209 }, gcd = true, description = "Shadow Bolt" },
    drain_life = { key = "drain_life", ranks = { 689, 699, 709, 7651, 11699, 11700, 27219, 27220 }, gcd = true, description = "Drain Life" },
    drain_soul = { key = "drain_soul", ranks = { 1120, 8288, 8289, 11675, 27217 }, gcd = true, description = "Drain Soul" },
    life_tap = { key = "life_tap", ranks = { 1454, 1455, 1456, 11687, 11688, 11689, 27222 }, gcd = true, description = "Life Tap" },
    curse_of_weakness = { key = "curse_of_weakness", ranks = { 702, 1108, 6205, 7646, 11707, 11708, 27224, 30909 }, gcd = true, description = "Curse of Weakness" },
    -- No spell_chain row (single-rank pet summon); confirmed via spell_template directly
    -- (SELECT Id, SpellName, BaseLevel FROM spell_template WHERE SpellName='Summon Voidwalker'),
    -- id 697 is the player-trained rank-1 (BaseLevel 10); other ids returned by that query are
    -- NPC/quest-script duplicates (BaseLevel 1), not the trainer-taught spell.
    summon_voidwalker = { key = "summon_voidwalker", id = 697, gcd = true, description = "Summon Voidwalker" },
    -- Ranged auto-attack finisher shared by all classes with a wand equipped.
    shoot = { key = "shoot", id = 5019, gcd = false, description = "Shoot (wand)" },
}

local function shallow_copy(src)
    local out = {}
    for key, value in pairs(src) do
        if type(value) == "table" then
            local sub = {}
            for i = 1, #value do
                sub[i] = value[i]
            end
            out[key] = sub
        else
            out[key] = value
        end
    end
    return out
end

function SpellCatalog:new()
    local o = setmetatable({}, SpellCatalog)
    o._spells = {}
    o._id_index = {}
    for key, data in pairs(SPELLS) do
        o._spells[key] = shallow_copy(data)
        if data.id then
            o._id_index[data.id] = key
        end
        if data.ranks then
            for _, spell_id in ipairs(data.ranks) do
                o._id_index[spell_id] = key
            end
        end
    end
    return o
end

function SpellCatalog:get(key)
    return self._spells[key]
end

function SpellCatalog:all()
    return self._spells
end

function SpellCatalog:find_key_by_id(spell_id)
    return self._id_index[tonumber(spell_id) or -1]
end

function SpellCatalog:resolve_best_rank(key)
    local spell = self:get(key)
    if not spell then
        return nil
    end
    if spell.id then
        if core and core.spell_book and core.spell_book.has_spell then
            local ok, known = pcall(core.spell_book.has_spell, spell.id)
            if ok and known then return spell.id end
            return nil
        end
        return spell.id
    end
    if spell.ranks and #spell.ranks > 0 then
        if core and core.spell_book and core.spell_book.has_spell then
            for i = #spell.ranks, 1, -1 do
                local ok, known = pcall(core.spell_book.has_spell, spell.ranks[i])
                if ok and known then return spell.ranks[i] end
            end
            return nil
        end
        return spell.ranks[#spell.ranks]
    end
    return nil
end

function SpellCatalog:resolve_lowest_rank(key)
    local spell = self:get(key)
    if not spell then
        return nil
    end
    if spell.id then
        if core and core.spell_book and core.spell_book.has_spell then
            local ok, known = pcall(core.spell_book.has_spell, spell.id)
            if ok and known then return spell.id end
            return nil
        end
        return spell.id
    end
    if spell.ranks and #spell.ranks > 0 then
        if core and core.spell_book and core.spell_book.has_spell then
            for i = 1, #spell.ranks do
                local ok, known = pcall(core.spell_book.has_spell, spell.ranks[i])
                if ok and known then return spell.ranks[i] end
            end
            return nil
        end
        return spell.ranks[1]
    end
    return nil
end

-- Extraction query used to (re)generate rank arrays from tbcmangos.sqlite at authoring time
-- (offline-only; the runtime never touches sqlite -- see design D-rank-resolution):
--   SELECT spell_id, rank FROM spell_chain WHERE first_spell = <base_id> ORDER BY rank;
-- Cross-check level curve via spell_template.SpellName/BaseLevel. Regeneration is manual,
-- not a build step.

-- Returns true iff `spell_id` is currently TRAINED, per core.spell_book. Checks
-- is_spell_learned first (spellbook.md:227 -- the reliable signal for talent-modified ranks),
-- falling back to is_spell_known. When core.spell_book is unavailable (offline/legacy harness),
-- treat as known -- mirrors resolve_best_rank/resolve_lowest_rank's existing fallback behavior.
local function is_trained(spell_id)
    if not (core and core.spell_book) then
        return true
    end
    if core.spell_book.is_spell_learned then
        local ok, learned = pcall(core.spell_book.is_spell_learned, spell_id)
        if ok and learned then
            return true
        end
    end
    if core.spell_book.is_spell_known then
        local ok, known = pcall(core.spell_book.is_spell_known, spell_id)
        if ok and known then
            return true
        end
    end
    return false
end

-- Kept SEPARATE from resolve_best_rank (which gates on core.spell_book.has_spell, line 125) to
-- avoid Mage/Paladin blast radius -- resolve_best_rank has other callers this change must not
-- touch. Walks the rank array HIGH -> LOW and returns the first TRAINED id, or nil if none is
-- known yet (graceful 1-70 degradation).
function SpellCatalog:resolve_known_rank(key)
    local spell = self:get(key)
    if not spell then
        return nil
    end
    if spell.id then
        return is_trained(spell.id) and spell.id or nil
    end
    if spell.ranks and #spell.ranks > 0 then
        for i = #spell.ranks, 1, -1 do
            if is_trained(spell.ranks[i]) then
                return spell.ranks[i]
            end
        end
        return nil
    end
    return nil
end

local function get_spell(self, key_or_id)
    if type(key_or_id) == "string" then
        return self:get(key_or_id)
    end
    local key = self:find_key_by_id(key_or_id)
    return key and self:get(key) or nil
end

function SpellCatalog:is_gcd_spell(key_or_id)
    local spell = get_spell(self, key_or_id)
    return spell and spell.gcd == true or false
end

function SpellCatalog:is_ogcd_spell(key_or_id)
    local spell = get_spell(self, key_or_id)
    return spell and spell.ogcd == true or false
end

return SpellCatalog
