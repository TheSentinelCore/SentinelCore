-- SentinelCore/rotations/paladin/RetributionUtility.lua
-- Utility AI action definitions for TBC Retribution Paladin.
-- All actions registered with UtilityEvaluator using response curves.
-- See design doc Section 5.3 for complete specifications.

local RetUtil = {}

-- Rank tables: highest rank first, resolved at registration time.
-- Spell IDs from tbcmangos.spell_template.
local RANKS = {
    SEAL_OF_BLOOD       = { 31892 },                                                     -- R1(64)
    SEAL_OF_COMMAND     = { 27170, 20920, 20919, 20918, 20915, 20375 },                  -- R6(70)..R1(20)
    JUDGEMENT            = { 20271 },                                                     -- level 4
    CRUSADER_STRIKE      = { 35395 },                                                    -- talent (50)
    HAMMER_OF_WRATH      = { 27180, 24239, 24274, 24275 },                               -- R4(68)..R1(44)
    EXORCISM             = { 27138, 10314, 10313, 10312, 5615, 5614, 879 },              -- R7(68)..R1(20)
    CONSECRATION         = { 27173, 20924, 20923, 20922, 20116, 26573 },                 -- R6(70)..R1(20)
    HOLY_WRATH           = { 27139, 10318, 2812 },                                       -- R3(69)..R1(50)
    AVENGING_WRATH       = { 31884 },                                                    -- level 70
    DIVINE_SHIELD        = { 1020, 642 },                                                -- R2(50), R1(34)
    LAY_ON_HANDS         = { 27154, 10310, 2800, 633 },                                  -- R4(69)..R1(10)
    HAMMER_OF_JUSTICE    = { 10308, 5589, 5588, 853 },                                   -- R4(54)..R1(8)
    REPENTANCE           = { 20066 },                                                    -- talent (20)
    FLASH_OF_LIGHT       = { 27137, 19943, 19942, 19941, 19940, 19939, 19750 },          -- R7(66)..R1(20)
    HOLY_LIGHT           = { 27136, 27135, 25292, 10329, 10328, 3472, 1042, 1026, 647, 639, 635 }, -- R11(70)..R1(1)
}
RetUtil.RANKS = RANKS

--- Find the highest learned rank from a list of spell IDs (highest first).
---@param ranks number[]
---@return number|nil
local function best_rank(ranks)
    if not core or not core.spell_book or not core.spell_book.is_spell_learned then
        return ranks[1]
    end
    for i = 1, #ranks do
        if core.spell_book.is_spell_learned(ranks[i]) then
            return ranks[i]
        end
    end
    return nil
end

--- Register an action only if the spell is learned (or has no spell_id).
local function register_if_learned(evaluator, action)
    if action.spell_id then
        evaluator:register(action)
    end
end

function RetUtil.register_actions(evaluator)
    -- Resolve best available rank for each spell
    local S = {}
    for key, ranks in pairs(RANKS) do
        S[key] = best_rank(ranks)
    end

    ----------------------------------------------------------------
    -- Defensives
    ----------------------------------------------------------------

    -- Divine Shield (panic button)
    register_if_learned(evaluator, {
        id = "divine_shield",
        action_type = "cast_spell_self",
        spell_id = S.DIVINE_SHIELD,
        weight = 5.0,
        bucket = 0,
        considerations = {
            { input = "player_health_pct", curve = "step_below", params = { threshold = 0.20 } },
            { input = "player_health_pct", curve = "inverse_linear", params = { min = 0, max = 0.20 } },
            { input = "enemy_count", curve = "linear", params = { min = 0, max = 5 } },
        },
    })

    -- Lay on Hands (absolute last resort)
    register_if_learned(evaluator, {
        id = "lay_on_hands",
        action_type = "cast_spell_self",
        spell_id = S.LAY_ON_HANDS,
        weight = 4.5,
        bucket = 0,
        considerations = {
            { input = "player_health_pct", curve = "step_below", params = { threshold = 0.12 } },
        },
    })

    -- Holy Light (big self-heal — preferred when mana allows, heals more per cast)
    register_if_learned(evaluator, {
        id = "holy_light",
        action_type = "cast_spell_self",
        spell_id = S.HOLY_LIGHT,
        weight = 2.5,
        bucket = 3,
        considerations = {
            { input = "player_health_pct", curve = "inverse_linear", params = { min = 0.15, max = 0.65 } },
            { input = "player_mana_pct", curve = "linear", params = { min = 0.15, max = 0.50 } },
            { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
        },
    })

    -- Flash of Light (quick heal — fallback when mana too low for Holy Light)
    register_if_learned(evaluator, {
        id = "flash_of_light",
        action_type = "cast_spell_self",
        spell_id = S.FLASH_OF_LIGHT,
        weight = 1.8,
        bucket = 3,
        considerations = {
            { input = "player_health_pct", curve = "inverse_linear", params = { min = 0.20, max = 0.65 } },
            { input = "player_mana_pct", curve = "linear", params = { min = 0.05, max = 0.30 } },
            { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
        },
    })

    ----------------------------------------------------------------
    -- Interrupts
    ----------------------------------------------------------------

    -- Hammer of Justice (stun interrupt)
    register_if_learned(evaluator, {
        id = "hammer_of_justice",
        action_type = "cast_spell_target",
        spell_id = S.HAMMER_OF_JUSTICE,
        weight = 3.5,
        bucket = 1,
        intent = "interrupt",
        considerations = {
            { input = "target_is_casting", curve = "step_above", params = { threshold = 0.5 } },
            { input = "target_cast_progress", curve = "linear", params = { min = 0.50, max = 0.85 } },
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 10 } },
        },
    })

    -- Repentance (CC interrupt backup)
    register_if_learned(evaluator, {
        id = "repentance",
        action_type = "cast_spell_target",
        spell_id = S.REPENTANCE,
        weight = 2.5,
        bucket = 1,
        intent = "interrupt",
        considerations = {
            { input = "target_is_casting", curve = "step_above", params = { threshold = 0.5 } },
            { input = "target_cast_progress", curve = "linear", params = { min = 0.55, max = 0.90 } },
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 20 } },
        },
    })

    ----------------------------------------------------------------
    -- Seal Twisting
    ----------------------------------------------------------------

    -- SoC R1 prep (early in swing cycle) — always R1 for cheap mana cost
    if S.SEAL_OF_COMMAND then
        evaluator:register({
            id = "seal_twist_prep",
            action_type = "cast_spell_self",
            spell_id = RANKS.SEAL_OF_COMMAND[#RANKS.SEAL_OF_COMMAND], -- R1 (cheapest)
            weight = 2.5,
            intent = "seal_twist",
            considerations = {
                { input = "swing_in_prep_window", curve = "step_above", params = { threshold = 0.5 } },
                { input = "has_seal_of_command", curve = "step_below", params = { threshold = 0.5 } },
                { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.08 } },
                { input = "seal_twist_enabled", curve = "step_above", params = { threshold = 0.5 } },
            },
        })
    end

    -- SoB twist (last 0.4s before swing) — Horde only
    register_if_learned(evaluator, {
        id = "seal_twist_execute",
        action_type = "cast_spell_self",
        spell_id = S.SEAL_OF_BLOOD,
        weight = 3.0,
        intent = "seal_twist",
        considerations = {
            { input = "swing_in_twist_window", curve = "step_above", params = { threshold = 0.5 } },
            { input = "has_seal_of_command", curve = "step_above", params = { threshold = 0.5 } },
            { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.08 } },
            { input = "seal_twist_enabled", curve = "step_above", params = { threshold = 0.5 } },
        },
    })

    -- Fallback: maintain SoB when not twisting (Horde only)
    register_if_learned(evaluator, {
        id = "seal_of_blood_maintain",
        action_type = "cast_spell_self",
        spell_id = S.SEAL_OF_BLOOD,
        weight = 1.0,
        bucket = 5,
        considerations = {
            { input = "has_seal_of_blood", curve = "step_below", params = { threshold = 0.5 } },
            { input = "seal_twist_enabled", curve = "step_below", params = { threshold = 0.5 } },
        },
    })

    -- Fallback: maintain SoC when SoB unavailable (Alliance) and not twisting
    if not S.SEAL_OF_BLOOD and S.SEAL_OF_COMMAND then
        evaluator:register({
            id = "seal_of_command_maintain",
            action_type = "cast_spell_self",
            spell_id = S.SEAL_OF_COMMAND,
            weight = 1.0,
            bucket = 5,
            considerations = {
                { input = "has_any_seal", curve = "step_below", params = { threshold = 0.5 } },
            },
        })
    end

    ----------------------------------------------------------------
    -- Cooldowns
    ----------------------------------------------------------------

    -- Avenging Wrath (+30% dmg, major cooldown)
    register_if_learned(evaluator, {
        id = "avenging_wrath",
        action_type = "cast_spell_self",
        spell_id = S.AVENGING_WRATH,
        weight = 2.5,
        bucket = 3,
        considerations = {
            { input = "target_health_pct", curve = "linear", params = { min = 0.40, max = 1.0 } },
            { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.30 } },
            { input = "player_health_pct", curve = "step_above", params = { threshold = 0.40 } },
        },
    })

    ----------------------------------------------------------------
    -- Core Rotation
    ----------------------------------------------------------------

    -- Judgement (on GCD, 8s CD with talent, 10yd range, consumes active seal)
    register_if_learned(evaluator, {
        id = "judgement",
        action_type = "cast_spell_target",
        spell_id = S.JUDGEMENT,
        weight = 1.8,
        considerations = {
            { input = "has_any_seal", curve = "step_above", params = { threshold = 0.5 } },
            { input = "target_distance", curve = "step_below", params = { threshold = 10.5 } },
            { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.08 } },
        },
    })

    -- Crusader Strike (6s CD, core rotational ability)
    register_if_learned(evaluator, {
        id = "crusader_strike",
        action_type = "cast_spell_target",
        spell_id = S.CRUSADER_STRIKE,
        weight = 2.0,
        considerations = {
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 5.5 } },
            { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.10 } },
            { input = "target_health_pct", curve = "inverse_linear", params = { min = 0, max = 1.0 } },
        },
    })

    -- Hammer of Wrath (execute <20% HP)
    register_if_learned(evaluator, {
        id = "hammer_of_wrath",
        action_type = "cast_spell_target",
        spell_id = S.HAMMER_OF_WRATH,
        weight = 2.2,
        bucket = 3,
        considerations = {
            { input = "target_health_pct", curve = "step_below", params = { threshold = 0.20 } },
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 30 } },
            { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.06 } },
        },
    })

    -- Exorcism (undead/demon, 15s CD)
    register_if_learned(evaluator, {
        id = "exorcism",
        action_type = "cast_spell_target",
        spell_id = S.EXORCISM,
        weight = 1.3,
        bucket = 4,
        considerations = {
            { input = "target_is_undead_demon", curve = "step_above", params = { threshold = 0.5 } },
            { input = "player_mana_pct", curve = "linear", params = { min = 0.15, max = 0.55 } },
            { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 30 } },
        },
    })

    -- Consecration (AoE, expensive)
    register_if_learned(evaluator, {
        id = "consecration",
        action_type = "cast_spell_self",
        spell_id = S.CONSECRATION,
        weight = 1.1,
        bucket = 4,
        considerations = {
            { input = "enemy_count", curve = "linear", params = { min = 2, max = 5 } },
            { input = "player_mana_pct", curve = "linear", params = { min = 0.25, max = 0.70 } },
            { input = "nearest_enemy_distance", curve = "inverse_linear", params = { min = 0, max = 8 } },
        },
    })

    -- Holy Wrath (AoE, undead/demon, 60s CD)
    register_if_learned(evaluator, {
        id = "holy_wrath",
        action_type = "cast_spell_self",
        spell_id = S.HOLY_WRATH,
        weight = 1.0,
        bucket = 4,
        considerations = {
            { input = "target_is_undead_demon", curve = "step_above", params = { threshold = 0.5 } },
            { input = "enemy_count", curve = "linear", params = { min = 2, max = 6 } },
            { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.35 } },
            { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
        },
    })

    -- Auto-attack (always available filler)
    evaluator:register({
        id = "auto_attack",
        action_type = "auto_attack",
        weight = 0.5,
        bucket = 5,
        considerations = {
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 5.5 } },
        },
    })

    ----------------------------------------------------------------
    -- Racial Abilities (gated by is_spell_learned at cooldown check)
    ----------------------------------------------------------------

    -- Blood Fury (Orc, +AP for 15s) — only when Avenging Wrath active (stack CDs)
    evaluator:register({
        id = "blood_fury",
        action_type = "cast_spell_self",
        spell_id = 33697,
        weight = 1.5,
        bucket = 3,
        considerations = {
            { input = "in_combat", curve = "step_above", params = { threshold = 0.5 } },
            { input = "has_avenging_wrath", curve = "step_above", params = { threshold = 0.5 } },
            { input = "player_health_pct", curve = "step_above", params = { threshold = 0.40 } },
        },
    })

    -- Stoneform (Dwarf, removes bleeds/poisons + armor)
    evaluator:register({
        id = "stoneform",
        action_type = "cast_spell_self",
        spell_id = 20594,
        weight = 3.0,
        bucket = 0,
        considerations = {
            { input = "player_health_pct", curve = "step_below", params = { threshold = 0.30 } },
        },
    })

    -- Arcane Torrent (Blood Elf, AoE silence + mana restore)
    evaluator:register({
        id = "arcane_torrent",
        action_type = "cast_spell_self",
        spell_id = 28730,
        weight = 2.0,
        bucket = 1,
        considerations = {
            { input = "target_is_casting", curve = "step_above", params = { threshold = 0.5 } },
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 8 } },
        },
    })
end

-- Expose resolved SPELLS for backward compatibility (tests reference RetUtil.SPELLS)
RetUtil.SPELLS = {
    SEAL_OF_BLOOD = RANKS.SEAL_OF_BLOOD[1],
    SEAL_OF_COMMAND_R1 = RANKS.SEAL_OF_COMMAND[#RANKS.SEAL_OF_COMMAND],
    JUDGEMENT = RANKS.JUDGEMENT[1],
    CRUSADER_STRIKE = RANKS.CRUSADER_STRIKE[1],
    HAMMER_OF_WRATH = RANKS.HAMMER_OF_WRATH[1],
    EXORCISM = RANKS.EXORCISM[1],
    CONSECRATION = RANKS.CONSECRATION[1],
    HOLY_WRATH = RANKS.HOLY_WRATH[1],
    AVENGING_WRATH = RANKS.AVENGING_WRATH[1],
    DIVINE_SHIELD = RANKS.DIVINE_SHIELD[1],
    LAY_ON_HANDS = RANKS.LAY_ON_HANDS[1],
    HAMMER_OF_JUSTICE = RANKS.HAMMER_OF_JUSTICE[1],
    REPENTANCE = RANKS.REPENTANCE[1],
    FLASH_OF_LIGHT = RANKS.FLASH_OF_LIGHT[1],
    HOLY_LIGHT = RANKS.HOLY_LIGHT[1],
}

return RetUtil
