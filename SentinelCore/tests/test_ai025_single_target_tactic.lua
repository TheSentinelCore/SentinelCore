local T = require("tests/TestUtil")

return { run = function()
    local SingleTargetTactic = require("tactics/SingleTargetTactic")
    local BT = require("ai/BehaviorTree")

    -- 1. Preconditions always pass (fallback tactic)
    local tactic = SingleTargetTactic:new()
    T.assert_true(tactic:check_preconditions({}), "always available")
    T.assert_eq(tactic:get_name(), "single_target", "correct name")

    -- 2. Utility baseline: 0 enemies → 0.7 (enemy_count<=1 bump)
    local ctx_idle = { enemy_count = 0, player_mana_pct = 0.8 }
    local score = tactic:score_utility(ctx_idle, nil)
    T.assert_eq(score, 0.7, "baseline utility with 0 enemies")

    -- 3. Utility increases when low mana (safer to single-target)
    local ctx_low_mana = { enemy_count = 1, player_mana_pct = 0.10 }
    local score_low = tactic:score_utility(ctx_low_mana, nil)
    T.assert_eq(score_low, 0.8, "utility boost when low mana")

    -- 4. Default rest config (standard thresholds)
    local rest = tactic:get_rest_config()
    T.assert_eq(rest.drink_below, 0.30, "default drink threshold")
    T.assert_eq(rest.eat_below, 0.50, "default eat threshold")

    -- 5. Target config: no cluster preference
    local target_cfg = tactic:get_target_config()
    T.assert_eq(target_cfg.prefer_clusters, false, "no cluster preference")

    -- 6. Explore config: frontier mode
    local explore_cfg = tactic:get_explore_config()
    T.assert_eq(explore_cfg.mode, "frontier", "frontier exploration")

    -- 7. Has two phases: engage and combat
    local phases = tactic:get_phases()
    T.assert_eq(#phases, 2, "two phases")
    T.assert_eq(phases[1].name, "engage", "first phase is engage")
    T.assert_eq(phases[2].name, "combat", "second phase is combat")

    -- 8. Reset does not error
    tactic:reset()

    -- 9. AoE penalty: pack detected with sufficient mana
    -- enemy_count=3 (>1 → base stays 0.5), pack_count=4, mana=0.50 → 0.5 * 0.6 = 0.3
    local ctx_pack = { enemy_count = 3, player_mana_pct = 0.50, pack_count = 4 }
    local score_pack = tactic:score_utility(ctx_pack, nil)
    T.assert_eq(score_pack, 0.3, "penalized when pack detected with mana")

    -- 10. AoE penalty skipped when low mana
    local ctx_pack_low = { enemy_count = 1, player_mana_pct = 0.10, pack_count = 5 }
    local score_pack_low = tactic:score_utility(ctx_pack_low, nil)
    T.assert_eq(score_pack_low, 0.8, "pack penalty skipped when low mana")

    -- 11. Phase predicates
    T.assert_true(phases[1].enter_if({ has_target = true, in_combat = false }), "engage enters")
    T.assert_eq(phases[1].enter_if({ has_target = true, in_combat = true }), false, "engage blocked in combat")
    T.assert_eq(phases[1].exit_if({ in_combat = true }), true, "engage exits on combat")
    T.assert_true(phases[2].enter_if({ in_combat = true }), "combat enters in combat")
    T.assert_true(phases[2].exit_if({ in_combat = false, target_alive = false }), "combat exits target dead")

    -- 12. Phase ticks return FAILURE without deps
    T.assert_eq(phases[1].tick({}, {}), BT.Status.FAILURE, "engage FAILURE without pull_node")
    T.assert_eq(phases[2].tick({}, {}), BT.Status.FAILURE, "combat FAILURE without combat_node")

    -- 13. Nil context fields default to safe single-target
    local score_empty = tactic:score_utility({}, nil)
    T.assert_eq(score_empty, 0.7, "nil fields default to safe single-target")

    return true
end }
