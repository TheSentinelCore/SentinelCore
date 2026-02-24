local TU = require("tests/TestUtil")
local BT = require("ai/BehaviorTree")
local S = BT.Status

local M = {}

function M.run()
    local env = TU.install_core_stub()
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local LootService = require("services/LootService")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)
    local now = 1000
    env.core.time = function() return now end

    local nav_calls = {}
    local nav_moving = false
    local mock_nav = {
        move_to = function(_, pos)
            nav_calls[#nav_calls + 1] = { action = "move_to", pos = pos }
            nav_moving = true
        end,
        is_moving = function() return nav_moving end,
        stop = function() nav_moving = false end,
        soft_repath = function(_, pos, cb)
            nav_calls[#nav_calls + 1] = { action = "soft_repath", pos = pos }
            if cb then cb(true) end
        end,
    }

    local loot_svc = LootService:new(eb, bb, {}, mock_nav)
    local tree = loot_svc:build()

    -- Test 1: FAILURE when no pending loot target
    bb:set("player.in_combat", false)
    bb:set("loot.pending_target", nil)
    assert(tree:tick() == S.FAILURE, "should fail with no loot target")

    -- Test 2: FAILURE when in combat with living attackers
    local player_obj = TU.mock_object({ name = "Player", position = { x = 0, y = 0, z = 0 } })
    bb:set("player.object", player_obj)
    local lootable = TU.mock_object({ position = { x = 10, y = 0, z = 0 } })
    bb:set("loot.pending_target", lootable)
    bb:set("player.in_combat", true)
    -- Mock a living attacker targeting the player
    local attacker = TU.mock_object({
        name = "Attacker", in_combat = true,
        position = { x = 5, y = 0, z = 0 }, target = player_obj
    })
    env.core.object_manager.get_visible_objects = function() return { attacker } end
    assert(tree:tick() == S.FAILURE, "should fail when in combat with living attackers")

    -- Test 2b: Soft combat gate — allow looting when combat flag lingers but no attackers
    env.core.object_manager.get_visible_objects = function() return {} end
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    tree:reset()
    loot_svc:reset()
    local soft_gate_status = tree:tick()
    assert(soft_gate_status == S.RUNNING, "should allow looting when combat flag lingers but no attackers")

    -- Test 3: RUNNING when lootable exists and not in combat (service starts)
    bb:set("player.in_combat", false)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    tree:reset()
    loot_svc:reset()
    local status = tree:tick()
    assert(status == S.RUNNING, "should be running when service starts looting")

    -- Test 4: When close enough, service starts and interacts
    bb:set("player.position", { x = 9, y = 0, z = 0 })
    tree:reset()
    loot_svc:reset()
    now = now + 0.1
    -- Set up core.input.loot_object and core.game_ui.get_loot_item_count
    env.core.input.loot_object = function() end
    env.core.game_ui = env.core.game_ui or {}
    env.core.game_ui.get_loot_item_count = function() return 0 end
    -- Tick multiple times to let the service progress through retries.
    -- Need 6 ticks: 3 for retry_limit, 1 for zero_loot_confirm, 1 more because
    -- update() sets state="completed" but the BT action already returned RUNNING
    -- that tick, so the final tick sees the completed state and clears pending_target.
    for _ = 1, 6 do
        now = now + 0.7
        tree:tick()
    end
    -- After enough retries with 0 loot items, service completes and clears pending_target
    assert(bb:get("loot.pending_target") == nil, "should clear pending_target after loot")

    -- Test 5: Timeout triggers FAILURE after 10s (BT Timeout wrapper)
    local far_lootable = TU.mock_object({ position = { x = 100, y = 0, z = 0 } })
    bb:set("loot.pending_target", far_lootable)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    tree:reset()
    loot_svc:reset()
    now = now + 0.1
    tree:tick()  -- start the timeout, RUNNING (far away)
    now = now + 12
    status = tree:tick()
    assert(status == S.FAILURE, "should fail after timeout")

    -- Test 6: Bug 1 — AoE corpse discovery when no pending target
    tree:reset()
    loot_svc:reset()
    bb:set("player.in_combat", false)
    bb:clear("loot.pending_target")
    bb:clear("combat.target")
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    local aoe_corpse = TU.mock_object({
        dead = true, has_loot = true, can_be_looted = true,
        position = { x = 5, y = 0, z = 0 },
    })
    env.core.object_manager.get_visible_objects = function() return { aoe_corpse } end
    now = now + 0.1
    local aoe_status = tree:tick()
    assert(aoe_status == S.RUNNING, "Bug 1: should start looting AoE-killed corpse")
    assert(bb:get("loot.pending_target") == aoe_corpse, "Bug 1: should set AoE corpse as pending")

    -- Test 7: Bug 2 — stop nav and face corpse before loot_object
    tree:reset()
    loot_svc:reset()
    nav_moving = true -- simulate active exploration nav
    local close_lootable = TU.mock_object({
        dead = true, has_loot = true, can_be_looted = true,
        position = { x = 3, y = 0, z = 0 },
    })
    bb:set("loot.pending_target", close_lootable)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.in_combat", false)
    env.core.object_manager.get_visible_objects = function() return { close_lootable } end
    local look_at_called = false
    local stop_called = false
    env.core.input.look_at = function() look_at_called = true end
    local orig_stop = mock_nav.stop
    mock_nav.stop = function() nav_moving = false; stop_called = true end
    now = now + 0.1
    tree:tick() -- condition passes, action starts looting (idle -> start)
    now = now + 0.1
    tree:tick() -- update: in range, first attempt fires with stop+face
    assert(stop_called, "Bug 2: should stop navigation before looting")
    assert(look_at_called, "Bug 2: should face corpse before looting")
    mock_nav.stop = orig_stop

    -- Test 8: Bug 3 — recover from stale looting state after BT preemption
    -- Reset loot_pending_since timer from prior tests
    tree:reset()
    loot_svc:reset()
    bb:clear("loot.pending_target")
    tree:tick() -- FAILURE tick resets internal pending timer
    tree:reset()
    local stale_target = TU.mock_object({
        dead = true, has_loot = true, can_be_looted = true,
        position = { x = 4, y = 0, z = 0 },
    })
    bb:set("loot.pending_target", stale_target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.in_combat", false)
    env.core.object_manager.get_visible_objects = function() return { stale_target } end
    now = now + 0.1
    tree:tick() -- starts looting
    assert(loot_svc:is_active(), "Bug 3: service should be active after start")
    -- Simulate BT preemption (reset BT node but NOT the service)
    tree:reset()
    assert(loot_svc:is_active(), "Bug 3: service should still be active after BT reset")
    -- New pending target after combat (target-change triggers stale detection)
    now = now + 1.0
    local new_stale_target = TU.mock_object({
        dead = true, has_loot = true, can_be_looted = true,
        position = { x = 3, y = 0, z = 0 },
    })
    bb:set("loot.pending_target", new_stale_target)
    env.core.object_manager.get_visible_objects = function() return { new_stale_target } end
    local stale_status = tree:tick()
    assert(stale_status == S.RUNNING, "Bug 3: should start fresh loot cycle after stale recovery")
    assert(loot_svc:is_active(), "Bug 3: service should be actively looting new target")

    -- Test 9: Loot blacklist — corpse yielding 0 items gets blacklisted
    tree:reset()
    loot_svc:reset()
    bb:clear("loot.pending_target")
    bb:set("player.in_combat", false)
    bb:set("player.position", { x = 0, y = 0, z = 0 })

    local empty_corpse = TU.mock_object({
        dead = true, has_loot = true, can_be_looted = true,
        position = { x = 3, y = 0, z = 0 },
    })
    bb:set("loot.pending_target", empty_corpse)
    env.core.object_manager.get_visible_objects = function() return { empty_corpse } end
    env.core.input.loot_object = function() end
    env.core.game_ui.get_loot_item_count = function() return 0 end

    -- Run through the full loot cycle (start -> retries -> 0-item completion)
    -- 3 attempts (max_retries=2) × ~2 ticks each + 1 start + 1 completion = ~9 ticks
    now = now + 0.1
    tree:tick() -- start looting
    for _ = 1, 9 do
        now = now + 0.7
        tree:tick()
    end
    -- Corpse should be cleared from pending after 0-item completion
    assert(bb:get("loot.pending_target") == nil, "Blacklist: should clear pending after 0-item loot")

    -- Now put the same corpse back as pending — blacklist should reject it
    bb:set("loot.pending_target", empty_corpse)
    env.core.object_manager.get_visible_objects = function() return { empty_corpse } end
    tree:reset()
    loot_svc:reset()
    now = now + 0.1
    local bl_status = tree:tick()
    assert(bl_status == S.FAILURE, "Blacklist: should reject blacklisted corpse in condition")
    assert(bb:get("loot.pending_target") == nil, "Blacklist: should clear blacklisted pending target")

    -- Verify _scan_loot_queue also filters blacklisted corpses
    local fresh_corpse = TU.mock_object({
        dead = true, has_loot = true, can_be_looted = true,
        position = { x = 5, y = 0, z = 0 },
    })
    env.core.object_manager.get_visible_objects = function() return { empty_corpse, fresh_corpse } end
    tree:reset()
    loot_svc:reset()
    bb:clear("loot.pending_target")
    bb:set("player.in_combat", false)
    now = now + 0.1
    local scan_status = tree:tick()
    assert(scan_status == S.RUNNING, "Blacklist: should pick non-blacklisted corpse from scan")
    assert(bb:get("loot.pending_target") == fresh_corpse, "Blacklist: scan should skip blacklisted, pick fresh")

    env.restore()
    return true
end

return M
