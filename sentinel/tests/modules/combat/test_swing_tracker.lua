local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SwingTracker = require("modules/combat/swing_tracker")
local T = require("tests/test_util")

local M = {}

local function make_player()
    local unit = {}
    function unit:get_guid() return "player" end
    return unit
end

function M.run()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local tracker = SwingTracker:new(bus, bb)

    bb:set("system.now_ms", 1000)
    bb:set("player.object", make_player())
    bb:set("player.is_auto_attacking", true)
    bb:set("player.attack_speed_s", 3.0)
    bb:set("module.combat.twist_mode", "auto")
    bb:set("module.combat.allow_estimated_twist", false)
    bb:set("module.combat.twist_window_ms", 350)

    tracker:update(bb)
    T.assert_false(bb:get("rotation.twist.enabled"))

    bb:set("module.combat.allow_estimated_twist", true)
    tracker:update(bb)
    T.assert_true(bb:get("rotation.twist.enabled"))
end

return M
