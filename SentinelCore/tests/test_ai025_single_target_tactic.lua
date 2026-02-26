local T = require("tests/TestUtil")

return { run = function()
    local SingleTargetTactic = require("tactics/SingleTargetTactic")
    local BT = require("ai/BehaviorTree")

    -- 1. Preconditions always pass (fallback tactic)
    local tactic = SingleTargetTactic:new()
    T.assert_true(tactic:check_preconditions({}), "always available")
    T.assert_eq(tactic:get_name(), "single_target", "correct name")

    -- 2. Utility baseline
    local ctx_idle = { enemy_count = 0, player_mana_pct = 0.8 }
    local score = tactic:score_utility(ctx_idle, nil)
    T.assert_true(score >= 0.4 and score <= 1.0, "utility in valid range: " .. tostring(score))

    -- 3. Utility increases when low mana (safer to single-target)
    local ctx_low_mana = { enemy_count = 1, player_mana_pct = 0.10 }
    local score_low = tactic:score_utility(ctx_low_mana, nil)
    T.assert_true(score_low >= 0.5, "higher utility when low mana")

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

    return true
end }
