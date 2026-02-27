local T = require("tests/TestUtil")

return { run = function()
    local TacticalSelector = require("ai/TacticalSelector")
    local TacticalPlanner = require("ai/TacticalPlanner")
    local SingleTargetTactic = require("tactics/SingleTargetTactic")
    local Tactic = require("ai/Tactic")
    local BT = require("ai/BehaviorTree")

    -- 1. TacticalSelector + SingleTargetTactic integration
    local selector = TacticalSelector:new(nil)
    local st = SingleTargetTactic:new()
    selector:register(st)
    selector:refresh_available({})
    T.assert_eq(selector:get_available_count(), 1, "single target available")

    local active = selector:select({ enemy_count = 1, player_mana_pct = 0.8 })
    T.assert_eq(active:get_name(), "single_target", "single target selected")

    -- 2. TacticalPlanner ticks SingleTargetTactic phases
    local planner = TacticalPlanner:new()
    planner:set_tactic(st)

    -- Engage phase: has_target=true, not in combat
    local ctx_pull = { has_target = true, in_combat = false }
    local status = planner:tick(ctx_pull, {})
    T.assert_eq(planner:get_current_phase_name(), "engage", "engage phase active")
    -- tick returns FAILURE because deps.pull_node is nil (expected in test)
    T.assert_eq(status, BT.Status.FAILURE, "no pull_node -> FAILURE")

    -- Combat phase: in_combat=true
    local ctx_combat = { has_target = true, in_combat = true, target_alive = true }
    planner:reset()
    planner:set_tactic(st)
    local status2 = planner:tick(ctx_combat, {})
    T.assert_eq(planner:get_current_phase_name(), "combat", "combat phase active")

    -- 3. Two tactics: SingleTarget + a mock AoE, selector picks correct one
    local aoe_mock = Tactic:new({
        name = "aoe_mock",
        preconditions = function() return true end,
        utility = function(ctx)
            local pack = tonumber(ctx.pack_count) or 0
            if pack >= 3 then return 0.9 end
            return 0.1
        end,
        phases = {
            { name = "gather", enter_if = function() return true end,
              tick = function() return BT.Status.RUNNING end,
              exit_if = function() return false end },
        },
    })

    local selector2 = TacticalSelector:new(nil)
    selector2:register(st)
    selector2:register(aoe_mock)
    selector2:refresh_available({})

    -- Low pack count -> single target wins
    local pick1 = selector2:select({ enemy_count = 1, player_mana_pct = 0.8, pack_count = 0 })
    T.assert_eq(pick1:get_name(), "single_target", "ST wins with no pack")

    -- High pack count -> AoE wins
    local pick2 = selector2:select({ enemy_count = 5, player_mana_pct = 0.8, pack_count = 5 })
    T.assert_eq(pick2:get_name(), "aoe_mock", "AoE wins with pack of 5")

    return true
end }
