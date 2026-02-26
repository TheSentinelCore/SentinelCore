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

    -- 8. No available tactics → nil
    local empty_selector = TacticalSelector:new(advisor)
    local none = empty_selector:select(ctx)
    T.assert_eq(none, nil, "nil when no tactics available")

    return true
end }
