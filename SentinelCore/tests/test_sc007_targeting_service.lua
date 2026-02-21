local T = require("tests/TestUtil")

local function run()
    local player = T.mock_object({
        level = 10,
        class_id = 2,
        position = { x = 0, y = 0, z = 0 },
    })

    local target_near_lowhp = T.mock_object({
        name = "NearLowHp",
        level = 10,
        health = 20,
        max_health = 100,
        position = { x = 5, y = 0, z = 0 },
    })

    local target_far_fullhp = T.mock_object({
        name = "FarFullHp",
        level = 10,
        health = 100,
        max_health = 100,
        position = { x = 35, y = 0, z = 0 },
    })

    T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return { target_far_fullhp, target_near_lowhp } end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local TargetingService = require("services/TargetingService")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)

    bb:set("player.object", player)
    bb:set("player.position", player:get_position())
    bb:set("player.in_combat", false)

    local targeting = TargetingService:new(bus, bb, {
        base_radius = 40,
        max_radius = 60,
        score_weights = {
            kill_speed = 0.5,
            loot_value = 0.2,
            travel_cost = 0.2,
            risk = 0.1,
        },
    })

    local target, err = targeting:acquire_target()
    T.assert_true(target ~= nil and target:get_name() == "NearLowHp", "target scoring should be deterministic")
    T.assert_eq(bb:get("combat.enemy_count", 0), 1, "nearby enemy count should be populated for rotation aoe routing")

    return {
        sc007_target_scoring = true,
    }
end

return { run = run }
