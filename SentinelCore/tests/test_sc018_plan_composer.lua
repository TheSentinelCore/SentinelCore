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

    local maintenance_ctx_edge = {
        player_health_pct = 0.78,
        player_mana_pct = 0.42,
    }
    local maintenance_plan_edge = PlanComposer.compose_maintenance(provider, maintenance_ctx_edge)
    T.assert_true(type(maintenance_plan_edge[1]) == "table" and maintenance_plan_edge[1].item_kind == "water",
        "maintenance scheduler should use deficit weighting so small mana deficits can outrank base-priority food")

    -- EDF-like scheduling: ready actions with earlier deadlines should outrank
    -- higher base-priority actions that are still on cooldown.
    local deadline_provider = {
        defensive = function() return {} end,
        interrupt = function() return {} end,
        utility = function() return {} end,
        combat = function()
            return {
                {
                    action_type = "cast_spell_target",
                    priority = 300,
                    intent = "burst",
                    spell_id = 1001,
                    max_target_distance = 30.0,
                },
                {
                    action_type = "cast_spell_target",
                    priority = 220,
                    intent = "sustain",
                    spell_id = 1002,
                    max_target_distance = 5.5,
                },
            }
        end,
        aoe = function() return {} end,
    }

    local deadline_ctx = {
        enemy_count = 1,
        now = 50.0,
        global_cooldown_remaining = 0.0,
        player_move_speed = 7.0,
        target_distance = 4.0,
        spell_cooldown_remaining = function(spell_id)
            if tonumber(spell_id) == 1001 then
                return 3.0
            end
            return 0.0
        end,
    }
    local deadline_plan = PlanComposer.compose_combat(deadline_provider, deadline_ctx, 3)
    T.assert_true(type(deadline_plan[1]) == "table" and tonumber(deadline_plan[1].spell_id) == 1002,
        "combat scheduler should prioritize earliest-deadline ready actions over higher-priority cooldown-locked actions")
    T.assert_true((tonumber(deadline_plan[1]._scheduler_deadline) or math.huge) <
        (tonumber(deadline_plan[2]._scheduler_deadline) or -math.huge),
        "combat scheduler should sort by earliest absolute deadline (EDF-like)")

    return {
        sc018_plan_composer_scheduler = true,
    }
end

return { run = run }
