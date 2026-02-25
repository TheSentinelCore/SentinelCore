-- Regression tests for PullService navigation guard.
--
-- PullService checks navigation:is_moving() before issuing nav commands.
-- When NavClient is unavailable, is_moving() returns nil.  Without the nil
-- guard, the false-branch executes and issues a spurious move_to() call that
-- overwrites stale last_dest with nil on callback failure.
--
-- Specific cases:
-- (1) is_moving() == nil → skip nav entirely, still return RUNNING
-- (2) Transitioning from nil (unavailable) to false (idle) → nav starts normally
-- (3) Target position updates while moving → soft_repath fires correctly
-- (4) is_moving() == nil while in ranged-pull range → no nav but no crash

local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local PullService = require("services/PullService")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    -- -----------------------------------------------------------------------
    -- Test 1: is_moving() returns nil → no nav call, RUNNING returned
    -- -----------------------------------------------------------------------
    local nav_calls = {}
    local nav_moving_val = nil  -- nil simulates NavClient unavailable
    local mock_nav = {
        move_to = function(_, pos, cb)
            nav_calls[#nav_calls + 1] = { action = "move_to", pos = pos }
            nav_moving_val = true
            if cb then cb(true) end
        end,
        is_moving = function() return nav_moving_val end,
        stop = function() nav_moving_val = false end,
        soft_repath = function(_, pos, cb)
            nav_calls[#nav_calls + 1] = { action = "soft_repath", pos = pos }
            if cb then cb(true) end
        end,
    }

    local target_far = TU.mock_object({
        health = 500, max_health = 1000,
        position = { x = 50, y = 0, z = 0 },
    })
    bb:set("combat.target", target_far)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.in_combat", false)

    local pull = PullService.build(bb, mock_nav)
    pull:reset()
    nav_calls = {}

    local result = pull:tick()
    assert(result == S.RUNNING,
        "Test 1: expected RUNNING when NavClient unavailable (is_moving=nil)")
    assert(#nav_calls == 0,
        "Test 1: expected no nav calls when is_moving returns nil, got " .. #nav_calls)

    -- -----------------------------------------------------------------------
    -- Test 2: is_moving() transitions nil → false → nav starts normally
    -- -----------------------------------------------------------------------
    nav_moving_val = false   -- NavClient now available and idle
    nav_calls = {}
    now = now + 0.1
    pull:reset()

    local result2 = pull:tick()
    assert(result2 == S.RUNNING, "Test 2: expected RUNNING when nav starts")
    assert(#nav_calls == 1 and nav_calls[1].action == "move_to",
        "Test 2: expected a move_to call when NavClient becomes available, got " ..
        tostring(#nav_calls) .. " calls")

    -- -----------------------------------------------------------------------
    -- Test 3: target moves while nav is in flight → soft_repath fires
    -- -----------------------------------------------------------------------
    nav_moving_val = true   -- nav is now in flight
    nav_calls = {}
    now = now + 0.1
    -- Move target >1yd to trigger soft_repath
    target_far._position = { x = 52, y = 0, z = 0 }

    local result3 = pull:tick()
    assert(result3 == S.RUNNING, "Test 3: expected RUNNING during chase")
    assert(#nav_calls == 1 and nav_calls[1].action == "soft_repath",
        "Test 3: expected soft_repath when target moves, got " ..
        tostring(#nav_calls) .. " calls of type " ..
        tostring(nav_calls[1] and nav_calls[1].action))

    -- -----------------------------------------------------------------------
    -- Test 4: is_moving() returns nil while in ranged pull range → no crash
    -- Player is within 10yd but outside 5yd (ranged pull zone).
    -- With nil nav, we expect RUNNING without any nav call.
    -- -----------------------------------------------------------------------
    nav_moving_val = nil   -- NavClient unavailable again
    nav_calls = {}
    bb:set("player.position", { x = 45, y = 0, z = 0 })   -- 7yd from target at x=52
    -- Reset pull so last_dest is cleared
    pull:reset()
    now = now + 0.1

    -- Provide spell_book so ranged-pull Judgement path doesn't error
    env.core.spell_book = env.core.spell_book or {}
    env.core.spell_book.get_spell_cooldown = function(_, id) return 100 end   -- on CD
    env.core.spell_book.is_spell_learned = function(_, id) return false end

    local result4 = pull:tick()
    assert(result4 == S.RUNNING,
        "Test 4: expected RUNNING in ranged-pull zone with nil nav, got " ..
        tostring(result4))
    -- No move_to should have been issued (is_moving == nil path taken)
    local move_to_count = 0
    for _, c in ipairs(nav_calls) do
        if c.action == "move_to" then move_to_count = move_to_count + 1 end
    end
    assert(move_to_count == 0,
        "Test 4: expected no move_to with nil nav, got " .. move_to_count)

    env.restore()
    return true
end

return M
