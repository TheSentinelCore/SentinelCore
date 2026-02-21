local T = require("tests/TestUtil")

local function run()
    local loot_count = 2
    local target = T.mock_object({ name = "Corpse", dead = true })

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

    local loot = LootService:new(bus, bb, {
        loot_timeout = 5,
        interaction_retry_limit = 2,
        interaction_retry_delay = 0.1,
    })

    local ok = loot:start(target)
    T.assert_true(ok == true, "loot start should pass")

    local u1 = loot:update()
    T.assert_true(u1 == true and loot:get_state() == "completed", "loot should complete")

    return {
        sc010_loot_pipeline = true,
    }
end

return { run = run }
