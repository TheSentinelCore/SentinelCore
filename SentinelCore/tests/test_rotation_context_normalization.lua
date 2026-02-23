local T = require("tests/TestUtil")

local function run()
    local player = T.mock_object({ health = 650, max_health = 1000, in_combat = true })
    local target = T.mock_object({ health = 250, max_health = 1000, casting = true })
    player._target = target
    function target:get_creature_type()
        return 6
    end

    function player:get_power(power_type)
        if tonumber(power_type) == 1 then
            return 0
        end
        return 220
    end

    function player:get_max_power(power_type)
        if tonumber(power_type) == 1 then
            return 100
        end
        return 1000
    end

    local env = T.install_core_stub({
        object_manager = {
            get_local_player = function()
                return player
            end,
        },
        spell_book = {
            is_usable_spell = function() return true end,
            is_spell_learned = function(id) return id == 27137 end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local CombatContext = require("rotations/framework/CombatContext")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.object", player)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("combat.target", target)
    bb:set("player.class_id", 2)
    bb:set("player.spec_id", 0)
    bb:set("combat.enemy_count", 1)
    bb:set("player.in_combat", true)

    local ctx_builder = CombatContext:new(bb)

    local unit_helper_100_scale = {
        get_health_percentage = function(_, unit)
            if unit == player then
                return 65
            end
            return 25
        end,
        get_resource_percentage = function(_, unit, power_type)
            return 22
        end,
    }

    local enums = {
        power_type = {
            MANA = 0,
        },
    }

    local ctx = ctx_builder:build({
        enums = enums,
        helpers = {
            unit_helper = unit_helper_100_scale,
            distance_3d = function(_, _) return 5 end,
        },
    })

    T.assert_eq(ctx.player_health_pct, 0.65, "player health pct must normalize 65 -> 0.65")
    T.assert_eq(ctx.target_health_pct, 0.25, "target health pct must normalize 25 -> 0.25")
    T.assert_eq(ctx.player_mana_pct, 0.22, "mana pct must normalize 22 -> 0.22")
    T.assert_true(ctx.target_is_undead_or_demon == true, "context should identify undead targets for spell gating")
    T.assert_true(ctx.target_is_casting == true and ctx.target_is_channeling == false,
        "context should expose cast/channel states separately")
    T.assert_true(ctx.target_is_casting_or_channeling == true,
        "context should expose combined cast/channel state for interrupt guards")
    T.assert_true(type(ctx.target_is_creature_type) == "function" and ctx.target_is_creature_type("undead") == true,
        "context should provide creature-type predicate helper")

    target._casting = false
    target._channeling = true
    local ctx_channel = ctx_builder:build({
        enums = enums,
        helpers = {
            unit_helper = unit_helper_fraction,
            distance_3d = function(_, _) return 5 end,
        },
    })
    T.assert_true(ctx_channel.target_is_casting == false and ctx_channel.target_is_channeling == true,
        "context should detect channeling targets for interrupt logic")
    T.assert_true(ctx_channel.target_is_casting_or_channeling == true,
        "combined cast/channel flag should stay true for channeling targets")
    target._casting = true
    target._channeling = false

    local unit_helper_fraction = {
        get_health_percentage = function(_, unit)
            if unit == player then
                return 0.65
            end
            return 0.25
        end,
        get_resource_percentage = function(_, unit, power_type)
            return 0.22
        end,
    }

    local ctx2 = ctx_builder:build({
        enums = enums,
        helpers = {
            unit_helper = unit_helper_fraction,
            distance_3d = function(_, _) return 5 end,
        },
    })

    T.assert_eq(ctx2.player_health_pct, 0.65, "player health pct should remain 0.65")
    T.assert_eq(ctx2.target_health_pct, 0.25, "target health pct should remain 0.25")
    T.assert_eq(ctx2.player_mana_pct, 0.22, "mana pct should remain 0.22")

    local unit_helper_stale = {
        get_health_percentage = function(_, unit)
            if unit == player then
                return 0.65
            end
            return 0.25
        end,
        get_resource_percentage = function(_, unit, power_type)
            return 1.00 -- stale/incorrect helper reading
        end,
    }
    local ctx_stale = ctx_builder:build({
        enums = enums,
        helpers = {
            unit_helper = unit_helper_stale,
            distance_3d = function(_, _) return 5 end,
        },
    })
    T.assert_true(type(ctx_stale.player_mana_pct) == "number" and ctx_stale.player_mana_pct >= 0.21 and ctx_stale.player_mana_pct <= 0.23,
        "mana context should prefer reliable unit power ratios over stale helper percentages")

    local ctx3 = ctx_builder:build({
        enums = {
            power_type = {
                MANA = 1, -- simulate mismatched enum source; fallback should still resolve mana via power(0)
            },
        },
        helpers = {
            unit_helper = nil,
            distance_3d = function(_, _) return 5 end,
        },
    })
    T.assert_true(type(ctx3.player_mana_pct) == "number" and ctx3.player_mana_pct >= 0.21 and ctx3.player_mana_pct <= 0.23,
        "mana normalization should fall back to reliable unit APIs even when enum mana type is mismatched")

    -- Simulate wrappers that expose get_mana but do not expose get_max_mana.
    -- Context must not infer 100% from partial APIs and should prefer power ratios when available.
    function player:get_mana()
        return 500
    end
    function player:get_max_mana()
        return nil
    end
    function player:get_power(power_type)
        if tonumber(power_type) == 0 then
            return 100
        end
        return nil
    end
    function player:get_max_power(power_type)
        if tonumber(power_type) == 0 then
            return 1000
        end
        return nil
    end

    local ctx4 = ctx_builder:build({
        enums = enums,
        helpers = {
            unit_helper = unit_helper_stale, -- stale helper must not override reliable unit power ratio
            distance_3d = function(_, _) return 5 end,
        },
    })
    T.assert_true(type(ctx4.player_mana_pct) == "number" and ctx4.player_mana_pct >= 0.09 and ctx4.player_mana_pct <= 0.11,
        "mana normalization should not infer full mana when get_max_mana is unavailable")

    -- When both direct mana/max and power/max are unavailable, helper fallback should still be used.
    function player:get_power(power_type)
        return nil
    end
    function player:get_max_power(power_type)
        return nil
    end

    local ctx5 = ctx_builder:build({
        enums = enums,
        helpers = {
            unit_helper = unit_helper_100_scale,
            distance_3d = function(_, _) return 5 end,
        },
    })
    T.assert_eq(ctx5.player_mana_pct, 0.22,
        "mana normalization should use helper fallback when direct resource APIs are incomplete")

    -- ── New context fields: CC, interrupt, TTD, attack speed ─────
    do
        local player2 = T.mock_object({ health = 800, max_health = 1000, in_combat = true })
        local target2 = T.mock_object({ health = 500, max_health = 1000, casting = true })
        player2._stunned = false
        player2._rooted = true
        player2._silenced = false
        player2._feared = false
        function player2:is_stunned() return self._stunned end
        function player2:is_rooted() return self._rooted end
        function player2:is_silenced() return self._silenced end
        function player2:is_feared() return self._feared end
        function player2:get_attack_speed() return 3.8 end
        function player2:get_loss_of_control_info() return { valid = false } end
        function player2:get_power(pt) return 800 end
        function player2:get_max_power(pt) return 1000 end

        function target2:is_active_spell_interruptable() return true end
        function target2:get_active_spell_id() return 12345 end
        function target2:get_active_spell_cast_end_time() return 1002.0 end
        function target2:get_active_spell_cast_start_time() return 999.0 end
        function target2:time_to_die() return 15.5 end

        local bus2 = EventBus:new()
        local bb2 = Blackboard:new(bus2)
        bb2:set("player.object", player2)
        bb2:set("player.position", { x = 0, y = 0, z = 0 })
        bb2:set("combat.target", target2)
        bb2:set("player.class_id", 2)
        bb2:set("player.in_combat", true)
        bb2:set("combat.enemy_count", 1)

        local ctx_builder2 = CombatContext:new(bb2)
        local ctx_new = ctx_builder2:build({
            enums = enums,
            helpers = { distance_3d = function(_, _) return 5 end },
        })

        T.assert_eq(ctx_new.player_is_stunned, false, "player_is_stunned should be false")
        T.assert_eq(ctx_new.player_is_rooted, true, "player_is_rooted should be true")
        T.assert_eq(ctx_new.player_is_silenced, false, "player_is_silenced should be false")
        T.assert_eq(ctx_new.player_is_feared, false, "player_is_feared should be false")
        T.assert_eq(ctx_new.player_is_casting, false, "player_is_casting should be false when not casting")
        T.assert_eq(ctx_new.player_attack_speed, 3.8, "player_attack_speed should be 3.8")
        T.assert_eq(ctx_new.target_is_interruptable, true, "target_is_interruptable should be true")
        T.assert_eq(ctx_new.target_active_spell_id, 12345, "target_active_spell_id should be 12345")
        T.assert_true(ctx_new.target_ttd_seconds == 15.5, "target_ttd_seconds should be 15.5")
        T.assert_true(type(ctx_new.player_aura_remaining) == "function", "player_aura_remaining should be a function")
        T.assert_true(ctx_new.target_cast_progress > 0, "target_cast_progress should be > 0 during active cast")
    end

    return {
        rotation_context_normalization = true,
    }
end

return { run = run }
