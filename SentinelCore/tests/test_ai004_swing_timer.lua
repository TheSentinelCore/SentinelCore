local SwingTimer = require("ai/SwingTimer")

local M = {}

function M.run()
    local time = 0
    local timer = SwingTimer:new(function() return time end)

    -- Configure for a 3.5s weapon
    timer:set_weapon_speed(3.5)
    timer:set_haste_modifier(1.0)

    -- Record a swing at t=0
    timer:record_swing()
    assert(math.abs(timer:time_until_swing() - 3.5) < 0.01, "full swing remaining at t=0")

    -- At t=1.0, 2.5s remaining
    time = 1.0
    assert(math.abs(timer:time_until_swing() - 2.5) < 0.01, "2.5s remaining at t=1")

    -- Prep window: >0.8s remaining
    time = 0.5
    assert(timer:in_prep_window() == true, "in prep window at t=0.5")
    time = 3.0
    assert(timer:in_prep_window() == false, "not in prep at t=3.0 (only 0.5s left)")

    -- Twist window: <=0.4s remaining
    time = 3.0
    assert(timer:in_twist_window() == false, "not in twist at t=3.0 (0.5s left)")
    time = 3.2
    assert(timer:in_twist_window() == true, "in twist at t=3.2 (0.3s left)")

    -- Haste modifier: 1.4x haste -> 3.5/1.4 = 2.5s swing
    timer:set_haste_modifier(1.4)
    timer:record_swing()
    time = time + 2.0
    assert(math.abs(timer:time_until_swing() - 0.5) < 0.01, "hasted swing")

    -- Swing elapsed (negative remaining -> clamped to 0)
    time = time + 2.0
    assert(timer:time_until_swing() == 0, "clamped to 0 after swing window")

    return true
end

return M
