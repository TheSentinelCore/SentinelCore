local T = require("tests/TestUtil")

local function run()
    -- Test 1: Durability pct is set on blackboard
    local player = T.mock_object({ faction_id = 1 })
    player.get_durability_pct = function() return 0.75 end

    T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local Sensors = require("core/Sensors")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local sensors = Sensors:new(bb)

    sensors:update()
    T.assert_eq(bb:get("player.durability_pct", -1), 0.75, "durability_pct should be 0.75")

    -- Test 2: Missing durability API defaults to 1.0
    player.get_durability_pct = nil
    sensors:update()
    T.assert_eq(bb:get("player.durability_pct", -1), 1.0, "missing durability API should default to 1.0")

    return {
        sc024_durability_sensor = true,
        sc024_durability_fallback = true,
    }
end

return { run = run }
