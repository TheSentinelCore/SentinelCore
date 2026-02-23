-- SentinelCore/rotations/paladin/RetributionUtility.lua
-- Utility AI action definitions for TBC Retribution Paladin.
-- All actions registered with UtilityEvaluator using response curves.
-- See design doc Section 5.3 for complete specifications.

local RetUtil = {}

-- Spell IDs (from mangos DB)
local SPELLS = {
    SEAL_OF_BLOOD = 31892,
    SEAL_OF_COMMAND_R1 = 20375,
    JUDGEMENT = 20271,
    CRUSADER_STRIKE = 35395,
    HAMMER_OF_WRATH_R4 = 27180,
    EXORCISM_R7 = 27138,
    CONSECRATION_R6 = 27173,
    HOLY_WRATH_R3 = 27139,
    AVENGING_WRATH = 31884,
    DIVINE_SHIELD_R2 = 1020,
    LAY_ON_HANDS_R4 = 27154,
    HAMMER_OF_JUSTICE_R4 = 10308,
    REPENTANCE = 20066,
    FLASH_OF_LIGHT_R7 = 27137,
    HOLY_LIGHT_R11 = 27136,
    BLESSING_OF_MIGHT_R8 = 27140,
    SANCTITY_AURA = 20218,
    BLESSING_OF_FREEDOM = 1044,
}
RetUtil.SPELLS = SPELLS

function RetUtil.register_actions(evaluator)
    ----------------------------------------------------------------
    -- Defensives
    ----------------------------------------------------------------

    -- Divine Shield (panic button)
    evaluator:register({
        id = "divine_shield",
        action_type = "cast_spell_self",
        spell_id = SPELLS.DIVINE_SHIELD_R2,
        weight = 5.0,
        considerations = {
            { input = "player_health_pct", curve = "step_below", params = { threshold = 0.20 } },
            { input = "player_health_pct", curve = "inverse_linear", params = { min = 0, max = 0.20 } },
            { input = "enemy_count", curve = "linear", params = { min = 0, max = 5 } },
        },
    })

    -- Lay on Hands (absolute last resort)
    evaluator:register({
        id = "lay_on_hands",
        action_type = "cast_spell_self",
        spell_id = SPELLS.LAY_ON_HANDS_R4,
        weight = 4.0,
        considerations = {
            { input = "player_health_pct", curve = "step_below", params = { threshold = 0.12 } },
        },
    })

    -- Holy Light (big self-heal)
    evaluator:register({
        id = "holy_light",
        action_type = "cast_spell_self",
        spell_id = SPELLS.HOLY_LIGHT_R11,
        weight = 1.8,
        considerations = {
            { input = "player_health_pct", curve = "inverse_linear", params = { min = 0.30, max = 0.65 } },
            { input = "player_mana_pct", curve = "linear", params = { min = 0.22, max = 0.60 } },
            { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
        },
    })

    -- Flash of Light (quick heal)
    evaluator:register({
        id = "flash_of_light",
        action_type = "cast_spell_self",
        spell_id = SPELLS.FLASH_OF_LIGHT_R7,
        weight = 2.0,
        considerations = {
            { input = "player_health_pct", curve = "inverse_linear", params = { min = 0.25, max = 0.55 } },
            { input = "player_mana_pct", curve = "linear", params = { min = 0.10, max = 0.40 } },
            { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
        },
    })

    ----------------------------------------------------------------
    -- Interrupts
    ----------------------------------------------------------------

    -- Hammer of Justice (stun interrupt)
    evaluator:register({
        id = "hammer_of_justice",
        action_type = "cast_spell_target",
        spell_id = SPELLS.HAMMER_OF_JUSTICE_R4,
        weight = 3.5,
        intent = "interrupt",
        considerations = {
            { input = "target_is_casting", curve = "step_above", params = { threshold = 0.5 } },
            { input = "target_cast_progress", curve = "linear", params = { min = 0.50, max = 0.85 } },
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 10 } },
        },
    })

    -- Repentance (CC interrupt backup)
    evaluator:register({
        id = "repentance",
        action_type = "cast_spell_target",
        spell_id = SPELLS.REPENTANCE,
        weight = 2.5,
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

    -- SoC R1 prep (early in swing cycle)
    evaluator:register({
        id = "seal_twist_prep",
        action_type = "cast_spell_self",
        spell_id = SPELLS.SEAL_OF_COMMAND_R1,
        weight = 2.5,
        intent = "seal_twist",
        considerations = {
            { input = "swing_in_prep_window", curve = "step_above", params = { threshold = 0.5 } },
            { input = "has_seal_of_command", curve = "step_below", params = { threshold = 0.5 } },
            { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.08 } },
            { input = "seal_twist_enabled", curve = "step_above", params = { threshold = 0.5 } },
        },
    })

    -- SoB twist (last 0.4s before swing)
    evaluator:register({
        id = "seal_twist_execute",
        action_type = "cast_spell_self",
        spell_id = SPELLS.SEAL_OF_BLOOD,
        weight = 3.0,
        intent = "seal_twist",
        considerations = {
            { input = "swing_in_twist_window", curve = "step_above", params = { threshold = 0.5 } },
            { input = "has_seal_of_command", curve = "step_above", params = { threshold = 0.5 } },
            { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.08 } },
            { input = "seal_twist_enabled", curve = "step_above", params = { threshold = 0.5 } },
        },
    })

    -- Fallback: maintain SoB when not twisting
    evaluator:register({
        id = "seal_of_blood_maintain",
        action_type = "cast_spell_self",
        spell_id = SPELLS.SEAL_OF_BLOOD,
        weight = 1.0,
        considerations = {
            { input = "has_seal_of_blood", curve = "step_below", params = { threshold = 0.5 } },
            { input = "seal_twist_enabled", curve = "step_below", params = { threshold = 0.5 } },
        },
    })

    ----------------------------------------------------------------
    -- Cooldowns
    ----------------------------------------------------------------

    -- Avenging Wrath (+30% dmg)
    evaluator:register({
        id = "avenging_wrath",
        action_type = "cast_spell_self",
        spell_id = SPELLS.AVENGING_WRATH,
        weight = 1.5,
        considerations = {
            { input = "target_health_pct", curve = "linear", params = { min = 0.40, max = 1.0 } },
            { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.30 } },
            { input = "enemy_count", curve = "linear", params = { min = 1, max = 4 } },
        },
    })

    ----------------------------------------------------------------
    -- Core Rotation
    ----------------------------------------------------------------

    -- Judgement (off-GCD, 8s CD with talent)
    evaluator:register({
        id = "judgement",
        action_type = "cast_spell_target",
        spell_id = SPELLS.JUDGEMENT,
        weight = 1.8,
        bypasses_gcd = true,
        considerations = {
            { input = "has_seal_of_blood", curve = "step_above", params = { threshold = 0.5 } },
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 10 } },
            { input = "player_mana_pct", curve = "linear", params = { min = 0.05, max = 0.25 } },
        },
    })

    -- Crusader Strike (6s CD, core filler)
    evaluator:register({
        id = "crusader_strike",
        action_type = "cast_spell_target",
        spell_id = SPELLS.CRUSADER_STRIKE,
        weight = 1.5,
        considerations = {
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 5.5 } },
            { input = "player_mana_pct", curve = "linear", params = { min = 0.08, max = 0.35 } },
        },
    })

    -- Hammer of Wrath (execute <20% HP)
    evaluator:register({
        id = "hammer_of_wrath",
        action_type = "cast_spell_target",
        spell_id = SPELLS.HAMMER_OF_WRATH_R4,
        weight = 2.2,
        considerations = {
            { input = "target_health_pct", curve = "step_below", params = { threshold = 0.20 } },
            { input = "target_health_pct", curve = "inverse_linear", params = { min = 0, max = 0.20 } },
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 30 } },
            { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.06 } },
        },
    })

    -- Exorcism (undead/demon, 15s CD)
    evaluator:register({
        id = "exorcism",
        action_type = "cast_spell_target",
        spell_id = SPELLS.EXORCISM_R7,
        weight = 1.3,
        considerations = {
            { input = "target_is_undead_demon", curve = "step_above", params = { threshold = 0.5 } },
            { input = "player_mana_pct", curve = "linear", params = { min = 0.15, max = 0.55 } },
            { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 30 } },
        },
    })

    -- Consecration (AoE, expensive)
    evaluator:register({
        id = "consecration",
        action_type = "cast_spell_self",
        spell_id = SPELLS.CONSECRATION_R6,
        weight = 1.1,
        considerations = {
            { input = "enemy_count", curve = "linear", params = { min = 2, max = 5 } },
            { input = "player_mana_pct", curve = "linear", params = { min = 0.25, max = 0.70 } },
            { input = "nearest_enemy_distance", curve = "inverse_linear", params = { min = 0, max = 8 } },
        },
    })

    -- Holy Wrath (AoE, undead/demon, 60s CD)
    evaluator:register({
        id = "holy_wrath",
        action_type = "cast_spell_self",
        spell_id = SPELLS.HOLY_WRATH_R3,
        weight = 1.0,
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
        weight = 0.3,
        considerations = {
            { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 5.5 } },
        },
    })
end

return RetUtil
