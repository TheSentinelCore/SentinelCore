local T = require("tests/test_util")

local M = {}

function M.run()
    -- Mock core global for time-based tests
    local mock_time = 0
    core = { time = function() return mock_time end }

    local Humanization = require("shared/humanization")

    -- 1. random_between respects bounds
    do
        local h = Humanization.new()
        for _ = 1, 200 do
            local v = h:random_between(5, 10)
            T.assert_true(v >= 5, "random_between result below min: " .. tostring(v))
            T.assert_true(v <= 10, "random_between result above max: " .. tostring(v))
        end
    end

    -- 2. random_between with equal values
    do
        local h = Humanization.new()
        local v = h:random_between(3, 3)
        T.assert_equal(v, 3, "random_between with equal values should return that value")
    end

    -- 3. jitter_point offsets x/y within range, z unchanged
    do
        local h = Humanization.new()
        for _ = 1, 100 do
            local result = h:jitter_point({ x = 100, y = 200, z = 300 }, 2.0)
            T.assert_not_nil(result, "jitter_point should return a table")
            T.assert_true(result.x >= 98, "jittered x below range: " .. tostring(result.x))
            T.assert_true(result.x <= 102, "jittered x above range: " .. tostring(result.x))
            T.assert_true(result.y >= 198, "jittered y below range: " .. tostring(result.y))
            T.assert_true(result.y <= 202, "jittered y above range: " .. tostring(result.y))
            T.assert_equal(result.z, 300, "jitter_point z should be unchanged")
        end
    end

    -- 4. jitter_point with zero amount returns exact copy
    do
        local h = Humanization.new()
        local result = h:jitter_point({ x = 10, y = 20, z = 30 }, 0)
        T.assert_not_nil(result, "jitter_point(0) should return a table")
        T.assert_equal(result.x, 10, "jitter_point(0) x should be exact")
        T.assert_equal(result.y, 20, "jitter_point(0) y should be exact")
        T.assert_equal(result.z, 30, "jitter_point(0) z should be exact")
    end

    -- 5. jitter_point with nil input returns nil
    do
        local h = Humanization.new()
        local result = h:jitter_point(nil, 2)
        T.assert_equal(result, nil, "jitter_point(nil) should return nil")
    end

    -- 6. is_ready returns false before deadline
    do
        mock_time = 0
        local h = Humanization.new()
        -- First call schedules deadline at now_s() + random_between(1.0, 2.0) => between 1.0 and 2.0
        local ready1 = h:is_ready("test_key", 1.0, 2.0)
        -- time is 0, deadline is >= 1.0, so should be false
        T.assert_false(ready1, "is_ready should return false before deadline")
        -- Call again immediately, still time=0
        local ready2 = h:is_ready("test_key", 1.0, 2.0)
        T.assert_false(ready2, "is_ready should still be false at time 0")
    end

    -- 7. is_ready returns true after deadline
    do
        mock_time = 0
        local h = Humanization.new()
        -- Schedule deadline (will be between 1.0 and 2.0)
        h:is_ready("test_after", 1.0, 2.0)
        -- Advance time past maximum possible deadline
        mock_time = 3.0
        local ready = h:is_ready("test_after", 1.0, 2.0)
        T.assert_true(ready, "is_ready should return true after deadline has passed")
    end
end

return M
