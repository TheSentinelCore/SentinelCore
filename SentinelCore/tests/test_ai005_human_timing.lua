local HumanTiming = require("ai/HumanTiming")

local M = {}

function M.run()
    -- Use a fixed seed for deterministic tests
    math.randomseed(42)

    local ht = HumanTiming:new()

    -- Test 1: delays are in reasonable range
    local delays = {}
    for i = 1, 100 do
        delays[i] = ht:get_action_delay("rotation")
    end

    local min_d, max_d = math.huge, -math.huge
    for i = 1, 100 do
        if delays[i] < min_d then min_d = delays[i] end
        if delays[i] > max_d then max_d = delays[i] end
    end

    assert(min_d >= 0.030, "min delay should be at least 30ms: " .. min_d)
    assert(max_d < 1.0, "max delay should be under 1s: " .. max_d)

    -- Test 2: interrupt delays are longer than rotation delays (on average)
    local int_sum, rot_sum = 0, 0
    for i = 1, 200 do
        int_sum = int_sum + ht:get_action_delay("interrupt")
        rot_sum = rot_sum + ht:get_action_delay("rotation")
    end
    assert(int_sum / 200 > rot_sum / 200, "interrupts should be slower on average")

    -- Test 3: fatigue increases delay
    ht:set_fatigue(0.30)  -- 30% slower
    local fatigued_sum = 0
    for i = 1, 200 do
        fatigued_sum = fatigued_sum + ht:get_action_delay("rotation")
    end
    assert(fatigued_sum / 200 > rot_sum / 200, "fatigue should increase delays")

    -- Test 4: should_fumble returns boolean
    local fumbles = 0
    for i = 1, 1000 do
        if ht:should_fumble(0.05) then fumbles = fumbles + 1 end
    end
    -- With 5% rate, expect ~50 fumbles (allow wide tolerance)
    assert(fumbles > 10 and fumbles < 150, "fumble rate should be near 5%: " .. fumbles)

    -- Test 5: stochastic_select occasionally picks non-best
    local picks = { best = 0, other = 0 }
    for i = 1, 1000 do
        local candidates = {
            { id = "best", utility = 1.0 },
            { id = "second", utility = 0.95 },
            { id = "third", utility = 0.80 },
        }
        local pick = ht:stochastic_select(candidates, 0.05)
        if pick.id == "best" then picks.best = picks.best + 1
        else picks.other = picks.other + 1 end
    end
    assert(picks.other > 10, "stochastic should sometimes pick non-best: " .. picks.other)
    assert(picks.best > 700, "best should still win most of the time: " .. picks.best)

    return true
end

return M
