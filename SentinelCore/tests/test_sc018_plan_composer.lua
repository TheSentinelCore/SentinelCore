local T = require("tests/TestUtil")

local function run()
    local PlanComposer = require("rotations/framework/PlanComposer")

    local provider = {
        resolve_combat_state = function(_, ctx)
            return {
                combat_mode = "recovery",
                planner_intents = {
                    recover = 1.0,
                    burst = -1.0,
                },
            }
        end,
        defensive = function()
            return {
                { action_type = "cast_spell_self", priority = 100, intent = "defensive", spell_id = 10 },
            }
        end,
        interrupt = function()
            return {}
        end,
        utility = function()
            return {
                { action_type = "cast_spell_self", priority = 90, intent = "burst", combat_modes = { "burst" }, spell_id = 11 },
                { action_type = "cast_spell_self", priority = 80, intent = "recover", combat_modes = { "recovery" }, spell_id = 12 },
            }
        end,
        combat = function()
            return {
                { action_type = "cast_spell_target", priority = 200, intent = "burst", combat_modes = { "burst" }, spell_id = 1 },
                { action_type = "cast_spell_target", priority = 190, intent = "sustain", combat_modes = { "burst", "sustain", "recovery" }, spell_id = 2 },
                { action_type = "cast_spell_target", priority = 180, intent = "execute", combat_modes = { "burst", "sustain", "recovery" }, spell_id = 3 },
            }
        end,
        aoe = function()
            return {}
        end,
        maintenance = function()
            return {
                {
                    action_type = "use_item_self",
                    priority = 985,
                    item_kind = "food",
                    max_player_health_pct = 0.80,
                },
                {
                    action_type = "use_item_self",
                    priority = 980,
                    item_kind = "water",
                    max_player_mana_pct = 0.45,
                },
            }
        end,
    }

    local combat_ctx = {
        enemy_count = 1,
        player_mana_pct = 0.15,
        player_health_pct = 0.95,
        target_health_pct = 0.20,
    }

    local combat_plan = PlanComposer.compose_combat(provider, combat_ctx, 3)
    local has_burst_only = false
    local execute_index = 0
    local sustain_index = 0
    for i = 1, #combat_plan do
        local action = combat_plan[i]
        if tonumber(action.spell_id) == 1 or tonumber(action.spell_id) == 11 then
            has_burst_only = true
        elseif tonumber(action.spell_id) == 3 then
            execute_index = i
        elseif tonumber(action.spell_id) == 2 then
            sustain_index = i
        end
    end
    T.assert_true(has_burst_only == false, "combat scheduler should filter actions outside active combat mode")
    T.assert_true(execute_index > 0 and sustain_index > 0 and execute_index < sustain_index,
        "combat scheduler should promote execute intent actions in execute phase")

    local maintenance_ctx = {
        player_health_pct = 0.95,
        player_mana_pct = 0.15,
    }
    local maintenance_plan = PlanComposer.compose_maintenance(provider, maintenance_ctx)
    T.assert_true(type(maintenance_plan[1]) == "table" and maintenance_plan[1].item_kind == "water",
        "maintenance scheduler should prioritize water when mana deficit dominates")

    local maintenance_ctx_food = {
        player_health_pct = 0.40,
        player_mana_pct = 0.90,
    }
    local maintenance_plan_food = PlanComposer.compose_maintenance(provider, maintenance_ctx_food)
    T.assert_true(type(maintenance_plan_food[1]) == "table" and maintenance_plan_food[1].item_kind == "food",
        "maintenance scheduler should prioritize food when health deficit dominates")

    return {
        sc018_plan_composer_scheduler = true,
    }
end

return { run = run }
