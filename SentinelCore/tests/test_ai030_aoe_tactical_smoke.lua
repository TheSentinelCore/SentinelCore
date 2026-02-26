-- SentinelCore/tests/test_ai030_aoe_tactical_smoke.lua
-- AoE tactical system end-to-end smoke test
local T = require("tests/TestUtil")

return { run = function()
    local env = T.install_core_stub()

    local TacticalSelector = require("ai/TacticalSelector")
    local SingleTargetTactic = require("tactics/SingleTargetTactic")
    local AoEKiteTactic = require("tactics/AoEKiteTactic")
    local PositioningService = require("services/PositioningService")
    local CombatContext = require("ai/CombatContext")
    local Blackboard = require("core/Blackboard")
    local BT = require("ai/BehaviorTree")

    -- ----------------------------------------------------------------
    -- 1. Selector picks AoEKiteTactic for 3+ pack
    -- ----------------------------------------------------------------
    local selector = TacticalSelector:new(nil)
    selector:register(SingleTargetTactic:new())
    selector:register(AoEKiteTactic:new())
    selector:refresh_available({ pack_count = 4, player_mana_pct = 0.8 })

    local ctx_aoe = {
        pack_count = 4,
        player_mana_pct = 0.8,
        enemy_count = 4,
    }
    local picked = selector:select(ctx_aoe)
    T.assert_eq(picked:get_name(), "aoe_kite", "selector picks AoE for pack=4")

    -- ----------------------------------------------------------------
    -- 2. Selector falls back to SingleTarget for small pack
    -- ----------------------------------------------------------------
    local selector2 = TacticalSelector:new(nil)
    selector2:register(SingleTargetTactic:new())
    selector2:register(AoEKiteTactic:new())
    selector2:refresh_available({ pack_count = 1, player_mana_pct = 0.8 })

    local ctx_small = {
        pack_count = 1,
        player_mana_pct = 0.8,
        enemy_count = 1,
    }
    local picked_small = selector2:select(ctx_small)
    T.assert_eq(picked_small:get_name(), "single_target", "selector picks ST for pack=1")

    -- ----------------------------------------------------------------
    -- 3. Selector falls back to SingleTarget at low mana
    -- ----------------------------------------------------------------
    local selector3 = TacticalSelector:new(nil)
    selector3:register(SingleTargetTactic:new())
    selector3:register(AoEKiteTactic:new())
    -- refresh with low mana: AoE preconditions fail at 15%
    selector3:refresh_available({ pack_count = 4, player_mana_pct = 0.15 })

    local ctx_low_mana = {
        pack_count = 4,
        player_mana_pct = 0.15,
        enemy_count = 4,
    }
    local picked_low = selector3:select(ctx_low_mana)
    T.assert_eq(picked_low:get_name(), "single_target", "selector falls back to ST at low mana")

    -- ----------------------------------------------------------------
    -- 4. AoE tactic phases transition
    -- ----------------------------------------------------------------
    local tactic = AoEKiteTactic:new()
    local phases = tactic:get_phases()
    T.assert_eq(phases[1].name, "engage", "phase 1 is engage")
    T.assert_eq(phases[2].name, "aoe_combat", "phase 2 is aoe_combat")

    -- engage enters with has_target=true, in_combat=false
    T.assert_true(
        phases[1].enter_if({ has_target = true, in_combat = false }),
        "engage enters with target and no combat"
    )

    -- aoe_combat enters with in_combat=true
    T.assert_true(
        phases[2].enter_if({ in_combat = true }),
        "aoe_combat enters in combat"
    )

    -- ----------------------------------------------------------------
    -- 5. PositioningService integration
    -- ----------------------------------------------------------------
    -- kite_position: player at {100,200,0}, threat at {105,200,0}
    -- threat is to the +x side, so kite should move in -x direction
    local player_pos = { x = 100, y = 200, z = 0 }
    local threat_pos = { x = 105, y = 200, z = 0 }
    local kite = PositioningService.kite_position(player_pos, threat_pos, 8)
    T.assert_true(kite ~= nil, "kite_position returns a result")
    T.assert_true(kite.x < 100, "kite x < 100 (away from threat at x=105)")

    -- aoe_center: enemies near {100,200,0} at 30yd range
    local enemies = {
        { x = 98, y = 202, z = 0 },
        { x = 102, y = 198, z = 0 },
        { x = 100, y = 200, z = 0 },
    }
    local aoe_center = PositioningService.aoe_center(player_pos, enemies, 30)
    T.assert_true(aoe_center ~= nil, "aoe_center returns a result")
    T.assert_true(type(aoe_center.x) == "number", "aoe_center has numeric x")
    T.assert_true(type(aoe_center.y) == "number", "aoe_center has numeric y")
    T.assert_true(type(aoe_center.z) == "number", "aoe_center has numeric z")

    -- ----------------------------------------------------------------
    -- 6. CombatContext pack fields
    -- ----------------------------------------------------------------
    local bb = Blackboard:new()
    local mock_player = T.mock_object({
        health = 800, max_health = 1000,
        mana = 800, max_mana = 1000,
        in_combat = true,
        position = { x = 100, y = 200, z = 0 },
    })
    bb:set("player.object", mock_player)
    bb:set("player.health", 800)
    bb:set("player.max_health", 1000)
    bb:set("player.in_combat", true)
    bb:set("player.position", { x = 100, y = 200, z = 0 })
    bb:set("combat.enemy_count", 4)

    -- Set pack data
    bb:set("pack.count", 4)
    bb:set("pack.spread", 5.5)
    bb:set("pack.centroid", { x = 110, y = 210, z = 3 })
    bb:set("pack.gathered_count", 3)

    local ctx = CombatContext.build(bb)
    T.assert_eq(ctx.pack_count, 4, "pack_count is 4")
    T.assert_eq(ctx.pack_centroid_x, 110, "pack_centroid_x is 110")
    T.assert_eq(ctx.pack_centroid_y, 210, "pack_centroid_y is 210")
    T.assert_eq(ctx.pack_centroid_z, 3, "pack_centroid_z is 3")
    T.assert_eq(ctx.pack_spread, 5.5, "pack_spread is 5.5")
    T.assert_eq(ctx.pack_gathered_count, 3, "pack_gathered_count is 3")

    env.restore()
    return true
end }
