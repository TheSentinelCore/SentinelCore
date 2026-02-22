local T = require("tests/TestUtil")

local function run()
    local learned = {
        [27137] = true,
        [19750] = true,
        [27136] = true,
        [27174] = true,
        [20218] = true,
    }

    T.install_core_stub({
        spell_book = {
            is_spell_learned = function(id)
                return learned[tonumber(id) or -1] == true
            end,
            has_spell = function(id)
                return learned[tonumber(id) or -1] == true
            end,
            is_usable_spell = function() return true end,
        },
    })

    local provider = require("rotations/paladin/Retribution")

    local function resolve_from_fallback(name, fallback_ids)
        if type(fallback_ids) == "table" and #fallback_ids > 0 then
            return fallback_ids[1]
        end
        return nil
    end

    local base_ctx = {
        class_id = 2,
        in_combat = true,
        enemy_count = 1,
        player_mana_pct = 0.55,
        player_has_aura = function(spec) return false end,
        resolve_spell_id = resolve_from_fallback,
    }

    T.assert_true(provider:can_run(base_ctx) == true, "retribution provider should run for paladin class")

    local combat = provider:combat(base_ctx)
    local has_judgement = false
    local has_reseal = false
    local judgement_priority = 0
    local crusader_priority = 0
    local exorcism_action = nil
    for i = 1, #combat do
        local action = combat[i]
        if action.action_type == "cast_spell_target" and tonumber(action.spell_id) == 20271 then
            has_judgement = true
            judgement_priority = tonumber(action.priority) or 0
            T.assert_true(action.allow_movement == true,
                "judgement should be castable while moving during approach")
            T.assert_eq(tonumber(action.max_target_distance), 9.0,
                "judgement combat range should use 9-yard reliability window")
        end
        if action.action_type == "cast_spell_target" and tonumber(action.spell_id) == 35395 then
            crusader_priority = tonumber(action.priority) or 0
        end
        if action.action_type == "cast_spell_target" and tonumber(action.priority) == 500 then
            exorcism_action = action
        end
        if action.action_type == "cast_spell_self" and tonumber(action.priority) == 545 then
            has_reseal = true
        end
    end
    T.assert_true(has_judgement, "combat plan should include Judgement")
    T.assert_true(has_reseal, "combat plan should include post-judgement reseal")
    T.assert_true(crusader_priority > judgement_priority,
        "combat plan should prioritize Crusader Strike before Judgement when both are available")
    T.assert_true(type(exorcism_action) == "table", "combat plan should include Exorcism action for valid targets")

    local exorcism_invalid = exorcism_action.condition({
        player_mana_pct = 0.80,
        target_is_undead_or_demon = false,
    }, exorcism_action)
    T.assert_true(exorcism_invalid == false, "exorcism should be blocked on non-undead/non-demon targets")

    local exorcism_valid = exorcism_action.condition({
        player_mana_pct = 0.80,
        target_is_undead_or_demon = true,
    }, exorcism_action)
    T.assert_true(exorcism_valid == true, "exorcism should be allowed on undead/demon targets")

    local defensive = provider:defensive(base_ctx)
    local has_health_potion = false
    local has_mana_potion = false
    local flash_action = nil
    local holy_action = nil
    for i = 1, #defensive do
        local action = defensive[i]
        if action.action_type == "use_best_health_potion" then
            has_health_potion = true
        elseif action.action_type == "use_best_mana_potion" then
            has_mana_potion = true
        elseif action.action_type == "cast_spell_self" and tonumber(action.priority) == 945 then
            holy_action = action
        elseif action.action_type == "cast_spell_self" and tonumber(action.priority) == 935 then
            flash_action = action
        end
    end
    T.assert_true(has_health_potion, "defensive plan should include health potion action")
    T.assert_true(has_mana_potion, "defensive plan should include mana potion action")
    T.assert_true(type(holy_action) == "table", "defensive plan should include Holy Light action")
    T.assert_true(type(flash_action) == "table", "defensive plan should include Flash of Light action")
    T.assert_true(flash_action.allow_movement == false, "flash of light should require standing still")
    T.assert_true((tonumber(flash_action.max_player_mana_pct) or -1) >= 0 and
        (tonumber(flash_action.max_player_mana_pct) or -1) <= 0.15,
        "flash of light should only be available in a very-low-mana band")
    T.assert_true((tonumber(holy_action.max_player_health_pct) or 0) >= (tonumber(flash_action.max_player_health_pct) or 1),
        "holy light should be the main heal window, with flash reserved for narrower fallback health bands")

    local flash_execute_hold = flash_action.condition({
        in_combat = true,
        player_health_pct = 0.70,
        target_health_pct = 0.20,
    }, flash_action)
    T.assert_true(flash_execute_hold == false,
        "flash of light should be held in execute range when player health is not in the critical band")

    local flash_execute_critical = flash_action.condition({
        in_combat = true,
        player_health_pct = 0.30,
        target_health_pct = 0.20,
    }, flash_action)
    T.assert_true(flash_execute_critical == true,
        "flash of light should still be allowed in execute range at critical player health")

    local high_mana_spell = flash_action.spell_id(base_ctx, flash_action)
    T.assert_eq(high_mana_spell, 27137, "high mana Flash of Light should use max rank")

    local low_ctx = {
        class_id = 2,
        in_combat = true,
        enemy_count = 1,
        player_mana_pct = 0.15,
        player_has_aura = function(spec) return false end,
        resolve_spell_id = resolve_from_fallback,
    }
    local low_mana_spell = flash_action.spell_id(low_ctx, flash_action)
    T.assert_eq(low_mana_spell, 27137, "Flash of Light should always resolve to max learned rank")

    local maintenance = provider:maintenance(base_ctx)
    local has_food = false
    local has_water = false
    for i = 1, #maintenance do
        local action = maintenance[i]
        if action.action_type == "use_item_self" and type(action.item_kind) == "string" then
            if action.item_kind == "food" and tonumber(action.priority) == 985 then
                has_food = true
            elseif action.item_kind == "water" and tonumber(action.priority) == 980 then
                has_water = true
            end
        end
    end
    T.assert_true(has_water, "maintenance plan should include water action")
    T.assert_true(has_food, "maintenance plan should include food action")

    local aoe = provider:aoe(base_ctx)
    local holy_wrath_action = nil
    for i = 1, #aoe do
        local action = aoe[i]
        if action.action_type == "cast_spell_self" and tonumber(action.priority) == 560 then
            holy_wrath_action = action
            break
        end
    end
    T.assert_true(type(holy_wrath_action) == "table", "aoe plan should include Holy Wrath action")
    local holy_wrath_invalid = holy_wrath_action.condition({
        target_is_undead_or_demon = false,
    }, holy_wrath_action)
    T.assert_true(holy_wrath_invalid == false, "holy wrath should be blocked on non-undead/non-demon targets")
    local holy_wrath_valid = holy_wrath_action.condition({
        target_is_undead_or_demon = true,
    }, holy_wrath_action)
    T.assert_true(holy_wrath_valid == true, "holy wrath should be allowed on undead/demon targets")

    local pull_no_seal = provider:get_pull_profile(base_ctx)
    T.assert_true(type(pull_no_seal) == "table", "pull profile should be a table")
    T.assert_eq(tonumber(pull_no_seal.pull_spell_id) or 0, 0, "pull profile should not require ranged pull without active seal")
    T.assert_eq(tonumber(pull_no_seal.max_pull_range), 5.5,
        "pull profile should close into melee range when no active seal is present")

    local seal_ctx = {
        class_id = 2,
        in_combat = true,
        enemy_count = 1,
        player_mana_pct = 0.55,
        player_has_aura = function() return true end,
        resolve_spell_id = resolve_from_fallback,
    }
    local pull_with_seal = provider:get_pull_profile(seal_ctx)
    T.assert_eq(tonumber(pull_with_seal.pull_spell_id), 20271,
        "pull profile should use Judgement when a seal is active")
    T.assert_eq(tonumber(pull_with_seal.max_pull_range), 9.0,
        "pull profile should close into 9-yard Judgement cast buffer when a seal is active")

    return {
        retribution_regressions = true,
    }
end

return { run = run }
