-- Regression test for P3 bug: rest_start_time closure persists through combat.
--
-- When CombatInterruptService preempts rest, it clears "combat.was_resting" on the
-- blackboard but cannot reach the eat_drink closure's rest_start_time variable.
-- If the timeout (60s) is checked against the stale start time, the NEXT rest session
-- will timeout prematurely before the player has recovered.
--
-- Fix: eat_drink detects the mismatch (rest_start_time != nil AND was_resting == false)
-- and resets rest_start_time to "now" before resuming.

local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local RestService = require("services/RestService")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    local rest = RestService.build(bb, nil)

    -- Shared low-HP state
    bb:set("player.health", 400)
    bb:set("player.max_health", 1000)
    bb:set("player.in_combat", false)

    -- Test 1: Start a rest session. Timer should begin at now=1000.
    rest:reset()
    local result = rest:tick()
    assert(result == S.RUNNING, "Test 1: expected RUNNING at low HP")
    assert(bb:get("combat.was_resting") == true, "Test 1: was_resting should be set")

    -- Test 2: Simulate CombatInterruptService externally clearing was_resting
    -- WITHOUT the ReactiveSelector ever giving the gate condition a chance to run.
    -- (In production the gate never fires during combat because CombatService holds
    -- the ReactiveSelector at a higher priority slot.)
    bb:set("combat.was_resting", false)

    -- Advance time by 70 seconds — beyond the 60s rest timeout.
    -- If rest_start_time is NOT reset, the next tick would return S.FAILURE (timeout).
    -- If rest_start_time IS reset (the fix), the next tick should return S.RUNNING.
    now = now + 70

    -- Player is still out of combat with low HP.
    local result2 = rest:tick()
    assert(result2 == S.RUNNING,
        "Test 2: rest should start fresh after interrupt (not time out from old session)")
    assert(bb:get("combat.was_resting") == true,
        "Test 2: was_resting should be re-armed after fresh session start")

    -- Test 3: Verify the fresh session progresses normally.
    -- After another non-fatal advance (< 60s), it should still be RUNNING.
    now = now + 10
    local result3 = rest:tick()
    assert(result3 == S.RUNNING, "Test 3: fresh rest session should still be RUNNING at +10s")

    -- Test 4: Normal recovery path still works after an interrupted session.
    bb:set("player.health", 950)   -- 95% HP — above 90% exit threshold
    now = now + 0.1
    local result4 = rest:tick()
    assert(result4 == S.FAILURE, "Test 4: rest gate should fail when fully recovered")
    assert(bb:get("combat.was_resting") == false,
        "Test 4: was_resting should be cleared on clean exit")

    env.restore()
    return true
end

return M
