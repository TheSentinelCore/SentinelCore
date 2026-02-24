local SwingTimer = require("ai/SwingTimer")

local M = {}

function M.run()
    local time = 0
    local timer = SwingTimer:new(function() return time end)

    -- Configure for a 3.5s weapon
    timer:set_weapon_speed(3.5)
    timer:set_haste_modifier(1.0)

    -- Without auto_attack_helper and no player, fallback returns interval * 0.5
    assert(timer:time_until_swing() > 0, "fallback returns positive value")

    -- Mock auto_attack_helper by injecting via package.loaded
    local mock_next_swing = 3.5  -- next swing at t=3.5
    local mock_aa = {
        get_next_attack_core_time = function(self, unit)
            return mock_next_swing
        end,
    }
    package.loaded["common/utility/auto_attack_helper"] = mock_aa

    -- Force re-load of the aa helper by creating a fresh SwingTimer
    -- (the module-level lazy-load already cached nil, so we need a fresh module)
    package.loaded["ai/SwingTimer"] = nil
    local SwingTimer2 = require("ai/SwingTimer")
    local timer2 = SwingTimer2:new(function() return time end)
    timer2:set_weapon_speed(3.5)
    timer2:set_haste_modifier(1.0)

    -- Set a mock player object
    local mock_player = {}
    timer2:set_player(mock_player)

    -- At t=0, next swing at 3.5 -> 3.5s remaining
    time = 0
    assert(math.abs(timer2:time_until_swing() - 3.5) < 0.01, "full swing remaining at t=0")

    -- At t=1.0, 2.5s remaining
    time = 1.0
    assert(math.abs(timer2:time_until_swing() - 2.5) < 0.01, "2.5s remaining at t=1")

    -- Prep window: >0.8s remaining
    time = 0.5
    assert(timer2:in_prep_window() == true, "in prep window at t=0.5")
    time = 3.0
    assert(timer2:in_prep_window() == false, "not in prep at t=3.0 (only 0.5s left)")

    -- Twist window: <=0.4s remaining and >0
    time = 3.0
    assert(timer2:in_twist_window() == false, "not in twist at t=3.0 (0.5s left)")
    time = 3.2
    assert(timer2:in_twist_window() == true, "in twist at t=3.2 (0.3s left)")

    -- Swing elapsed (remaining -> clamped to 0)
    time = 4.0
    assert(timer2:time_until_swing() == 0, "clamped to 0 after swing window")

    -- Haste modifier: update next swing time to simulate 2.5s interval
    mock_next_swing = time + 2.5
    timer2:set_haste_modifier(1.4)
    time = time + 2.0
    assert(math.abs(timer2:time_until_swing() - 0.5) < 0.01, "hasted swing")

    -- Clean up mock
    package.loaded["common/utility/auto_attack_helper"] = nil
    package.loaded["ai/SwingTimer"] = nil

    return true
end

return M
