-- SentinelCore/tests/test_ai007_retribution_utility.lua
local TU = require("tests/TestUtil")
local UE = require("ai/UtilityEvaluator")

local M = {}

function M.run()
    local env = TU.install_core_stub()

    -- Stub spell book: all spells are "learned"
    env.core.spell_book.has_spell = function() return true end
    env.core.spell_book.is_spell_learned = function() return true end
    env.core.spell_book.get_spell_cooldown = function() return 0 end
    env.core.spell_book.get_global_cooldown = function() return 0 end

    local RetUtil = require("rotations/paladin/RetributionUtility")

    -- Test 1: Register actions and evaluate in normal combat
    local eval = UE:new()
    RetUtil.register_actions(eval)

    local ctx = {
        player_health_pct = 0.80,
        player_mana_pct = 0.60,
        player_is_moving = 0,
        player_is_casting = 0,
        player_is_cc = 0,
        in_combat = 1,
        target_health_pct = 0.70,
        target_distance = 4.0,
        target_is_casting = 0,
        target_cast_progress = 0,
        target_time_to_die = 20,
        target_is_fleeing = 0,
        target_is_undead_demon = 0,
        enemy_count = 1,
        time_in_combat = 5,
        nearest_enemy_distance = 4.0,
        spell_cooldown_remaining = 0,
        gcd_remaining = 0,
        swing_time_remaining = 2.0,
        swing_in_prep_window = 1,
        swing_in_twist_window = 0,
        has_seal_of_blood = 1,
        has_seal_of_command = 0,
        has_avenging_wrath = 0,
        has_blessing_of_might = 1,
        vengeance_stacks = 0,
        seal_twist_enabled = 0,
        aoe_threshold = 3,
    }

    local result = eval:evaluate(ctx)
    assert(result ~= nil, "should find an action")
    -- In normal combat, some action should be selected
    assert(result.action.id ~= nil, "action should have an id")

    -- Test 2: Execute phase - Hammer of Wrath should score high
    ctx.target_health_pct = 0.10
    result = eval:evaluate(ctx)
    assert(result ~= nil, "should find execute action")
    assert(result.action.id == "hammer_of_wrath", "HoW should win in execute: " .. tostring(result.action.id))

    -- Test 3: Emergency - Divine Shield at very low health
    ctx.player_health_pct = 0.08
    ctx.target_health_pct = 0.50
    local top = eval:get_top_k(ctx, 3)
    local found_ds = false
    for _, entry in ipairs(top) do
        if entry.action.id == "divine_shield" then found_ds = true end
    end
    assert(found_ds, "Divine Shield should be in top 3 at 8% HP")

    -- Test 4: Seal twist - SoC R1 in prep window
    ctx.player_health_pct = 0.80
    ctx.seal_twist_enabled = 1
    ctx.swing_in_prep_window = 1
    ctx.swing_in_twist_window = 0
    ctx.has_seal_of_command = 0
    ctx.has_seal_of_blood = 1
    ctx.player_mana_pct = 0.50
    result = eval:evaluate(ctx)
    assert(result ~= nil, "should find twist prep action")
    assert(result.action.id == "seal_twist_prep", "SoC R1 prep should win: " .. tostring(result.action.id))

    -- Test 5: Seal twist - SoB in twist window
    ctx.swing_in_prep_window = 0
    ctx.swing_in_twist_window = 1
    ctx.has_seal_of_command = 1
    ctx.has_seal_of_blood = 0
    result = eval:evaluate(ctx)
    assert(result ~= nil, "should find twist action")
    assert(result.action.id == "seal_twist_execute", "SoB twist should win: " .. tostring(result.action.id))

    -- Test 6: Interrupt - HoJ when target casting
    ctx.swing_in_twist_window = 0
    ctx.swing_in_prep_window = 0
    ctx.seal_twist_enabled = 0
    ctx.has_seal_of_blood = 1
    ctx.has_seal_of_command = 0
    ctx.target_is_casting = 1
    ctx.target_cast_progress = 0.70
    ctx.target_distance = 5.0
    ctx.player_health_pct = 0.80
    result = eval:evaluate(ctx)
    assert(result ~= nil, "should find interrupt")
    assert(result.action.id == "hammer_of_justice", "HoJ should win on casting target: " .. tostring(result.action.id))

    env.restore()
    return true
end

return M
