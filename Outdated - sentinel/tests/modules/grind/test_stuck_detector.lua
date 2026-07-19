local StuckDetector = require("modules/grind/stuck_detector")
local T = require("tests/test_util")

local M = {}

function M.run()
    -- Not stuck initially
    local det = StuckDetector:new()
    T.assert_false(det:is_stuck(), "not stuck initially")
    T.assert_equal(det:get_attempt_count(), 0, "zero attempts initially")
    T.assert_false(det:should_give_up(), "should not give up initially")

    -- Movement resets stuck counter
    det = StuckDetector:new()
    det:sample(0, { x = 0, y = 0, z = 0 })
    det:sample(2000, { x = 0.5, y = 0, z = 0 })  -- low movement
    det:sample(4000, { x = 0.8, y = 0, z = 0 })  -- low movement
    det:sample(6000, { x = 10, y = 0, z = 0 })    -- real movement, resets counter
    det:sample(8000, { x = 10.3, y = 0, z = 0 })  -- low movement (count = 1)
    T.assert_false(det:is_stuck(), "movement resets stuck counter")

    -- No movement for 3 samples triggers stuck
    det = StuckDetector:new()
    det:sample(0, { x = 5, y = 5, z = 5 })
    det:sample(2000, { x = 5, y = 5, z = 5 })   -- low movement (1)
    det:sample(4000, { x = 5.1, y = 5, z = 5 })  -- low movement (2)
    det:sample(6000, { x = 5, y = 5, z = 5 })     -- low movement (3)
    T.assert_true(det:is_stuck(), "3 consecutive low-movement samples triggers stuck")

    -- Samples within interval are ignored
    det = StuckDetector:new()
    det:sample(0, { x = 0, y = 0, z = 0 })
    det:sample(500, { x = 0, y = 0, z = 0 })   -- ignored (too soon)
    det:sample(1000, { x = 0, y = 0, z = 0 })  -- ignored (too soon)
    T.assert_false(det:is_stuck(), "samples within interval are ignored")

    -- reset() clears stuck state
    det = StuckDetector:new()
    det:sample(0, { x = 0, y = 0, z = 0 })
    det:sample(2000, { x = 0, y = 0, z = 0 })
    det:sample(4000, { x = 0, y = 0, z = 0 })
    det:sample(6000, { x = 0, y = 0, z = 0 })
    T.assert_true(det:is_stuck(), "stuck before reset")
    det:reset()
    T.assert_false(det:is_stuck(), "not stuck after reset")

    -- Attempt counter increments
    det = StuckDetector:new()
    T.assert_equal(det:get_attempt_count(), 0, "0 attempts at start")
    det:record_attempt()
    T.assert_equal(det:get_attempt_count(), 1, "1 attempt after record")
    det:record_attempt()
    T.assert_equal(det:get_attempt_count(), 2, "2 attempts after second record")
    T.assert_false(det:should_give_up(), "should not give up at 2 attempts")

    -- should_give_up after 3 attempts
    det:record_attempt()
    T.assert_equal(det:get_attempt_count(), 3, "3 attempts")
    T.assert_true(det:should_give_up(), "should give up at 3 attempts")

    -- reset() does NOT clear attempt_count
    det:reset()
    T.assert_equal(det:get_attempt_count(), 3, "reset does not clear attempt count")
    T.assert_true(det:should_give_up(), "should_give_up still true after reset")
end

return M
