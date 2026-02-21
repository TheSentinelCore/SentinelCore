local T = require("tests/TestUtil")

local function run()
    local player = T.mock_object({ health = 650, max_health = 1000, in_combat = true })
    local target = T.mock_object({ health = 250, max_health = 1000, casting = true })
    player._target = target

    function player:get_power(power_type)
        return 220
    end

    function player:get_max_power(power_type)
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

    return {
        rotation_context_normalization = true,
    }
end

return { run = run }
