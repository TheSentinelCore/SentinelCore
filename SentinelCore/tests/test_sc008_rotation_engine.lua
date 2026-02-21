local T = require("tests/TestUtil")
local ErrorCodes = require("events/ErrorCodes")

local function run()
    local player = T.mock_object({ class_id = 2, spec_id = 0, health = 60, max_health = 100, mana = 30, max_mana = 100 })
    local target = T.mock_object({ name = "Enemy" })
    local food_item = T.mock_object({ item_id = 4540 })

    T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return { target } end,
        },
        inventory = {
            get_items_in_bag = function(bag_id)
                if bag_id == 0 then
                    return {
                        { item = food_item, slot_id = 24 },
                    }
                end
                return {}
            end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local RotationEngine = require("services/RotationEngine")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.object", player)
    bb:set("combat.target", target)
    bb:set("player.class_id", 2)
    bb:set("player.spec_id", 0)
    bb:set("combat.enemy_count", 4)
    bb:set("player.in_combat", false)

    local rotation = RotationEngine:new(bus, bb, { aoe_enemy_threshold = 3 })
    local plan, err = rotation:generate_plan()
    T.assert_true(type(plan) == "table" and #plan > 0, "rotation plan should exist")
    local has_divine_storm = false
    local has_crusader_strike = false
    local has_judgement = false
    local has_health_potion_action = false
    local has_mana_potion_action = false
    for i = 1, #plan do
        local spell_id = tonumber(plan[i].spell_id) or 0
        local action_type = tostring(plan[i].action_type or "")
        if spell_id == 53385 then
            has_divine_storm = true
        elseif spell_id == 35395 then
            has_crusader_strike = true
        elseif spell_id == 20271 then
            has_judgement = true
        end
        if action_type == "use_best_health_potion" then
            has_health_potion_action = true
        elseif action_type == "use_best_mana_potion" then
            has_mana_potion_action = true
        end
    end
    T.assert_true(has_divine_storm == false, "TBC retribution plan must not include Divine Storm")
    T.assert_true(has_crusader_strike == true, "retribution plan missing Crusader Strike")
    T.assert_true(has_judgement == true, "retribution plan missing Judgement")
    T.assert_true(has_health_potion_action == true, "retribution plan missing health potion action")
    T.assert_true(has_mana_potion_action == true, "retribution plan missing mana potion action")

    local maintenance_plan, maintenance_err = rotation:generate_maintenance_plan()
    T.assert_true(type(maintenance_plan) == "table", "maintenance plan should be a table")
    local has_maintenance_consume = false
    for i = 1, #maintenance_plan do
        if maintenance_plan[i].action_type == "use_item_self" then
            has_maintenance_consume = true
            break
        end
    end
    T.assert_true(has_maintenance_consume == true, "maintenance plan should include eat/drink consumable actions")

    local maintenance_tick_ok, maintenance_tick_err = rotation:tick_maintenance_once()
    T.assert_true(maintenance_tick_ok == true, "maintenance tick should execute consumable action when rest is needed")

    T.assert_true(rotation:should_hold_maintenance() == true, "rotation should hold pulls while rest thresholds are unmet")
    player._health = 100
    player._mana = 100
    T.assert_true(rotation:should_hold_maintenance() == false, "rotation hold should clear after resources recover")

    bb:set("player.class_id", 1)
    local unsupported_plan, unsupported_err = rotation:generate_plan()
    T.assert_true(unsupported_plan == nil, "unsupported class should not resolve a combat plan")
    T.assert_eq(unsupported_err, ErrorCodes.ROTATION_UNAVAILABLE, "unsupported class should return rotation unavailable")
    T.assert_true(rotation:should_hold_maintenance() == false, "unsupported class should not inherit paladin rest thresholds")

    bb:set("player.class_id", 2)
    local restored_plan, restored_err = rotation:generate_plan()
    T.assert_true(type(restored_plan) == "table" and #restored_plan > 0, "paladin plan should recover after class switch")

    local executed, exec_err = rotation:tick_once()
    T.assert_true(executed == true or exec_err ~= nil, "rotation tick should execute or return guarded reason")
    T.assert_true(exec_err == nil or exec_err == ErrorCodes.CAST_GUARD_BLOCKED or exec_err == ErrorCodes.CAST_INVALID_TARGET,
        "rotation tick error should be explicit guard/cast code")

    return {
        sc008_rotation_contract = true,
    }
end

return { run = run }
