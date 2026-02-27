local T = require("tests/TestUtil")

return { run = function()
    local TacticalSelector = require("ai/TacticalSelector")
    local TacticalPlanner = require("ai/TacticalPlanner")
    local PackTracker = require("ai/PackTracker")
    local SingleTargetTactic = require("tactics/SingleTargetTactic")
    local BT = require("ai/BehaviorTree")

    -- Full lifecycle test
    local selector = TacticalSelector:new(nil)
    local planner = TacticalPlanner:new()
    local tracker = PackTracker:new()

    -- Register SingleTarget
    selector:register(SingleTargetTactic:new())
    selector:refresh_available({})
    T.assert_eq(selector:get_available_count(), 1, "1 tactic available")

    -- Simulate: idle state (no combat, no target)
    local ctx1 = { enemy_count = 0, player_mana_pct = 1.0, pack_count = 0,
                   has_target = false, in_combat = false }
    local active1 = selector:select(ctx1)
    T.assert_eq(active1:get_name(), "single_target", "ST selected when idle")

    -- Simulate: target acquired, not yet in combat
    local ctx2 = { enemy_count = 1, player_mana_pct = 0.8, pack_count = 1,
                   has_target = true, in_combat = false }
    planner:set_tactic(active1)
    local status2 = planner:tick(ctx2, {})
    T.assert_eq(planner:get_current_phase_name(), "engage", "engage phase on target")

    -- Simulate: now in combat
    local ctx3 = { enemy_count = 1, player_mana_pct = 0.7, pack_count = 1,
                   has_target = true, in_combat = true, target_alive = true }
    local status3 = planner:tick(ctx3, {})
    T.assert_eq(planner:get_current_phase_name(), "combat", "combat phase when fighting")

    -- Simulate: combat ended
    local ctx4 = { enemy_count = 0, player_mana_pct = 0.3, pack_count = 0,
                   has_target = false, in_combat = false, target_alive = false }
    local status4 = planner:tick(ctx4, {})
    -- No phase should match (no target, no combat)
    T.assert_eq(status4, BT.Status.FAILURE, "no phase when idle -- yields to loot/rest/explore")

    -- PackTracker: verify empty update
    tracker:update({}, { x = 0, y = 0, z = 0 }, "player")
    T.assert_eq(tracker:get_pack().count, 0, "empty pack")

    return true
end }
