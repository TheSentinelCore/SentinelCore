-- SentinelCore/tests/test_ai006_combat_context.lua
local TU = require("tests/TestUtil")
local CombatContext = require("ai/CombatContext")

local M = {}

function M.run()
    local env = TU.install_core_stub()

    local Blackboard = require("core/Blackboard")
    local bb = Blackboard:new()

    -- Populate blackboard like Sensors would
    local player = TU.mock_object({
        health = 500, max_health = 1000,
        mana = 300, max_mana = 1000,
        dead = false, ghost = false,
        in_combat = true, casting = false,
        position = { x = 100, y = 200, z = 0 },
    })
    local target = TU.mock_object({
        health = 200, max_health = 800,
        dead = false,
        in_combat = true, casting = true,
        position = { x = 105, y = 200, z = 0 },
    })

    bb:set("player.object", player)
    bb:set("player.health", 500)
    bb:set("player.max_health", 1000)
    bb:set("player.in_combat", true)
    bb:set("player.is_casting", false)
    bb:set("player.position", { x = 100, y = 200, z = 0 })
    bb:set("combat.target", target)
    bb:set("combat.enemy_count", 2)

    local ctx = CombatContext.build(bb)

    -- Verify key fields
    assert(ctx.player_health_pct == 0.5, "health_pct: " .. tostring(ctx.player_health_pct))
    assert(ctx.player_mana_pct == 0.3, "mana_pct: " .. tostring(ctx.player_mana_pct))
    assert(ctx.player_is_moving == 0, "is_moving")
    assert(ctx.player_is_casting == 0, "is_casting")
    assert(ctx.target_is_casting == 1, "target casting")
    assert(ctx.enemy_count == 2, "enemy_count")
    assert(ctx.in_combat == 1, "in_combat")

    -- Distance should be ~5 yards
    assert(ctx.target_distance ~= nil, "distance should exist")
    assert(math.abs(ctx.target_distance - 5) < 1, "distance ~5: " .. tostring(ctx.target_distance))

    env.restore()
    return true
end

return M
