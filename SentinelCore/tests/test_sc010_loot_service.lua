local T = require("tests/TestUtil")
local ErrorCodes = require("events/ErrorCodes")

local function run()
    local loot_count = 2
    local target = T.mock_object({ name = "Corpse", dead = true, position = { x = 0, y = 0, z = 0 } })

    T.install_core_stub({
        game_ui = {
            get_loot_item_count = function() return loot_count end,
        },
        input = {
            loot_object = function() end,
            loot_item = function() end,
            close_loot = function() end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local LootService = require("services/LootService")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.position", { x = 0, y = 0, z = 0 })

    local loot = LootService:new(bus, bb, {
        loot_timeout = 5,
        interaction_retry_limit = 2,
        interaction_retry_delay = 0.1,
    })

    local ok = loot:start(target)
    T.assert_true(ok == true, "loot start should pass")

    local u1 = loot:update()
    T.assert_true(u1 == true and loot:get_state() == "completed", "loot should complete")

    local nav_calls = { move_to = 0, stop = 0 }
    local nav = {
        move_to = function(_, pos)
            nav_calls.move_to = nav_calls.move_to + 1
        end,
        stop = function()
            nav_calls.stop = nav_calls.stop + 1
        end,
    }

    loot_count = 1
    local far_target = T.mock_object({ name = "FarCorpse", dead = true, position = { x = 20, y = 0, z = 0 } })
    local loot_with_approach = LootService:new(bus, bb, {
        loot_timeout = 5,
        interaction_retry_limit = 2,
        interaction_retry_delay = 0.1,
        loot_interact_range = 5.0,
        loot_approach_max_distance = 40.0,
        loot_approach_timeout = 2.0,
        loot_approach_reissue_cooldown = 0.3,
    }, nav)
    local a_ok, a_err = loot_with_approach:start(far_target)
    T.assert_true(a_ok == true and a_err == nil, "loot start should succeed for approach scenario")
    local a_update_1, a_err_1 = loot_with_approach:update()
    T.assert_true(a_update_1 == true and a_err_1 == nil and loot_with_approach:get_state() == "looting",
        "far corpse should trigger approach before interaction")
    T.assert_eq(nav_calls.move_to, 1, "approach should request navigation move_to for far corpse")
    bb:set("player.position", { x = 20, y = 0, z = 0 })
    local a_update_2, a_err_2 = loot_with_approach:update()
    T.assert_true(a_update_2 == true and a_err_2 == nil and loot_with_approach:get_state() == "completed",
        "loot should complete after approaching into interaction range")
    T.assert_true(nav_calls.stop >= 1, "loot service should stop navigation once corpse is in range")

    local unreachable_target = T.mock_object({
        name = "UnreachableCorpse",
        dead = true,
        position = { x = 80, y = 0, z = 0 },
    })
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    local loot_unreachable = LootService:new(bus, bb, {
        loot_timeout = 5,
        interaction_retry_limit = 2,
        interaction_retry_delay = 0.1,
        loot_interact_range = 5.0,
        loot_approach_max_distance = 30.0,
    }, nav)
    local u_ok, u_err = loot_unreachable:start(unreachable_target)
    T.assert_true(u_ok == true and u_err == nil, "loot start should succeed for unreachable scenario")
    local u_update, u_update_err = loot_unreachable:update()
    T.assert_true(u_update == false and u_update_err == ErrorCodes.LOOT_FAILED,
        "loot should fail fast when corpse is outside approach max distance")

    return {
        sc010_loot_pipeline = true,
        sc010_loot_approach_and_abandon = true,
    }
end

return { run = run }
