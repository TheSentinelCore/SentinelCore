-- Regression tests for FleeService centroid direction logic.
--
-- test_ai013 already covers the fallback path (flee from combat.target).
-- This test covers the PRIMARY path: flee direction computed as the inverse
-- of the centroid of ALL visible enemy objects, not just the primary target.
--
-- Specifically verifies:
-- (a) Multi-threat centroid: flee direction is the inverse of the average
--     threat position relative to the player.
-- (b) Symmetric threats cancel out the axis they share, leaving a clean flee
--     vector on the perpendicular axis.
-- (c) Orthogonal pair: two threats east & north → flee southwest.

local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local FleeService = require("services/FleeService")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    local player_pos = { x = 0, y = 0, z = 5 }
    local mock_player = TU.mock_object({ position = player_pos })

    -- Nav stub that records where move_to was called
    local last_flee_pos = nil
    local mock_nav = {
        move_to = function(_, pos, cb)
            last_flee_pos = pos
            if cb then cb(true) end
        end,
        is_moving = function() return false end,
        stop = function() end,
    }

    -- Helper: make a threat object visible to get_visible_objects
    local function make_threat(px, py)
        local obj = TU.mock_object({ position = { x = px, y = py, z = 5 } })
        -- Override can_attack to accept any argument (TestUtil default returns true)
        obj.can_attack = function(_, _) return true end
        return obj
    end

    -- -----------------------------------------------------------------------
    -- Test 1: two threats due east → flee due west (negative x)
    -- Threats at (+10, 0) and (+20, 0) → centroid (15, 0) → flee direction (-1, 0)
    -- Expected flee_pos.x << 0, flee_pos.y ≈ 0
    -- -----------------------------------------------------------------------
    local t1a = make_threat(10, 0)
    local t1b = make_threat(20, 0)
    env.core.object_manager.get_visible_objects = function() return { t1a, t1b } end

    local flee = FleeService.build(bb, mock_nav)
    bb:set("player.object", mock_player)
    bb:set("player.position", player_pos)
    bb:set("player.in_combat", true)
    bb:set("player.health", 100)
    bb:set("player.max_health", 1000)
    bb:set("combat.enemy_count", 2)
    last_flee_pos = nil
    flee:reset()

    local result = flee:tick()
    assert(result == S.RUNNING, "Test 1: expected RUNNING when should flee")
    assert(last_flee_pos ~= nil, "Test 1: expected move_to to be called")
    assert(last_flee_pos.x < 0,
        "Test 1: flee x should be negative (away from east threats), got " ..
        tostring(last_flee_pos and last_flee_pos.x))
    -- y should be close to 0 (within 1 unit at 30-unit flee distance)
    assert(math.abs(last_flee_pos.y) < 2,
        "Test 1: flee y should be near 0 for due-east threats, got " ..
        tostring(last_flee_pos and last_flee_pos.y))

    -- -----------------------------------------------------------------------
    -- Test 2: threats east and north → flee southwest
    -- Threat at (+10, 0) and (0, +10) → centroid (5, 5) → flee direction (-1, -1) norm
    -- Expected flee_pos.x < 0 and flee_pos.y < 0
    -- -----------------------------------------------------------------------
    local t2a = make_threat(10, 0)
    local t2b = make_threat(0, 10)
    env.core.object_manager.get_visible_objects = function() return { t2a, t2b } end

    local flee2 = FleeService.build(bb, mock_nav)
    bb:set("player.in_combat", true)
    bb:set("player.health", 100)
    bb:set("combat.enemy_count", 2)
    last_flee_pos = nil
    flee2:reset()

    local result2 = flee2:tick()
    assert(result2 == S.RUNNING, "Test 2: expected RUNNING")
    assert(last_flee_pos ~= nil, "Test 2: expected move_to to be called")
    assert(last_flee_pos.x < 0,
        "Test 2: flee x should be negative (west), got " .. tostring(last_flee_pos and last_flee_pos.x))
    assert(last_flee_pos.y < 0,
        "Test 2: flee y should be negative (south), got " .. tostring(last_flee_pos and last_flee_pos.y))

    -- -----------------------------------------------------------------------
    -- Test 3: symmetric threats north and south → flee due west (x axis)
    -- Player at (0,0); threats at (10, 5) and (10, -5) → centroid (10, 0)
    -- Flee direction is purely west (negative x), y ≈ 0
    -- -----------------------------------------------------------------------
    local t3a = make_threat(10, 5)
    local t3b = make_threat(10, -5)
    env.core.object_manager.get_visible_objects = function() return { t3a, t3b } end

    local flee3 = FleeService.build(bb, mock_nav)
    bb:set("player.in_combat", true)
    bb:set("player.health", 100)
    bb:set("combat.enemy_count", 2)
    last_flee_pos = nil
    flee3:reset()

    local result3 = flee3:tick()
    assert(result3 == S.RUNNING, "Test 3: expected RUNNING")
    assert(last_flee_pos ~= nil, "Test 3: expected move_to to be called")
    assert(last_flee_pos.x < 0,
        "Test 3: flee x should be negative (west), got " .. tostring(last_flee_pos and last_flee_pos.x))
    assert(math.abs(last_flee_pos.y) < 2,
        "Test 3: y symmetry: flee y should be near 0, got " ..
        tostring(last_flee_pos and last_flee_pos.y))

    env.restore()
    return true
end

return M
