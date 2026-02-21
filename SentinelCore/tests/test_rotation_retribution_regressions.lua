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
    for i = 1, #combat do
        local action = combat[i]
        if action.action_type == "cast_spell_target" and tonumber(action.spell_id) == 20271 then
            has_judgement = true
        end
        if action.action_type == "cast_spell_self" and tonumber(action.priority) == 545 then
            has_reseal = true
        end
    end
    T.assert_true(has_judgement, "combat plan should include Judgement")
    T.assert_true(has_reseal, "combat plan should include post-judgement reseal")

    local defensive = provider:defensive(base_ctx)
    local has_health_potion = false
    local has_mana_potion = false
    local flash_action = nil
    for i = 1, #defensive do
        local action = defensive[i]
        if action.action_type == "use_best_health_potion" then
            has_health_potion = true
        elseif action.action_type == "use_best_mana_potion" then
            has_mana_potion = true
        elseif action.action_type == "cast_spell_self" and tonumber(action.priority) == 935 then
            flash_action = action
        end
    end
    T.assert_true(has_health_potion, "defensive plan should include health potion action")
    T.assert_true(has_mana_potion, "defensive plan should include mana potion action")
    T.assert_true(type(flash_action) == "table", "defensive plan should include Flash of Light action")

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
    T.assert_eq(low_mana_spell, 19750, "low mana Flash of Light should use configured downrank")

    local maintenance = provider:maintenance(base_ctx)
    local has_food = false
    local has_water = false
    for i = 1, #maintenance do
        local action = maintenance[i]
        if action.action_type == "use_item_self" and type(action.item_id) == "table" then
            local first = tonumber(action.item_id[1]) or 0
            if first == 34062 then
                if tonumber(action.priority) == 980 then
                    has_water = true
                elseif tonumber(action.priority) == 970 then
                    has_food = true
                end
            end
        end
    end
    T.assert_true(has_water, "maintenance plan should include water action")
    T.assert_true(has_food, "maintenance plan should include food action")

    return {
        retribution_regressions = true,
    }
end

return { run = run }
