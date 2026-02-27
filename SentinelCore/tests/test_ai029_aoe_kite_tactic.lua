local T = require("tests/TestUtil")

return { run = function()
    local AoEKiteTactic = require("tactics/AoEKiteTactic")
    local SingleTargetTactic = require("tactics/SingleTargetTactic")
    local BT = require("ai/BehaviorTree")

    local tactic = AoEKiteTactic:new()

    -- 1. get_name returns "aoe_kite"
    T.assert_eq(tactic:get_name(), "aoe_kite", "correct name")

    -- 2. preconditions true: pack_count=3, mana_pct=0.5
    T.assert_true(
        tactic:check_preconditions({ pack_count = 3, player_mana_pct = 0.5, player_level = 60 }),
        "preconditions pass with pack=3 mana=0.5"
    )

    -- 3. preconditions false (low pack): pack_count=2, mana_pct=0.5
    T.assert_eq(
        tactic:check_preconditions({ pack_count = 2, player_mana_pct = 0.5, player_level = 60 }),
        false,
        "preconditions fail with low pack count"
    )

    -- 4. preconditions false (low mana): pack_count=3, mana_pct=0.20
    T.assert_eq(
        tactic:check_preconditions({ pack_count = 3, player_mana_pct = 0.20, player_level = 60 }),
        false,
        "preconditions fail with low mana"
    )

    -- 5. utility scaling: pack=3 → 0.65, pack=4 → 0.75, pack=5 → 0.85
    T.assert_eq(
        tactic:score_utility({ pack_count = 3, player_mana_pct = 0.8 }, nil),
        0.65,
        "utility pack=3"
    )
    T.assert_eq(
        tactic:score_utility({ pack_count = 4, player_mana_pct = 0.8 }, nil),
        0.75,
        "utility pack=4"
    )
    T.assert_eq(
        tactic:score_utility({ pack_count = 5, player_mana_pct = 0.8 }, nil),
        0.85,
        "utility pack=5"
    )

    -- 6. utility mana penalty: pack=3, mana=0.30 → 0.65*0.5=0.325
    T.assert_eq(
        tactic:score_utility({ pack_count = 3, player_mana_pct = 0.30 }, nil),
        0.325,
        "utility mana penalty below 0.35"
    )

    -- 7. utility vs SingleTarget: pack=3, mana=0.8
    --    AoE: 0.65, ST: base 0.5, pack>=3 and mana>0.40 → 0.5*0.6=0.30
    local st = SingleTargetTactic:new()
    local ctx_compare = { pack_count = 3, player_mana_pct = 0.8, enemy_count = 3 }
    local aoe_score = tactic:score_utility(ctx_compare, nil)
    local st_score = st:score_utility(ctx_compare, nil)
    T.assert_true(aoe_score > st_score, "AoE utility > ST utility with pack=3")
    T.assert_eq(aoe_score, 0.65, "AoE score is 0.65")
    T.assert_eq(st_score, 0.3, "ST score is 0.30 (penalized)")

    -- 8. rest_config: drink_below=0.40, eat_below=0.60, drink_until=0.90, eat_until=0.90
    local rest = tactic:get_rest_config()
    T.assert_eq(rest.drink_below, 0.40, "drink_below threshold")
    T.assert_eq(rest.eat_below, 0.60, "eat_below threshold")
    T.assert_eq(rest.drink_until, 0.90, "drink_until threshold")
    T.assert_eq(rest.eat_until, 0.90, "eat_until threshold")

    -- 9. target_config: prefer_clusters=true
    local target_cfg = tactic:get_target_config()
    T.assert_eq(target_cfg.prefer_clusters, true, "prefer_clusters enabled")

    -- 10. explore_config: mode="cluster_seek"
    local explore_cfg = tactic:get_explore_config()
    T.assert_eq(explore_cfg.mode, "cluster_seek", "cluster_seek exploration")

    -- 11. phases: engage enters with has_target+not_in_combat, aoe_combat enters with in_combat
    local phases = tactic:get_phases()
    T.assert_eq(#phases, 2, "two phases")
    T.assert_eq(phases[1].name, "engage", "first phase is engage")
    T.assert_eq(phases[2].name, "aoe_combat", "second phase is aoe_combat")

    -- engage predicates
    T.assert_true(
        phases[1].enter_if({ has_target = true, in_combat = false }),
        "engage enters with target and no combat"
    )
    T.assert_eq(
        phases[1].enter_if({ has_target = true, in_combat = true }),
        false,
        "engage blocked when in combat"
    )
    T.assert_eq(phases[1].exit_if({ in_combat = true }), true, "engage exits on combat")

    -- aoe_combat predicates
    T.assert_true(
        phases[2].enter_if({ in_combat = true }),
        "aoe_combat enters in combat"
    )
    T.assert_true(
        phases[2].exit_if({ in_combat = false, target_alive = false }),
        "aoe_combat exits when target dead and out of combat"
    )

    -- phase ticks return FAILURE without deps
    T.assert_eq(phases[1].tick({}, {}), BT.Status.FAILURE, "engage FAILURE without pull_node")
    T.assert_eq(phases[2].tick({}, {}), BT.Status.FAILURE, "aoe_combat FAILURE without combat_node")

    -- reset does not error
    tactic:reset()

    return true
end }
