local M = {}

function M.run()
    math.randomseed(42)

    local PathEntropy = require("ai/PathEntropy")
    local SessionBehavior = require("ai/SessionBehavior")

    -- PathEntropy tests
    local pe = PathEntropy:new()

    -- Test 1: jitter_position returns nearby position
    local pos = { x = 100, y = 200, z = 50 }
    local jittered = pe:jitter_position(pos)
    assert(jittered.x ~= nil, "should have x")
    assert(jittered.z == 50, "z should be preserved")
    local dx = jittered.x - pos.x
    local dy = jittered.y - pos.y
    local dist = math.sqrt(dx * dx + dy * dy)
    assert(dist <= 3.0, "jitter should be within radius")

    -- Test 2: approach angle jitter rotates vector
    local rx, ry = pe:jitter_approach_angle(1, 0)
    assert(rx ~= nil and ry ~= nil, "should return rotated vector")
    local len = math.sqrt(rx * rx + ry * ry)
    assert(math.abs(len - 1.0) < 0.01, "should preserve magnitude: " .. tostring(len))

    -- Test 3: micro pause duration in range
    local dur = pe:get_micro_pause_duration()
    assert(dur >= 0.5 and dur <= 1.5, "pause duration should be in range: " .. tostring(dur))

    -- SessionBehavior tests
    local sb = SessionBehavior:new({
        idle_check_interval = 10,
        idle_pause_chance = 1.0,  -- always pause for testing
        fatigue_ramp_minutes = 60,
    })

    -- Test 4: fatigue starts at 1.0
    sb:start(1000)
    local f = sb:get_fatigue_factor(1000)
    assert(math.abs(f - 1.0) < 0.01, "fatigue should start at 1.0: " .. tostring(f))

    -- Test 5: fatigue increases over time
    local f30 = sb:get_fatigue_factor(1000 + 30 * 60)  -- 30 min
    assert(f30 > 1.0, "fatigue should increase: " .. tostring(f30))
    assert(f30 <= 1.5, "fatigue should be capped: " .. tostring(f30))

    -- Test 6: idle pause triggers
    local paused = sb:check_idle_pause(1000 + 15)
    assert(paused == true, "should trigger idle pause (chance=1.0)")

    -- Test 7: pause continues
    local still_paused = sb:check_idle_pause(1000 + 16)
    assert(still_paused == true, "should still be paused")

    return true
end

return M
