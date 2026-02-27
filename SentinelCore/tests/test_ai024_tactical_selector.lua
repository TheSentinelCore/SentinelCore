local T = require("tests/TestUtil")

return { run = function()
    local TacticalSelector = require("ai/TacticalSelector")
    local Tactic = require("ai/Tactic")
    local BT = require("ai/BehaviorTree")

    -- Mock advisor (no bias)
    local advisor = {
        get_bias = function(self, name) return 1.0 end,
    }

    -- Two tactics: low utility and high utility
    local low_tactic = Tactic:new({
        name = "low",
        preconditions = function() return true end,
        utility = function() return 0.3 end,
        phases = {
            { name = "idle", enter_if = function() return true end,
              tick = function() return BT.Status.RUNNING end,
              exit_if = function() return false end },
        },
    })

    local high_tactic = Tactic:new({
        name = "high",
        preconditions = function() return true end,
        utility = function() return 0.8 end,
        phases = {
            { name = "burst", enter_if = function() return true end,
              tick = function() return BT.Status.RUNNING end,
              exit_if = function() return false end },
        },
    })

    local blocked_tactic = Tactic:new({
        name = "blocked",
        preconditions = function() return false end,  -- fails preconditions
        utility = function() return 1.0 end,
        phases = {},
    })

    -- 1. Construction
    local selector = TacticalSelector:new(advisor)
    T.assert_true(selector ~= nil, "selector created")

    -- 2. Register tactics
    selector:register(low_tactic)
    selector:register(high_tactic)
    selector:register(blocked_tactic)

    -- 3. Filter by preconditions
    local ctx = {}
    selector:refresh_available(ctx)
    T.assert_eq(selector:get_available_count(), 2, "blocked tactic filtered out")

    -- 4. Select highest utility
    local selected = selector:select(ctx)
    T.assert_eq(selected:get_name(), "high", "high utility tactic selected")

    -- 5. Active tactic persists
    T.assert_eq(selector:get_active():get_name(), "high", "active tactic is high")

    -- 6. Hysteresis: active tactic gets +0.1 bonus
    local close_low = Tactic:new({
        name = "close_low",
        preconditions = function() return true end,
        utility = function() return 0.75 end,
        phases = low_tactic:get_phases(),
    })
    local selector2 = TacticalSelector:new(advisor)
    selector2:register(close_low)
    selector2:register(high_tactic)
    selector2:refresh_available(ctx)
    selector2:select(ctx)  -- activates "high" (0.8 > 0.75)
    T.assert_eq(selector2:get_active():get_name(), "high", "high selected first")

    -- Now high scores 0.8 + 0.1 hysteresis = 0.9 vs close_low 0.75 → high stays
    local selected2 = selector2:select(ctx)
    T.assert_eq(selected2:get_name(), "high", "hysteresis keeps high active")

    -- 7. Tactic switch when new tactic scores much higher
    local dominant = Tactic:new({
        name = "dominant",
        preconditions = function() return true end,
        utility = function() return 0.99 end,
        phases = low_tactic:get_phases(),
    })
    selector2:register(dominant)
    selector2:refresh_available(ctx)
    local selected3 = selector2:select(ctx)
    T.assert_eq(selected3:get_name(), "dominant", "dominant tactic takes over")

    -- 8. No available tactics → nil and clears stale active
    local empty_selector = TacticalSelector:new(advisor)
    local none = empty_selector:select(ctx)
    T.assert_eq(none, nil, "nil when no tactics available")
    T.assert_eq(empty_selector:get_active(), nil, "active is nil when no tactics")

    -- 9. Advisor bias flips winner
    local bias_advisor = {
        get_bias = function(self, name)
            if name == "low" then return 2.0 end
            return 0.5
        end,
    }
    local bias_sel = TacticalSelector:new(bias_advisor)
    bias_sel:register(low_tactic)   -- raw 0.3 * 2.0 = 0.6
    bias_sel:register(high_tactic)  -- raw 0.8 * 0.5 = 0.4
    bias_sel:refresh_available(ctx)
    local biased = bias_sel:select(ctx)
    T.assert_eq(biased:get_name(), "low", "bias flips winner from high to low")

    -- 10. Advisor error falls back to raw scores
    local bad_advisor = {
        get_bias = function() error("advisor crash") end,
    }
    local err_sel = TacticalSelector:new(bad_advisor)
    err_sel:register(low_tactic)
    err_sel:register(high_tactic)
    err_sel:refresh_available(ctx)
    local err_selected = err_sel:select(ctx)
    T.assert_eq(err_selected:get_name(), "high", "advisor error falls back to raw scores")

    -- 11. refresh_available clears stale active
    local refresh_sel = TacticalSelector:new(advisor)
    local conditional_tactic = Tactic:new({
        name = "conditional",
        preconditions = function(c) return c.enabled == true end,
        utility = function() return 0.9 end,
        phases = low_tactic:get_phases(),
    })
    refresh_sel:register(conditional_tactic)
    refresh_sel:refresh_available({ enabled = true })
    refresh_sel:select({ enabled = true })
    T.assert_eq(refresh_sel:get_active():get_name(), "conditional", "conditional activated")
    refresh_sel:refresh_available({ enabled = false })
    T.assert_eq(refresh_sel:get_active(), nil, "active cleared when tactic fails preconditions")

    return true
end }
