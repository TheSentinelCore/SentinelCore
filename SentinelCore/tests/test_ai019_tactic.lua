local T = require("tests/TestUtil")

return { run = function()
    local Tactic = require("ai/Tactic")

    -- 1. Can create a minimal tactic
    local t = Tactic:new({
        name = "test_tactic",
        preconditions = function() return true end,
        utility = function() return 0.5 end,
        phases = {
            {
                name = "engage",
                enter_if = function() return true end,
                tick = function() return "SUCCESS" end,
                exit_if = function() return false end,
            },
        },
    })
    T.assert_true(t ~= nil, "tactic created")
    T.assert_eq(t:get_name(), "test_tactic", "name accessor")

    -- 2. preconditions delegation
    T.assert_true(t:check_preconditions({}), "preconditions pass")

    -- 3. utility delegation
    T.assert_eq(t:score_utility({}, nil), 0.5, "utility returns 0.5")

    -- 4. phases accessible
    local phases = t:get_phases()
    T.assert_eq(#phases, 1, "one phase")
    T.assert_eq(phases[1].name, "engage", "phase name")

    -- 5. config overrides default to nil (shared services use defaults)
    T.assert_eq(t:get_rest_config(), nil, "no rest config override")
    T.assert_eq(t:get_target_config(), nil, "no target config override")
    T.assert_eq(t:get_explore_config(), nil, "no explore config override")

    -- 6. Tactic with config overrides
    local t2 = Tactic:new({
        name = "custom",
        preconditions = function() return false end,
        utility = function() return 0.0 end,
        phases = {},
        rest_config = { drink_below = 0.95 },
        target_config = { prefer_clusters = true },
        explore_config = { mode = "cluster_seek" },
    })
    T.assert_eq(t2:get_rest_config().drink_below, 0.95, "rest config override")
    T.assert_eq(t2:get_target_config().prefer_clusters, true, "target config override")
    T.assert_eq(t2:get_explore_config().mode, "cluster_seek", "explore config override")

    -- 7. reset calls on_reset callback
    local reset_called = false
    local reset_self_ref = nil
    local t3 = Tactic:new({
        name = "resettable",
        on_reset = function(self_arg)
            reset_called = true
            reset_self_ref = self_arg
        end,
    })
    t3:reset()
    T.assert_true(reset_called, "on_reset callback was invoked")
    T.assert_true(reset_self_ref == t3, "on_reset receives self")

    -- 8. reset without on_reset does not error
    t:reset()

    -- 9. erroring precondition returns false (pcall protection)
    local t_err = Tactic:new({
        name = "erroring",
        preconditions = function() error("boom") end,
        utility = function() error("kaboom") end,
        on_reset = function() error("reset_boom") end,
    })
    T.assert_eq(t_err:check_preconditions({}), false, "erroring precondition returns false")

    -- 10. erroring utility returns 0 (pcall protection)
    T.assert_eq(t_err:score_utility({}, nil), 0, "erroring utility returns 0")

    -- 11. erroring on_reset does not propagate
    t_err:reset()  -- should not crash

    -- 12. utility > 1 clamped to 1
    local t_high = Tactic:new({
        name = "high",
        utility = function() return 5.0 end,
    })
    T.assert_eq(t_high:score_utility({}, nil), 1, "utility clamped to 1")

    -- 13. negative utility clamped to 0
    local t_neg = Tactic:new({
        name = "negative",
        utility = function() return -3.0 end,
    })
    T.assert_eq(t_neg:score_utility({}, nil), 0, "negative utility clamped to 0")

    return true
end }
