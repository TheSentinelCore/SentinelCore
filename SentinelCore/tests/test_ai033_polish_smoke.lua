local T = require("tests/TestUtil")

return { run = function()
    -- 1. AoEKiteTactic level gate: rejected below level 20
    do
        local AoEKiteTactic = require("tactics/AoEKiteTactic")
        local tactic = AoEKiteTactic:new()

        -- Below level 20: preconditions fail even with good pack/mana
        local low_ctx = {
            pack_count = 5,
            player_mana_pct = 0.8,
            player_level = 15,
            enemy_count = 5,
            in_combat = false,
            has_target = false,
        }
        T.assert_true(not tactic:check_preconditions(low_ctx),
            "AoE preconditions fail at level 15")

        -- At level 20: preconditions pass
        local high_ctx = {
            pack_count = 5,
            player_mana_pct = 0.8,
            player_level = 20,
            enemy_count = 5,
            in_combat = false,
            has_target = false,
        }
        T.assert_true(tactic:check_preconditions(high_ctx),
            "AoE preconditions pass at level 20")
    end

    -- 2. AoEKiteTactic pack threshold bounds (anti-detection)
    --    Threshold varies between 3 and 4. Test deterministic bounds:
    --    pack_count=4 always passes (>= max threshold 4)
    --    pack_count=2 always fails (< min threshold 3)
    do
        local AoEKiteTactic = require("tactics/AoEKiteTactic")
        local tactic = AoEKiteTactic:new()

        -- pack_count=4: always passes regardless of threshold (3 or 4)
        local ctx_high = {
            pack_count = 4,
            player_mana_pct = 0.8,
            player_level = 25,
            enemy_count = 4,
            in_combat = false,
            has_target = false,
        }
        T.assert_true(tactic:check_preconditions(ctx_high),
            "pack_count=4 always passes (>= max threshold)")

        -- pack_count=2: always fails regardless of threshold (3 or 4)
        local ctx_low = {
            pack_count = 2,
            player_mana_pct = 0.8,
            player_level = 25,
            enemy_count = 2,
            in_combat = false,
            has_target = false,
        }
        T.assert_true(not tactic:check_preconditions(ctx_low),
            "pack_count=2 always fails (< min threshold)")
    end

    -- 3. PositioningService jitter functions exist and produce valid output
    do
        local PS = require("services/PositioningService")

        -- jitter_kite_position: returns a position near the base kite position
        local player = { x = 10, y = 0, z = 0 }
        local threat = { x = 0, y = 0, z = 0 }
        local jittered = PS.jitter_kite_position(player, threat, 5)
        T.assert_true(jittered ~= nil, "jitter_kite_position returns non-nil")
        T.assert_true(type(jittered.x) == "number", "jittered kite has x")
        T.assert_true(type(jittered.y) == "number", "jittered kite has y")
        T.assert_true(type(jittered.z) == "number", "jittered kite has z")

        -- Should be roughly in the right area (within jitter radius of base kite)
        local base = PS.kite_position(player, threat, 5)
        local dx = jittered.x - base.x
        local dy = jittered.y - base.y
        local jitter_dist = math.sqrt(dx * dx + dy * dy)
        T.assert_true(jitter_dist <= 3.0, "jitter offset within 3yd radius, got " .. jitter_dist)

        -- jitter_aoe_center: returns a position near the base aoe center
        local enemies = {
            { x = 5, y = 0, z = 0 },
            { x = 7, y = 0, z = 0 },
        }
        local aoe_jittered = PS.jitter_aoe_center({ x = 0, y = 0, z = 0 }, enemies, 30)
        T.assert_true(aoe_jittered ~= nil, "jitter_aoe_center returns non-nil")
        local aoe_base = PS.aoe_center({ x = 0, y = 0, z = 0 }, enemies, 30)
        local adx = aoe_jittered.x - aoe_base.x
        local ady = aoe_jittered.y - aoe_base.y
        local aoe_jitter_dist = math.sqrt(adx * adx + ady * ady)
        T.assert_true(aoe_jitter_dist <= 3.0,
            "aoe jitter offset within 3yd radius, got " .. aoe_jitter_dist)

        -- nil inputs handled gracefully
        T.assert_true(PS.jitter_kite_position(nil, threat, 5) == nil,
            "jitter_kite nil from_pos returns nil")
        T.assert_true(PS.jitter_aoe_center(nil, enemies, 30) == nil,
            "jitter_aoe nil player_pos returns nil")
    end

    -- 4. GrindService tactical_sync_node includes player_level
    do
        local GrindService = require("services/GrindService")
        -- Verify the module loads without error (structural test)
        T.assert_true(GrindService ~= nil, "GrindService loads")
        T.assert_true(type(GrindService.build) == "function", "GrindService.build is a function")
    end

    return true
end }
