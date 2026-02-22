local T = require("tests/TestUtil")
local ErrorCodes = require("events/ErrorCodes")
local Events = require("events/Events")

local function run()
    local player = T.mock_object({ class_id = 2, spec_id = 0, health = 60, max_health = 100, mana = 30, max_mana = 100 })
    local target = T.mock_object({ name = "Enemy" })
    function target:get_guid() return 101 end
    local food_item = T.mock_object({ item_id = 4540 })
    local water_item = T.mock_object({ item_id = 159 })

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
                        { item = water_item, slot_id = 25 },
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
    local blocked_events = 0
    bus:on(Events.ROTATION_BLOCKED, function(data)
        blocked_events = blocked_events + 1
    end, { owner = rotation })
    local plan, err = rotation:generate_plan()
    T.assert_true(type(plan) == "table" and #plan > 0, "rotation plan should exist")
    local movement_profile = rotation:get_movement_profile()
    T.assert_eq(tonumber(movement_profile.combat_chase_range), 5.5,
        "retribution movement profile should request melee chase range")
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

    -- Drink priority validation: when HP is healthy and mana is low, maintenance should consume water, not food.
    player._health = 100
    player._mana = 20
    bb:set("player.in_combat", false)
    bb:set("rotation.rest.lock_until", 0)
    if core and core._set_time and core.time then
        core._set_time(core.time() + 1.0)
    end
    local queue = require("common/modules/spell_queue")
    local before_entries = queue and queue.get_entries and #queue:get_entries() or 0
    local drink_tick_ok, drink_tick_err = rotation:tick_maintenance_once()
    T.assert_true(drink_tick_ok == true, "maintenance should execute a drink action when only mana is low")
    local entries_after_drink = queue and queue.get_entries and queue:get_entries() or {}
    local drink_entry = entries_after_drink[#entries_after_drink]
    T.assert_true(#entries_after_drink > before_entries, "drink maintenance should enqueue a new action")
    T.assert_true(type(drink_entry) == "table" and tonumber(drink_entry.item_id) == 159,
        "drink maintenance should queue a water consumable when HP is healthy and mana is low")

    local original_build_context = rotation._context_builder.build
    rotation._context_builder.build = function()
        return {
            class_id = 2,
            spec_id = 0,
            in_combat = false,
            eating_or_drinking = true,
            player_health_pct = 1.0,
            player_mana_pct = 1.0,
            routine_policy = bb:get("rotation.policy"),
        }
    end
    T.assert_true(rotation:should_hold_maintenance() == false,
        "active drink/eat aura should not hold pulls once resources are already full")
    rotation._context_builder.build = original_build_context

    bb:set("player.class_id", 1)
    local unsupported_plan, unsupported_err = rotation:generate_plan()
    T.assert_true(unsupported_plan == nil, "unsupported class should not resolve a combat plan")
    T.assert_eq(unsupported_err, ErrorCodes.ROTATION_UNAVAILABLE, "unsupported class should return rotation unavailable")
    T.assert_true(rotation:should_hold_maintenance() == false, "unsupported class should not inherit paladin rest thresholds")

    bb:set("player.class_id", 2)
    local restored_plan, restored_err = rotation:generate_plan()
    T.assert_true(type(restored_plan) == "table" and #restored_plan > 0, "paladin plan should recover after class switch")

    bb:set("player.class_id", 9)
    bb:set("player.spec_id", 0)
    local warlock_plan, warlock_err = rotation:generate_plan()
    T.assert_true(type(warlock_plan) == "table" and #warlock_plan > 0,
        "warlock class should resolve a combat plan even when spec is unset (0)")

    bb:set("player.class_id", 2)
    bb:set("player.spec_id", 0)

    local executed, exec_err = rotation:tick_once()
    T.assert_true(executed == true or exec_err ~= nil, "rotation tick should execute or return guarded reason")
    T.assert_true(exec_err == nil or exec_err == ErrorCodes.CAST_GUARD_BLOCKED or exec_err == ErrorCodes.CAST_INVALID_TARGET,
        "rotation tick error should be explicit guard/cast code")

    local queue = require("common/modules/spell_queue")
    local entries = queue and queue.get_entries and queue:get_entries() or {}
    if type(entries) == "table" and #entries > 0 then
        local last = entries[#entries]
        local qp = tonumber(last.priority) or 0
        T.assert_true(qp >= 1 and qp <= 8, "queue priority should be normalized to API-supported range 1..8")
    end

    local self_target_swaps = 0
    local previous_set_target = core.input.set_target
    core.input.set_target = function()
        self_target_swaps = self_target_swaps + 1
        return true
    end

    local self_ctx = {
        player = io.stdout,
        target = target,
    }
    local self_action = {
        action_type = "cast_spell_self",
        spell_id = 27136,
        priority = 900,
        allow_movement = true,
        skip_facing = true,
    }
    local self_exec_ok, self_exec_err = rotation:execute_action(self_action, self_ctx)
    T.assert_true(self_exec_ok == true or self_exec_err ~= nil,
        "self cast execution should be deterministic (success or explicit guard error)")
    T.assert_eq(self_target_swaps, 0, "self casts should not swap target away from enemy")
    core.input.set_target = previous_set_target

    local blocked_ok, blocked_err = rotation:_execute_plan({
        {
            action_type = "cast_spell_target",
            spell_id = 20271,
            priority = 1000,
            condition = function()
                return false
            end,
            requires_castable_check = false,
        },
    }, {
        player = player,
        target = target,
        player_is_moving = false,
    })
    T.assert_true(blocked_ok == false and blocked_err ~= nil, "blocked plan execution should return an explicit guard error")
    T.assert_true(blocked_events >= 1, "rotation should emit blocked diagnostics when no action can execute")

    rotation._action_retry_until = {}
    rotation._action_retry_last_sweep_at = 0
    local retry_attempts = 0
    local original_execute_action = rotation.execute_action
    rotation.execute_action = function(self, action, ctx)
        retry_attempts = retry_attempts + 1
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    local retry_action = {
        action_type = "cast_spell_target",
        spell_id = 20271,
        priority = 1000,
        allow_movement = true,
        requires_castable_check = false,
    }
    local retry_ctx = {
        player = player,
        target = target,
        player_is_moving = false,
        player_health_pct = 1.0,
        target_health_pct = 1.0,
        player_mana_pct = 1.0,
        target_distance = 5.0,
        now = core.time(),
    }

    local retry_ok_1, retry_err_1 = rotation:_execute_plan({ retry_action }, retry_ctx, { emit_blocked = false })
    T.assert_true(retry_ok_1 == false and retry_err_1 ~= nil, "retry governor setup should produce an initial blocked action")
    T.assert_eq(retry_attempts, 1, "first blocked execution should attempt action once")

    local retry_ok_2, retry_err_2 = rotation:_execute_plan({ retry_action }, retry_ctx, { emit_blocked = false })
    T.assert_true(retry_ok_2 == false and retry_err_2 == ErrorCodes.CAST_GUARD_BLOCKED,
        "second execution within retry window should be blocked by retry governor")
    T.assert_eq(retry_attempts, 1, "retry window should suppress immediate reattempts for same action key")

    local alt_target = T.mock_object({ name = "AltEnemy" })
    function alt_target:get_guid() return 202 end
    retry_ctx.target = alt_target
    local retry_ok_3, retry_err_3 = rotation:_execute_plan({ retry_action }, retry_ctx, { emit_blocked = false })
    T.assert_true(retry_ok_3 == false and retry_err_3 ~= nil,
        "same action on a different target key should still be attempted during original target backoff")
    T.assert_eq(retry_attempts, 2, "retry key should include target guid so different targets do not share backoff")

    if core and core._set_time and core.time then
        core._set_time(core.time() + 0.6)
    end
    retry_ctx.target = target
    retry_ctx.now = core.time()
    local retry_ok_4, retry_err_4 = rotation:_execute_plan({ retry_action }, retry_ctx, { emit_blocked = false })
    T.assert_true(retry_ok_4 == false and retry_err_4 ~= nil,
        "action should be retried after retry window expires")
    T.assert_eq(retry_attempts, 3, "expired retry window should allow a fresh action attempt")

    rotation.execute_action = original_execute_action

    return {
        sc008_rotation_contract = true,
        sc008_retry_governor = true,
    }
end

return { run = run }
