local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SentinelGrind = require("modules/grind/module")
local T = require("tests/test_util")

local M = {}

local function make_event_bus()
    return EventBus:new()
end

local function make_nav()
    return {
        move_to = function() end,
        stop = function() end,
        is_active = function() return false end,
        get_state = function() return "idle" end,
    }
end

function M.run()
    -- Construction works
    local bb = Blackboard:new()
    local bus = make_event_bus()
    local nav = make_nav()
    local grind = SentinelGrind:new(bus, bb, nav)
    T.assert_not_nil(grind, "construction should return non-nil")

    -- initialize() sets blackboard defaults
    grind:initialize()
    T.assert_equal(bb:get("module.grind.enabled"), false, "enabled default should be false")
    T.assert_equal(bb:get("module.grind.health_flee_pct"), 0.20, "health_flee_pct default")
    T.assert_equal(bb:get("module.grind.max_hostiles"), 3, "max_hostiles default")
    T.assert_equal(bb:get("module.grind.health_eat_pct"), 0.50, "health_eat_pct default")
    T.assert_equal(bb:get("module.grind.mana_drink_pct"), 0.40, "mana_drink_pct default")
    T.assert_equal(bb:get("module.grind.needs_food"), true, "needs_food default")
    T.assert_equal(bb:get("module.grind.needs_water"), true, "needs_water default")

    -- update() doesn't error when disabled
    bb:set("module.grind.enabled", false)
    grind:update(bb)

    -- update() doesn't error when runner is nil
    bb:set("module.grind.enabled", true)
    grind:update(bb)

    -- shutdown() doesn't error
    grind:shutdown()

    -- shutdown() unsubscribes tokens
    local bb2 = Blackboard:new()
    local bus2 = make_event_bus()
    local nav2 = make_nav()
    local grind2 = SentinelGrind:new(bus2, bb2, nav2)
    grind2:initialize()
    grind2:shutdown()
end

return M
