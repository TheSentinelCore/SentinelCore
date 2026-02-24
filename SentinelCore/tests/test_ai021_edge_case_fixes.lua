local RC = require("ai/ResponseCurves")
local UE = require("ai/UtilityEvaluator")
local SwingTimer = require("ai/SwingTimer")

local M = {}

function M.run()
    -- Fix 5: Bell curve with width=0 should not produce NaN
    local score_bell = RC.evaluate("bell", 0.5, { center = 0.5, width = 0 })
    assert(score_bell == score_bell, "Fix5: bell width=0 should not be NaN")
    assert(score_bell > 0.99, "Fix5: bell at center with clamped width should be ~1.0: " .. tostring(score_bell))

    local score_bell_neg = RC.evaluate("bell", 0.5, { center = 0.5, width = -5 })
    assert(score_bell_neg == score_bell_neg, "Fix5: bell negative width should not be NaN")

    -- Fix 1: NaN guard in UtilityEvaluator
    -- Register an action whose curve would produce NaN without guards
    -- (bell width gets clamped by Fix 5, so force NaN through a custom test)
    local eval = UE:new()
    eval:register({
        id = "nan_action",
        weight = 2.0,
        considerations = {
            { input = "x", curve = "bell", params = { center = 0.5, width = 0 } },
        },
    })
    local result = eval:evaluate({ x = 0.5 })
    assert(result ~= nil, "Fix1: should return result, not nil")
    assert(result.utility == result.utility, "Fix1: utility must not be NaN")
    assert(result.utility > 0, "Fix1: should have positive utility")

    -- Fix 2: Zero haste modifier clamped to 0.01
    local now = 1000
    local st = SwingTimer:new(function() return now end)
    st:set_weapon_speed(3.5)
    st:set_haste_modifier(0)
    local interval = st:get_swing_interval()
    assert(interval == 3.5 / 0.01, "Fix2: haste=0 clamped to 0.01, interval=" .. tostring(interval))
    assert(interval < 1e6, "Fix2: interval must not be infinity")

    st:set_haste_modifier(-1)
    interval = st:get_swing_interval()
    assert(interval == 3.5 / 0.01, "Fix2: negative haste clamped to 0.01")

    -- Fix 2 continued: normal values unaffected
    st:set_haste_modifier(1.0)
    assert(st:get_swing_interval() == 3.5, "Fix2: normal haste=1.0 unaffected")

    st:set_haste_modifier(1.5)
    local expected = 3.5 / 1.5
    local actual = st:get_swing_interval()
    assert(math.abs(actual - expected) < 0.001, "Fix2: haste=1.5 works: " .. tostring(actual))

    return true
end

return M
