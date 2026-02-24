local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local DeathRecoveryService = require("services/DeathRecoveryService")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end
    local event_bus = { emit = function() end }

    local nav_calls = {}
    local nav_moving = false
    local mock_nav = {
        move_to = function(_, pos)
            nav_calls[#nav_calls + 1] = { action = "move_to", pos = pos }
            nav_moving = true
        end,
        is_moving = function() return nav_moving end,
        stop = function(_)
            nav_calls[#nav_calls + 1] = { action = "stop" }
            nav_moving = false
        end,
        soft_repath = function(_, pos, cb)
            nav_calls[#nav_calls + 1] = { action = "soft_repath", pos = pos }
            if cb then cb(true) end
        end,
    }

    -- Mock player object that the service's update() reads via _get_player()
    local mock_player = TU.mock_object({ dead = false, ghost = false })
    bb:set("player.object", mock_player)

    local dr_svc = DeathRecoveryService:new(event_bus, bb, {}, mock_nav)
    local tree = dr_svc:build()

    -- Test 1: FAILURE when alive
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", false)
    mock_player._dead = false
    mock_player._ghost = false
    assert(tree:tick() == S.FAILURE, "should fail when alive")

    -- Test 2: RUNNING when dead (waiting to release)
    bb:set("player.is_dead", true)
    bb:set("player.is_ghost", false)
    mock_player._dead = true
    mock_player._ghost = false
    assert(tree:tick() == S.RUNNING, "should be running when dead")

    -- Test 3: RUNNING when ghost (corpse run)
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", true)
    mock_player._dead = false
    mock_player._ghost = true
    bb:set("player.corpse_position", { x = 100, y = 200, z = 0 })
    bb:set("player.position", { x = 50, y = 200, z = 0 })
    now = now + 5
    assert(tree:tick() == S.RUNNING, "should be running during corpse run")

    -- Test 4: SUCCESS when resurrected
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", false)
    mock_player._dead = false
    mock_player._ghost = false
    tree:reset()
    assert(tree:tick() == S.FAILURE, "should fail once alive again")

    -- Test 5: Ghost with nil player.object (is_valid() returns false)
    -- Sensors sets bb death/ghost state via raw player even when is_valid fails.
    -- DeathRecoveryService must still activate using blackboard state.
    bb:set("player.object", nil)          -- is_valid() failed → no player object
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", true)       -- Sensors detected ghost via raw player
    bb:set("player.position", { x = 50, y = 200, z = 0 })
    env.core.game_ui.get_corpse_position = function()
        return { x = 100, y = 200, z = 0 }
    end
    nav_calls = {}
    tree:reset()
    now = now + 5
    assert(tree:tick() == S.RUNNING, "Test 5: should be RUNNING as ghost even with nil player.object")
    assert(dr_svc:is_active(), "Test 5: service should be active")
    assert(dr_svc:get_state() == "corpse_run", "Test 5: state should be corpse_run")

    -- Verify nav was issued to corpse position
    local found_nav = false
    for _, call in ipairs(nav_calls) do
        if call.action == "move_to" and call.pos and call.pos.x == 100 then
            found_nav = true
        end
    end
    assert(found_nav, "Test 5: should navigate to corpse even with nil player.object")

    -- Cleanup: restore player.object and core.game_ui
    env.core.game_ui.get_corpse_position = nil
    bb:set("player.object", mock_player)

    -- Test 6: Dead with nil player.object (release spirit)
    bb:set("player.object", nil)
    bb:set("player.is_dead", true)
    bb:set("player.is_ghost", false)
    local release_called = false
    env.core.input.release_spirit = function()
        release_called = true
        return true
    end
    tree:reset()
    dr_svc:reset()
    now = now + 1
    -- First tick activates the service (sets _started_at = now)
    assert(tree:tick() == S.RUNNING, "Test 6: should be RUNNING when dead with nil player.object")
    assert(dr_svc:get_state() == "dead", "Test 6: state should be dead")
    -- Advance past the release_delay (default 2.5s) and tick again
    now = now + 5
    tree:tick()
    assert(release_called, "Test 6: should attempt release_spirit")

    -- Cleanup
    bb:set("player.object", mock_player)
    env.core.input.release_spirit = nil

    env.restore()
    return true
end

return M
