local T = require("tests/TestUtil")

local function run()
    local learned = {
        [27072] = true,  -- Frostbolt
        [27079] = true,  -- Fire Blast
        [30455] = true,  -- Ice Lance
        [27087] = true,  -- Cone of Cold
        [27085] = true,  -- Blizzard
        [27082] = true,  -- Arcane Explosion
        [27088] = true,  -- Frost Nova
        [33405] = true,  -- Ice Barrier
        [45438] = true,  -- Ice Block
        [27131] = true,  -- Mana Shield
        [11958] = true,  -- Cold Snap
        [2139]  = true,  -- Counterspell
        [12051] = true,  -- Evocation
        [27126] = true,  -- Arcane Intellect
        [27124] = true,  -- Ice Armor
        [7301]  = true,  -- Frost Armor
    }

    T.install_core_stub({
        spell_book = {
            is_spell_learned = function(id)
                return learned[tonumber(id) or -1] == true
            end,
            has_spell = function(id)
                return learned[tonumber(id) or -1] == true
            end,
            is_usable_spell = function() return true end,
        },
    })

    local provider = require("rotations/mage/Frost")
    provider._mana_mode = nil

    local function resolve_from_fallback(name, fallback_ids)
        if type(fallback_ids) == "table" and #fallback_ids > 0 then
            return fallback_ids[1]
        end
        return nil
    end

    local base_ctx = {
        class_id = 8,
        in_combat = true,
        enemy_count = 1,
        player_mana_pct = 0.55,
        player_has_aura = function() return false end,
        target_has_aura = function() return false end,
        resolve_spell_id = resolve_from_fallback,
    }

    -- -----------------------------------------------------------------------
    -- 1. Identity tests
    -- -----------------------------------------------------------------------
    T.assert_eq(provider:id(), "mage.frost", "frost provider id should be mage.frost")
    T.assert_eq(provider:class_id(), 8, "frost provider class_id should be 8 (mage)")
    T.assert_eq(provider:spec_id(), 0, "frost provider spec_id should be 0")
    T.assert_eq(provider:spec(), "frost", "frost provider spec should be frost")

    -- -----------------------------------------------------------------------
    -- 2. can_run
    -- -----------------------------------------------------------------------
    T.assert_true(provider:can_run(base_ctx) == true,
        "frost provider should run for mage class")
    T.assert_true(provider:can_run({ class_id = 2 }) == false,
        "frost provider should not run for paladin class")
    T.assert_true(provider:can_run({ class_id = 9 }) == false,
        "frost provider should not run for warlock class")
    T.assert_true(provider:can_run({}) == false,
        "frost provider should not run when class_id is missing")

    -- -----------------------------------------------------------------------
    -- 3. resolve_combat_state — returns table with mana_mode, intents
    -- -----------------------------------------------------------------------
    provider._mana_mode = nil
    local state_burst = provider:resolve_combat_state({
        player_mana_pct = 0.70,
        target_health_pct = 0.80,
    })
    T.assert_eq(state_burst.combat_mode, "burst", "high mana should resolve burst mode")
    T.assert_eq(state_burst.mana_mode, "burst", "mana_mode alias should match combat_mode")
    T.assert_true(type(state_burst.planner_intents) == "table",
        "resolve_combat_state should return planner_intents table")

    local state_sustain = provider:resolve_combat_state({
        player_mana_pct = 0.35,
        target_health_pct = 0.80,
    })
    T.assert_eq(state_sustain.combat_mode, "sustain", "mid mana should resolve sustain mode")

    local state_recovery = provider:resolve_combat_state({
        player_mana_pct = 0.10,
        target_health_pct = 0.80,
    })
    T.assert_eq(state_recovery.combat_mode, "recovery", "low mana should resolve recovery mode")

    -- nil ctx should not crash
    local state_nil = provider:resolve_combat_state(nil)
    T.assert_true(type(state_nil) == "table",
        "resolve_combat_state should handle nil ctx gracefully")

    -- -----------------------------------------------------------------------
    -- 4. maintenance — armor/intellect buffs, food, water
    -- -----------------------------------------------------------------------
    local maint_ctx = {
        class_id = 8,
        in_combat = false,
        player_mana_pct = 0.55,
        player_has_aura = function() return false end,
        resolve_spell_id = resolve_from_fallback,
    }
    local maintenance = provider:maintenance(maint_ctx)
    T.assert_true(type(maintenance) == "table" and #maintenance > 0,
        "maintenance should return non-empty action list")

    local has_intellect_action = false
    local has_armor_action = false
    local has_food_action = false
    local has_water_action = false
    local food_action = nil
    local water_action = nil
    for i = 1, #maintenance do
        local action = maintenance[i]
        if action.action_type == "cast_spell_self" and tonumber(action.priority) == 240 then
            has_intellect_action = true
        end
        if action.action_type == "cast_spell_self" and tonumber(action.priority) == 235 then
            has_armor_action = true
        end
        if action.action_type == "use_item_self" and type(action.item_kind) == "string" then
            if action.item_kind == "food" and tonumber(action.priority) == 985 then
                has_food_action = true
                food_action = action
            elseif action.item_kind == "water" and tonumber(action.priority) == 984 then
                has_water_action = true
                water_action = action
            end
        end
    end
    T.assert_true(has_intellect_action, "maintenance should include Arcane Intellect action")
    T.assert_true(has_armor_action, "maintenance should include armor buff action")
    T.assert_true(has_food_action, "maintenance should include food action")
    T.assert_true(has_water_action, "maintenance should include water action")

    -- Food should be allowed while already drinking
    T.assert_true(food_action.condition({
        in_combat = false,
        player_is_moving = false,
        eating_or_drinking = true,
        player_is_eating = false,
        player_is_drinking = true,
        player_health_pct = 0.50,
    }, food_action) == true, "food should still be allowed while already drinking")

    -- Water should be allowed while already eating
    T.assert_true(water_action.condition({
        in_combat = false,
        player_is_moving = false,
        eating_or_drinking = true,
        player_is_eating = true,
        player_is_drinking = false,
        player_mana_pct = 0.30,
    }, water_action) == true, "water should still be allowed while already eating")

    -- Maintenance returns empty combat actions when stunned
    local stunned_combat = provider:combat({
        class_id = 8,
        in_combat = true,
        player_is_stunned = true,
        player_has_aura = function() return false end,
        resolve_spell_id = resolve_from_fallback,
    })
    T.assert_eq(#stunned_combat, 0, "combat should return empty when player is stunned")

    -- -----------------------------------------------------------------------
    -- 5. defensive — Ice Block, Ice Barrier, Frost Nova, health/mana potions
    -- -----------------------------------------------------------------------
    local defensive = provider:defensive(base_ctx)
    T.assert_true(type(defensive) == "table" and #defensive > 0,
        "defensive should return non-empty action list")

    local ice_block_action = nil
    local ice_barrier_action = nil
    local frost_nova_action = nil
    local cold_snap_action = nil
    local mana_shield_action = nil
    local has_health_potion = false
    local has_mana_potion = false
    for i = 1, #defensive do
        local action = defensive[i]
        if action.action_type == "cast_spell_self" and tonumber(action.priority) == 990 then
            ice_block_action = action
        elseif action.action_type == "cast_spell_self" and tonumber(action.priority) == 985 then
            cold_snap_action = action
        elseif action.action_type == "cast_spell_self" and tonumber(action.priority) == 950 then
            ice_barrier_action = action
        elseif action.action_type == "cast_spell_self" and tonumber(action.priority) == 940 then
            frost_nova_action = action
        elseif action.action_type == "cast_spell_self" and tonumber(action.priority) == 920 then
            mana_shield_action = action
        elseif action.action_type == "use_best_health_potion" then
            has_health_potion = true
        elseif action.action_type == "use_best_mana_potion" then
            has_mana_potion = true
        end
    end
    T.assert_true(type(ice_block_action) == "table", "defensive should include Ice Block action")
    T.assert_true(type(ice_barrier_action) == "table", "defensive should include Ice Barrier action")
    T.assert_true(type(frost_nova_action) == "table", "defensive should include Frost Nova action")
    T.assert_true(type(cold_snap_action) == "table", "defensive should include Cold Snap action")
    T.assert_true(type(mana_shield_action) == "table", "defensive should include Mana Shield action")
    T.assert_true(has_health_potion, "defensive should include health potion action")
    T.assert_true(has_mana_potion, "defensive should include mana potion action")

    -- Ice Block requires in_combat and not stunned
    T.assert_true(ice_block_action.condition({
        in_combat = true,
        player_is_stunned = false,
    }, ice_block_action) == true,
        "Ice Block should trigger in combat when not stunned")
    T.assert_true(ice_block_action.condition({
        in_combat = true,
        player_is_stunned = true,
    }, ice_block_action) == false,
        "Ice Block should be blocked when player is stunned")

    -- Frost Nova requires in combat and target in melee range
    T.assert_true(frost_nova_action.condition({
        in_combat = true,
        target_distance = 5.0,
    }, frost_nova_action) == true,
        "Frost Nova should trigger when target is in melee range")
    T.assert_true(frost_nova_action.condition({
        in_combat = true,
        target_distance = 15.0,
    }, frost_nova_action) == false,
        "Frost Nova should not trigger when target is far away")
    T.assert_true(frost_nova_action.condition({
        in_combat = false,
        target_distance = 5.0,
    }, frost_nova_action) == false,
        "Frost Nova should not trigger outside combat")

    -- Ice Barrier requires no existing barrier aura
    T.assert_true(ice_barrier_action.condition({
        player_has_aura = function() return false end,
    }, ice_barrier_action) == true,
        "Ice Barrier should be available when no barrier aura is active")
    T.assert_true(ice_barrier_action.condition({
        player_has_aura = function() return true end,
    }, ice_barrier_action) == false,
        "Ice Barrier should be blocked when barrier aura is already active")

    -- Cold Snap requires frost CDs to be active
    T.assert_true(cold_snap_action.condition({
        in_combat = true,
        spell_cooldown_remaining = function() return 5.0 end,
        resolve_spell_id = resolve_from_fallback,
        player_has_aura = function() return false end,
    }, cold_snap_action) == true,
        "Cold Snap should trigger when frost CDs are on cooldown")
    T.assert_true(cold_snap_action.condition({
        in_combat = true,
        spell_cooldown_remaining = function() return 0 end,
        resolve_spell_id = resolve_from_fallback,
        player_has_aura = function() return false end,
    }, cold_snap_action) == false,
        "Cold Snap should not trigger when frost CDs are ready")

    -- Mana Shield requires in combat, no existing shields
    T.assert_true(mana_shield_action.condition({
        in_combat = true,
        player_has_aura = function() return false end,
    }, mana_shield_action) == true,
        "Mana Shield should be available when no shields are active in combat")
    T.assert_true(mana_shield_action.condition({
        in_combat = true,
        player_has_aura = function() return true end,
    }, mana_shield_action) == false,
        "Mana Shield should be blocked when a shield is already active")

    -- -----------------------------------------------------------------------
    -- 6. interrupt — Counterspell
    -- -----------------------------------------------------------------------
    local interrupt = provider:interrupt(base_ctx)
    T.assert_true(type(interrupt) == "table" and #interrupt > 0,
        "interrupt should return non-empty action list")

    local cs_action = nil
    for i = 1, #interrupt do
        local action = interrupt[i]
        if action.action_type == "cast_spell_target" and tonumber(action.priority) == 980 then
            cs_action = action
        end
    end
    T.assert_true(type(cs_action) == "table", "interrupt should include Counterspell action")
    T.assert_true(cs_action.target_must_be_casting == true,
        "Counterspell should require target to be casting")
    T.assert_eq(tonumber(cs_action.max_target_distance), 30.0,
        "Counterspell should use 30-yard range")

    -- Counterspell condition: learned and interruptable
    T.assert_true(cs_action.condition({
        target_is_interruptable = true,
        resolve_spell_id = resolve_from_fallback,
    }, cs_action) == true,
        "Counterspell should be allowed when target is interruptable")
    T.assert_true(cs_action.condition({
        target_is_interruptable = false,
        resolve_spell_id = resolve_from_fallback,
    }, cs_action) == false,
        "Counterspell should be blocked when target is not interruptable")

    -- Empty interrupt when no target casting (target_must_be_casting handled by engine)
    -- The interrupt list always returns actions; the engine checks target_must_be_casting

    -- -----------------------------------------------------------------------
    -- 7. combat — Frostbolt, Fire Blast, Ice Lance
    -- -----------------------------------------------------------------------
    local combat = provider:combat(base_ctx)
    T.assert_true(type(combat) == "table" and #combat > 0,
        "combat should return non-empty action list")

    local frostbolt_action = nil
    local fire_blast_action = nil
    local ice_lance_action = nil
    for i = 1, #combat do
        local action = combat[i]
        if action.action_type == "cast_spell_target" and tonumber(action.priority) == 540 then
            frostbolt_action = action
        elseif action.action_type == "cast_spell_target" and tonumber(action.priority) == 545 then
            fire_blast_action = action
        elseif action.action_type == "cast_spell_target" and tonumber(action.priority) == 555 then
            ice_lance_action = action
        end
    end
    T.assert_true(type(frostbolt_action) == "table", "combat should include Frostbolt action")
    T.assert_true(type(fire_blast_action) == "table", "combat should include Fire Blast action")
    T.assert_true(type(ice_lance_action) == "table", "combat should include Ice Lance action")
    T.assert_eq(tonumber(frostbolt_action.max_target_distance), 30.0,
        "Frostbolt should use 30-yard range")
    T.assert_true(frostbolt_action.allow_movement == false,
        "Frostbolt should require standing still")
    T.assert_eq(tonumber(fire_blast_action.max_target_distance), 20.0,
        "Fire Blast should use 20-yard range")
    T.assert_eq(tonumber(ice_lance_action.max_target_distance), 30.0,
        "Ice Lance should use 30-yard range")

    -- Ice Lance requires Fingers of Frost or Frostbite on target
    T.assert_true(ice_lance_action.condition({
        player_has_aura = function() return false end,
        target_has_aura = function() return false end,
    }, ice_lance_action) == false,
        "Ice Lance should be blocked without Fingers of Frost or Frostbite")

    T.assert_true(ice_lance_action.condition({
        player_has_aura = function(aura_ids)
            -- Fingers of Frost aura ID 44544
            for i = 1, #aura_ids do
                if aura_ids[i] == 44544 then return true end
            end
            return false
        end,
        target_has_aura = function() return false end,
    }, ice_lance_action) == true,
        "Ice Lance should be allowed with Fingers of Frost proc")

    T.assert_true(ice_lance_action.condition({
        player_has_aura = function() return false end,
        target_has_aura = function(aura_ids)
            -- Frostbite aura IDs: 12494, 12496, 12497
            for i = 1, #aura_ids do
                if aura_ids[i] == 12494 then return true end
            end
            return false
        end,
    }, ice_lance_action) == true,
        "Ice Lance should be allowed with Frostbite on target")

    -- Feared should return empty combat
    local feared_combat = provider:combat({
        class_id = 8,
        in_combat = true,
        player_is_feared = true,
        player_has_aura = function() return false end,
        resolve_spell_id = resolve_from_fallback,
    })
    T.assert_eq(#feared_combat, 0, "combat should return empty when player is feared")

    -- -----------------------------------------------------------------------
    -- 8. aoe — Cone of Cold, Arcane Explosion
    -- -----------------------------------------------------------------------
    local aoe = provider:aoe(base_ctx)
    T.assert_true(type(aoe) == "table" and #aoe > 0,
        "aoe should return non-empty action list")

    local cone_of_cold_action = nil
    local blizzard_action = nil
    local arcane_explosion_action = nil
    local aoe_frostbolt_action = nil
    for i = 1, #aoe do
        local action = aoe[i]
        if action.action_type == "cast_spell_target" and tonumber(action.priority) == 555 then
            cone_of_cold_action = action
        elseif action.action_type == "cast_spell_position" and tonumber(action.priority) == 550 then
            blizzard_action = action
        elseif action.action_type == "cast_spell_self" and tonumber(action.priority) == 545 then
            arcane_explosion_action = action
        elseif action.action_type == "cast_spell_target" and tonumber(action.priority) == 530 then
            aoe_frostbolt_action = action
        end
    end
    T.assert_true(type(cone_of_cold_action) == "table", "aoe should include Cone of Cold action")
    T.assert_true(type(blizzard_action) == "table", "aoe should include Blizzard action")
    T.assert_true(type(arcane_explosion_action) == "table", "aoe should include Arcane Explosion action")
    T.assert_true(type(aoe_frostbolt_action) == "table", "aoe should include fallback Frostbolt action")
    T.assert_eq(tonumber(cone_of_cold_action.max_target_distance), 10.0,
        "Cone of Cold should use 10-yard range")

    -- Cone of Cold requires >= 2 enemies
    T.assert_true(cone_of_cold_action.condition({
        nearby_enemy_count = 2,
    }, cone_of_cold_action) == true,
        "Cone of Cold should trigger with 2+ enemies")
    T.assert_true(cone_of_cold_action.condition({
        nearby_enemy_count = 1,
    }, cone_of_cold_action) == false,
        "Cone of Cold should not trigger with fewer than 2 enemies")

    -- Arcane Explosion requires >= 3 enemies
    T.assert_true(arcane_explosion_action.condition({
        nearby_enemy_count = 3,
    }, arcane_explosion_action) == true,
        "Arcane Explosion should trigger with 3+ enemies")
    T.assert_true(arcane_explosion_action.condition({
        nearby_enemy_count = 2,
    }, arcane_explosion_action) == false,
        "Arcane Explosion should not trigger with fewer than 3 enemies")

    -- Blizzard requires >= 3 enemies and valid pack centroid
    T.assert_eq(tonumber(blizzard_action.priority), 550,
        "Blizzard should have priority 550")
    T.assert_true(blizzard_action.allow_movement == false,
        "Blizzard should not allow movement (channeled)")
    T.assert_eq(blizzard_action.min_player_mana_pct, 0.25,
        "Blizzard should require 25% mana")

    T.assert_true(blizzard_action.condition({
        nearby_enemy_count = 3,
        pack_centroid_x = -1630.5,
        pack_centroid_y = 5251.2,
        pack_centroid_z = 32.1,
    }, blizzard_action) == true,
        "Blizzard should trigger with 3+ enemies and valid centroid")
    T.assert_true(blizzard_action.condition({
        nearby_enemy_count = 2,
        pack_centroid_x = -1630.5,
        pack_centroid_y = 5251.2,
        pack_centroid_z = 32.1,
    }, blizzard_action) == false,
        "Blizzard should not trigger with fewer than 3 enemies")
    T.assert_true(blizzard_action.condition({
        nearby_enemy_count = 4,
    }, blizzard_action) == false,
        "Blizzard should not trigger without pack centroid coordinates")
    T.assert_true(blizzard_action.condition({
        nearby_enemy_count = 3,
        pack_centroid_x = 0,
        pack_centroid_y = 0,
        pack_centroid_z = 0,
    }, blizzard_action) == false,
        "Blizzard should not trigger with zero centroid (no valid pack)")

    -- Blizzard resolve_position returns centroid coordinates
    T.assert_true(type(blizzard_action.resolve_position) == "function",
        "Blizzard should have a resolve_position function")
    local blizzard_pos = blizzard_action.resolve_position({
        pack_centroid_x = -1630.5,
        pack_centroid_y = 5251.2,
        pack_centroid_z = 32.1,
    })
    T.assert_eq(blizzard_pos.x, -1630.5, "Blizzard resolve_position x should match centroid")
    T.assert_eq(blizzard_pos.y, 5251.2, "Blizzard resolve_position y should match centroid")
    T.assert_eq(blizzard_pos.z, 32.1, "Blizzard resolve_position z should match centroid")

    -- AoE returns empty when stunned
    local stunned_aoe = provider:aoe({
        class_id = 8,
        in_combat = true,
        player_is_stunned = true,
        player_has_aura = function() return false end,
        resolve_spell_id = resolve_from_fallback,
    })
    T.assert_eq(#stunned_aoe, 0, "aoe should return empty when player is stunned")

    -- -----------------------------------------------------------------------
    -- 9. get_pull_profile — Frostbolt at 30yd
    -- -----------------------------------------------------------------------
    local pull = provider:get_pull_profile(base_ctx)
    T.assert_true(type(pull) == "table", "pull profile should be a table")
    T.assert_eq(tonumber(pull.max_pull_range), 30.0,
        "pull profile should use 30-yard Frostbolt range")
    T.assert_true(pull.pull_spell_id ~= nil,
        "pull profile should have a pull spell id")

    -- -----------------------------------------------------------------------
    -- 10. get_movement_profile — combat_chase_range
    -- -----------------------------------------------------------------------
    local movement = provider:get_movement_profile(base_ctx)
    T.assert_true(type(movement) == "table", "movement profile should be a table")
    T.assert_eq(tonumber(movement.combat_chase_range), 30.0,
        "movement profile should use 30-yard chase range matching Frostbolt range")
    T.assert_eq(tonumber(movement.min_combat_range), 8.0,
        "movement profile should keep a contact floor to avoid melee range")

    local frozen_movement = provider:get_movement_profile({
        class_id = 8,
        target_has_aura = function(aura_ids)
            if type(aura_ids) ~= "table" then
                return false
            end
            for i = 1, #aura_ids do
                if aura_ids[i] == 122 then -- Frost Nova root rank
                    return true
                end
            end
            return false
        end,
    })
    T.assert_eq(tonumber(frozen_movement.min_combat_range), 25.0,
        "movement profile should enable ranged kiting window while target is frozen")

    -- -----------------------------------------------------------------------
    -- 11. mana_mode transitions — hysteresis thresholds
    -- -----------------------------------------------------------------------
    -- Default thresholds: sustain_enter=0.40, sustain_exit=0.55,
    --                     recovery_enter=0.15, recovery_exit=0.25

    -- Reset mana mode for clean hysteresis test
    provider._mana_mode = nil

    -- Start at high mana -> burst
    local h1 = provider:resolve_combat_state({ player_mana_pct = 0.70 })
    T.assert_eq(h1.combat_mode, "burst", "fresh high mana should be burst")

    -- Drop to 0.38 -> sustain (below sustain_enter=0.40)
    local h2 = provider:resolve_combat_state({ player_mana_pct = 0.38 })
    T.assert_eq(h2.combat_mode, "sustain", "mana below sustain_enter should transition to sustain")

    -- Stay at 0.50 in sustain -> should hold sustain (below sustain_exit=0.55)
    local h3 = provider:resolve_combat_state({ player_mana_pct = 0.50 })
    T.assert_eq(h3.combat_mode, "sustain",
        "sustain mode should hold until sustain_exit threshold is crossed")

    -- Rise to 0.56 -> burst (above sustain_exit=0.55)
    local h4 = provider:resolve_combat_state({ player_mana_pct = 0.56 })
    T.assert_eq(h4.combat_mode, "burst", "mana above sustain_exit should return to burst")

    -- Drop to 0.12 -> recovery (below recovery_enter=0.15)
    local h5 = provider:resolve_combat_state({ player_mana_pct = 0.12 })
    T.assert_eq(h5.combat_mode, "recovery", "mana below recovery_enter should transition to recovery")

    -- Stay at 0.22 -> hold recovery (below recovery_exit=0.25)
    local h6 = provider:resolve_combat_state({ player_mana_pct = 0.22 })
    T.assert_eq(h6.combat_mode, "recovery",
        "recovery mode should hold until recovery_exit threshold is crossed")

    -- Rise to 0.30 -> sustain (above recovery_exit=0.25 but below sustain_exit=0.55)
    local h7 = provider:resolve_combat_state({ player_mana_pct = 0.30 })
    T.assert_eq(h7.combat_mode, "sustain",
        "exiting recovery above recovery_exit but below sustain_exit should enter sustain")

    -- Rise to 0.60 -> burst
    local h8 = provider:resolve_combat_state({ player_mana_pct = 0.60 })
    T.assert_eq(h8.combat_mode, "burst",
        "mana above sustain_exit should return to burst from sustain")

    -- Drop directly from burst to recovery
    local h9 = provider:resolve_combat_state({ player_mana_pct = 0.10 })
    T.assert_eq(h9.combat_mode, "recovery",
        "sharp mana drop from burst should go directly to recovery")

    return {
        mage_frost_regressions = true,
    }
end

return { run = run }
