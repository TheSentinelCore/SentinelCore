local Blackboard = require("core/blackboard")
local StrategyEngine = require("modules/battleground/strategy_engine")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    local engine = StrategyEngine:new(bb)

    local evaluation = engine:evaluate({
        bg_key = "EOTS",
        player_side = "ALLIANCE",
        player_position = { x = 2200, y = 1570, z = 1160 },
        objective_states = {
            CENTER_FLAG = { owner = "NEUTRAL" },
            MAGE_TOWER = { owner = "FRIENDLY" },
            DRAENEI_RUINS = { owner = "FRIENDLY" },
            BLOOD_ELF = { owner = "ENEMY" },
            FEL_REAVER = { owner = "ENEMY" },
        },
        strategy_settings = {
            objective_skip_if_satisfied_radius = 18,
            objective_skip_threat_enemy_count = 0,
        },
        bootstrap_phase = "active",
    })

    T.assert_not_nil(evaluation)
    T.assert_equal(evaluation.strategy_id, "balanced")
    T.assert_not_nil(evaluation.selected)
    T.assert_true(evaluation.selected.id ~= "CENTER_FLAG")
    T.assert_equal(evaluation.default_route_id, nil)
    T.assert_true(
        evaluation.bootstrap_route_id == "EOTS_A_BOOTSTRAP_MAGE_TOWER"
        or evaluation.bootstrap_route_id == "EOTS_A_BOOTSTRAP_DRAENEI"
    )
end

return M
