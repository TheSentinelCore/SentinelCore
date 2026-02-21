local T = require("tests/TestUtil")
local ErrorCodes = require("events/ErrorCodes")

local function run()
    local player = T.mock_object({ class_id = 2, spec_id = 0 })
    local target = T.mock_object({ name = "Enemy" })

    T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return { target } end,
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

    local rotation = RotationEngine:new(bus, bb, { aoe_enemy_threshold = 3 })
    local plan, err = rotation:generate_plan()
    T.assert_true(type(plan) == "table" and #plan > 0, "rotation plan should exist")
    local has_divine_storm = false
    local has_crusader_strike = false
    local has_judgement = false
    for i = 1, #plan do
        local spell_id = tonumber(plan[i].spell_id) or 0
        if spell_id == 53385 then
            has_divine_storm = true
        elseif spell_id == 35395 then
            has_crusader_strike = true
        elseif spell_id == 20271 then
            has_judgement = true
        end
    end
    T.assert_true(has_divine_storm == false, "TBC retribution plan must not include Divine Storm")
    T.assert_true(has_crusader_strike == true, "retribution plan missing Crusader Strike")
    T.assert_true(has_judgement == true, "retribution plan missing Judgement")

    local executed, exec_err = rotation:tick_once()
    T.assert_true(executed == true or exec_err ~= nil, "rotation tick should execute or return guarded reason")
    T.assert_true(exec_err == nil or exec_err == ErrorCodes.CAST_GUARD_BLOCKED or exec_err == ErrorCodes.CAST_INVALID_TARGET,
        "rotation tick error should be explicit guard/cast code")

    return {
        sc008_rotation_contract = true,
    }
end

return { run = run }
