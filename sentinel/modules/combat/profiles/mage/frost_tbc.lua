local BT = require("core/bt/factory")
local Runner = require("core/bt/runner")
local Cond = require("modules/combat/profiles/mage/frost_conditions")
local Act = require("modules/combat/profiles/mage/frost_actions")
local MaintenanceTree = require("modules/combat/profiles/mage/maintenance_tree")
local FrostCombatState = require("modules/combat/profiles/mage/frost_combat_state")
local KiteController = require("modules/combat/profiles/mage/kite_controller")
local PetController = require("modules/combat/profiles/mage/pet_controller")
local PriorityBuilder = require("kernel/lib/priority_builder")
local ActionLibrary = require("modules/combat/action_library")

local Profile = {}
Profile.__index = Profile

-- ---------------------------------------------------------------------------
-- Off-GCD tree (selector, 75ms tick)
-- Cast cancellation, barrier, icy veins, cold snap
-- Kite controller ticks separately in tick_off_gcd() to run every cycle
-- ---------------------------------------------------------------------------
local function build_off_gcd_root()
    return BT.selector("frost_mage_off_gcd", {
        -- 1. Cancel overkill cast (target dying before cast finishes)
        BT.sequence("cancel_overkill", {
            BT.condition("cast_overkill", Cond.cast_is_overkill),
            BT.action("cancel_cast", Act.cancel_current_cast),
        }),
        -- 2. Cancel cast when enemy closing to melee + Frost Nova available
        BT.sequence("cancel_cast_melee", {
            BT.condition("should_cancel", Cond.should_cancel_cast),
            BT.action("cancel_cast", Act.cancel_current_cast),
        }),
        -- 3. Ice Barrier maintenance (talent, ~level 30+)
        BT.sequence("ice_barrier", {
            BT.condition("level_at_least_30", Cond.level_at_least(30)),
            BT.condition("missing_ice_barrier", Cond.missing_ice_barrier),
            BT.condition("ice_barrier_ready", Cond.spell_ready("ice_barrier", nil, "self")),
            BT.action("queue_ice_barrier", Act.queue_ice_barrier),
        }),
        -- 4. Icy Veins (in combat, not kiting)
        BT.sequence("icy_veins", {
            BT.condition("in_combat", Cond.in_combat),
            BT.condition("not_kiting", Cond.not_kiting),
            BT.condition("icy_veins_ready", Cond.spell_ready("icy_veins", nil, "self")),
            BT.action("queue_icy_veins", Act.queue_icy_veins),
        }),
        -- 5a. Cold Snap defensive (health < 30%)
        BT.sequence("cold_snap_defensive", {
            BT.condition("health_below_30", Cond.health_below(0.30)),
            BT.condition("cold_snap_ready", Cond.spell_ready("cold_snap", nil, "self")),
            BT.action("queue_cold_snap", Act.queue_cold_snap),
        }),
        -- 5b. Cold Snap offensive (reset Icy Veins when safe)
        BT.sequence("cold_snap_offensive", {
            BT.condition("in_combat", Cond.in_combat),
            BT.condition("health_above_60", Cond.health_above(0.60)),
            BT.condition("cold_snap_ready", Cond.spell_ready("cold_snap", nil, "self")),
            BT.condition("icy_veins_on_cd", function(bb)
                return not Cond.spell_ready("icy_veins", nil, "self")(bb)
            end),
            BT.action("queue_cold_snap", Act.queue_cold_snap),
        }),
        -- 6. Health potion (off-GCD, HP < 30%)
        BT.sequence("use_health_pot", {
            BT.condition("in_combat", Cond.in_combat),
            BT.condition("has_hp_pot", Cond.has_health_potion()),
            BT.condition("hp_below_30", Cond.health_below(0.30)),
            BT.condition("pot_ready", Cond.potion_ready()),
            BT.action("use_hp_pot", Act.use_health_potion),
        }),
        -- 7. Mana potion (off-GCD, mana < 15%)
        BT.sequence("use_mana_pot", {
            BT.condition("in_combat", Cond.in_combat),
            BT.condition("has_mp_pot", Cond.has_mana_potion()),
            BT.condition("mana_below_15", Cond.mana_below(0.15)),
            BT.condition("pot_ready", Cond.potion_ready()),
            BT.action("use_mp_pot", Act.use_mana_potion),
        }),
        -- 8. Pet attack on engage (one-time per target)
        BT.sequence("pet_attack", {
            BT.condition("has_pet", Cond.has_pet()),
            BT.condition("in_combat", Cond.in_combat),
            BT.condition("not_kiting", Cond.not_kiting),
            BT.condition("pet_not_on_target", Cond.pet_not_attacking_target()),
            BT.action("send_pet", Act.pet_attack),
        }),
        -- 9. Pet freeze for shatter combo
        BT.sequence("pet_freeze", {
            BT.condition("has_pet", Cond.has_pet()),
            BT.condition("in_combat", Cond.in_combat),
            BT.condition("freeze_useful", Cond.pet_freeze_useful()),
            BT.condition("not_kiting", Cond.not_kiting),
            BT.action("freeze", Act.pet_freeze),
        }),
        -- 10. Pet passive during kite
        BT.sequence("pet_passive_kite", {
            BT.condition("has_pet", Cond.has_pet()),
            BT.condition("is_kiting", Cond.is_kiting),
            BT.action("recall_pet", Act.pet_passive),
        }),
    })
end

-- ---------------------------------------------------------------------------
-- GCD tree (PriorityBuilder, 75ms tick)
-- Always evaluates from top for preemption (interrupts, emergencies, etc.).
-- Priority numbers are index*10 to preserve the original source order exactly
-- (PriorityBuilder:build sorts ascending — priority_builder.lua:99).
-- ---------------------------------------------------------------------------
local function not_aoe_mode(bb) return not Cond.should_use_aoe(bb) end
local function not_moving(bb) return not Cond.player_is_moving(bb) end
local function moving_not_kiting(bb)
    return Cond.player_is_moving(bb) and not Cond.is_running_away(bb)
end
local function enemies_melee_or_emergency(bb)
    local count = tonumber(bb:get("combat.enemy_count_10yd", 0)) or 0
    if count >= 2 then return true end
    if count >= 1 and (tonumber(bb:get("player.health_pct", 1)) or 1) < 0.40 then return true end
    return false
end

local function build_gcd_root(blackboard)
    local builder = PriorityBuilder.new("MAGE", "FROST")

    -- 1. INTERRUPT: Counterspell
    builder:add_priority("counterspell", {
        Cond.gcd_ready,
        Cond.target_casting_interruptible,
        Cond.spell_ready("counterspell"),
    }, Act.queue_counterspell, nil, 10)

    -- 2. EMERGENCY: Ice Block (health < 15%)
    builder:add_priority("ice_block_emergency", {
        Cond.gcd_ready,
        Cond.health_below(0.15),
        Cond.spell_ready("ice_block", nil, "self"),
    }, Act.queue_ice_block, nil, 20)

    -- 3. EMERGENCY: Mana Shield (health < 30%, mana > 30%, not already active)
    builder:add_priority("mana_shield_emergency", {
        Cond.gcd_ready,
        Cond.health_below(0.30),
        Cond.mana_above(0.30),
        Cond.missing_mana_shield,
        Cond.spell_ready("mana_shield", nil, "self"),
    }, Act.queue_mana_shield, nil, 30)

    -- 4. EMERGENCY: Hard flee (all defensives exhausted, HP critical)
    builder:add_priority("emergency_escape", {
        Cond.gcd_ready,
        Cond.should_emergency_escape,
    }, Act.emergency_escape, nil, 40)

    -- 5. CC (PvE): Polymorph second hostile (2+ enemies, not AoE mode)
    builder:add_priority("polymorph_pve", {
        Cond.gcd_ready,
        Cond.level_at_least(8),
        Cond.hostile_count_at_least(2, 30),
        not_aoe_mode,
        Cond.spell_ready("polymorph"),
    }, Act.queue_polymorph, nil, 50)

    -- 5. CC (PvP): Polymorph secondary hostile (level 8+, 2+ enemies)
    builder:add_priority("polymorph_pvp", {
        Cond.gcd_ready,
        Cond.level_at_least(8),
        Cond.target_is_player,
        Cond.hostile_count_at_least(2, 30),
        Cond.spell_ready("polymorph"),
    }, Act.queue_polymorph, nil, 60)

    -- 6. ADD FINISH: Fire Blast low-HP secondary enemy
    builder:add_priority("finish_low_add", {
        Cond.gcd_ready,
        Cond.has_low_health_add,
        Cond.not_kiting,
        Cond.spell_ready("fire_blast"),
    }, Act.finish_low_add, nil, 70)

    -- 7. KILL-SECURE: Fire Blast (instant finish, 20yd range)
    builder:add_priority("fire_blast_kill", {
        Cond.gcd_ready,
        Cond.not_running_away,
        Cond.target_killable_instant,
        Cond.target_in_range(20),
        Cond.spell_ready("fire_blast"),
    }, Act.queue_fire_blast_kill, nil, 80)

    -- 7. KILL-SECURE: Ice Lance (instant finish, level 66+)
    builder:add_priority("ice_lance_kill", {
        Cond.gcd_ready,
        Cond.not_running_away,
        Cond.level_at_least(66),
        Cond.target_killable_instant,
        Cond.spell_ready("ice_lance"),
    }, Act.queue_ice_lance_frozen, nil, 90)

    -- 8. KITE: Frost Nova + start kite (2+ melee OR 1 melee + HP < 40%)
    builder:add_priority("frost_nova_kite", {
        Cond.gcd_ready,
        enemies_melee_or_emergency,
        Cond.not_kiting,
        Cond.spell_ready("frost_nova"),
    }, ActionLibrary.sequence({ Act.queue_frost_nova, Act.start_kite }), nil, 100)

    -- 9. KITE: Blink for instant distance while running away
    builder:add_priority("blink_kite", {
        Cond.gcd_ready,
        Cond.is_running_away,
        Cond.spell_ready("blink", nil, "self"),
    }, Act.queue_blink, nil, 110)

    -- 10. KITE FALLBACK: Cone of Cold (enemy in melee, nova on CD)
    builder:add_priority("cone_of_cold_kite", {
        Cond.gcd_ready,
        Cond.enemies_in_melee(1),
        Cond.spell_ready("cone_of_cold"),
    }, Act.queue_cone_of_cold, nil, 120)

    -- 11. SPELLSTEAL (level 70, target has magic buff)
    builder:add_priority("spellsteal", {
        Cond.gcd_ready,
        Cond.level_at_least(70),
        Cond.target_has_stealable_buff,
        Cond.mana_above(0.20),
        Cond.spell_ready("spellsteal"),
    }, Act.queue_spellsteal, nil, 130)

    -- 12. SHATTER: Ice Lance on frozen target (3x damage, level 66+)
    builder:add_priority("ice_lance_shatter", {
        Cond.gcd_ready,
        Cond.not_running_away,
        Cond.level_at_least(66),
        Cond.target_is_frozen,
        Cond.spell_ready("ice_lance"),
    }, Act.queue_ice_lance_frozen, nil, 140)

    -- 13. SHATTER: Fire Blast on frozen target (20yd range)
    builder:add_priority("fire_blast_shatter", {
        Cond.gcd_ready,
        Cond.not_running_away,
        Cond.target_is_frozen,
        Cond.target_in_range(20),
        Cond.spell_ready("fire_blast"),
    }, Act.queue_fire_blast, nil, 150)

    -- 14. PVP BURST: Frostbolt on frozen player (shatter combo)
    builder:add_priority("frostbolt_pvp_shatter", {
        Cond.gcd_ready,
        Cond.target_is_player,
        Cond.target_is_frozen,
        not_moving,
        Cond.spell_ready("frostbolt"),
    }, Act.queue_frostbolt, nil, 160)

    -- 15. AOE: Blizzard > Arcane Explosion > Cone of Cold (3+ enemies)
    builder:add_priority("aoe_rotation", {
        Cond.gcd_ready,
        Cond.should_use_aoe,
        Cond.not_kiting,
    }, ActionLibrary.selector({ Act.queue_blizzard, Act.queue_arcane_explosion, Act.queue_cone_of_cold }), nil, 170)

    -- 16. MANA: Use mana gem (mana < 40%)
    builder:add_priority("use_mana_gem", {
        Cond.gcd_ready,
        Cond.mana_below(0.40),
        Cond.has_mana_gem,
    }, Act.use_mana_gem, nil, 180)

    -- 17. MANA: Evocation (mana < 20%, safe)
    builder:add_priority("evocation", {
        Cond.gcd_ready,
        Cond.mana_below(0.20),
        Cond.safe_to_evocate,
        Cond.spell_ready("evocation", nil, "self"),
    }, Act.queue_evocation, nil, 190)

    -- 18. SUMMON: Water Elemental (level 50+, pet absent)
    builder:add_priority("summon_water_elemental", {
        Cond.gcd_ready,
        Cond.level_at_least(50),
        Cond.missing_water_elemental,
        not_moving,
        Cond.spell_ready("summon_water_elemental", nil, "self"),
    }, Act.queue_summon_water_elemental, nil, 200)

    -- 19. MOVEMENT: Fire Blast (moving but NOT kite-running — can't face target)
    builder:add_priority("fire_blast_moving", {
        Cond.gcd_ready,
        moving_not_kiting,
        Cond.target_in_range(20),
        Cond.spell_ready("fire_blast"),
    }, Act.queue_fire_blast, nil, 210)

    -- 20. MOVEMENT: Ice Lance (moving but NOT kite-running, level 66+)
    builder:add_priority("ice_lance_moving", {
        Cond.gcd_ready,
        Cond.level_at_least(66),
        moving_not_kiting,
        Cond.spell_ready("ice_lance"),
    }, Act.queue_ice_lance, nil, 220)

    -- 21. FILLER: Frostbolt (standing still)
    builder:add_priority("frostbolt", {
        Cond.gcd_ready,
        not_moving,
        Cond.spell_ready("frostbolt"),
    }, Act.queue_frostbolt, nil, 230)

    -- 22. FALLBACK: Fireball (levels 1-3 before Frostbolt)
    builder:add_priority("fireball_fallback", {
        Cond.gcd_ready,
        not_moving,
        Cond.spell_ready("fireball"),
    }, Act.queue_fireball, nil, 240)

    -- 23. NOOP
    builder:add_priority("fallback_noop", nil, Act.noop, nil, 250)

    return builder:build(blackboard)
end

-- ---------------------------------------------------------------------------
-- Profile lifecycle
-- ---------------------------------------------------------------------------

function Profile.build(blackboard, event_bus)
    local o = setmetatable({}, Profile)
    o.id = "mage_frost_tbc"
    o._combat_state = FrostCombatState:new(blackboard)
    o._kite_controller = KiteController:new(blackboard)
    o._pet_controller = PetController:new()
    blackboard:set("module.combat.pet_controller", o._pet_controller)
    o._maintenance = Runner:new(BT.cooldown("frost_maintenance_cd", 250,
        MaintenanceTree.build(), { key = "combat_frost_maintenance" }))
    o._off_gcd = Runner:new(BT.cooldown("frost_offgcd_cd", 75,
        build_off_gcd_root(), { key = "combat_frost_offgcd" }))
    o._gcd = Runner:new(BT.cooldown("frost_gcd_cd", 75,
        build_gcd_root(blackboard), { key = "combat_frost_gcd" }))
    blackboard:set("rotation.profile_id", o.id)
    blackboard:set("module.combat.combat_range", 28)
    event_bus:publish("rotation:profile_loaded", {
        rotation_id = o.id,
        class_id = 8,
        spec_id = 2,
    })
    return o
end

function Profile:tick_maintenance(blackboard)
    return self._maintenance:tick(blackboard)
end

function Profile:tick_off_gcd(blackboard)
    self._combat_state:refresh(blackboard)
    self._kite_controller:update(blackboard)
    return self._off_gcd:tick(blackboard)
end

function Profile:tick_gcd(blackboard)
    local status = self._gcd:tick(blackboard)
    if status == "FAILURE" then
        local now = blackboard:get("system.now_ms", 0)
        -- Only log when the GCD tree actually evaluated (not just cooldown-throttled)
        local cd_last = blackboard:get("module.bt.cooldown.combat_frost_gcd", 0)
        local actually_evaluated = (now - cd_last) > 5
        if actually_evaluated and (not self._last_gcd_diag_ms or (now - self._last_gcd_diag_ms) >= 2000) then
            self._last_gcd_diag_ms = now
            if core and type(core.log) == "function" then
                local catalog = blackboard:get("module.combat.catalog")
                local fb_id = catalog and catalog:resolve_best_rank("frostbolt")
                local player = blackboard:get("player.object")
                local target = blackboard:get("combat.target")
                -- Test is_spell_castable directly
                local helper = spell_helper or nil
                if not helper then
                    local ok_h, h = pcall(require, "common/utility/spell_helper")
                    if ok_h then helper = h end
                end
                local castable_str = "no_helper"
                if helper and type(helper.is_spell_castable) == "function" and fb_id then
                    local ok1, v1 = pcall(helper.is_spell_castable, fb_id, player, target, true, true)
                    local ok2, v2 = pcall(helper.is_spell_castable, helper, fb_id, player, target, true, true)
                    castable_str = string.format("plain=%s/%s method=%s/%s",
                        tostring(ok1), tostring(v1), tostring(ok2), tostring(v2))
                end
                local los_str = "no_helper"
                if helper and type(helper.is_spell_in_line_of_sight) == "function" and fb_id then
                    local ok3, v3 = pcall(helper.is_spell_in_line_of_sight, fb_id, player, target)
                    local ok4, v4 = pcall(helper.is_spell_in_line_of_sight, helper, fb_id, player, target)
                    los_str = string.format("plain=%s/%s method=%s/%s",
                        tostring(ok3), tostring(v3), tostring(ok4), tostring(v4))
                end
                pcall(core.log, string.format(
                    "[FrostGCD] fb_id=%s castable=[%s] los=[%s]",
                    tostring(fb_id), castable_str, los_str))
            end
        end
    end
    return status
end

function Profile:reset()
    self._maintenance:reset()
    self._off_gcd:reset()
    self._gcd:reset()
    self._combat_state:reset()
    self._kite_controller:reset()
    if self._pet_controller then
        self._pet_controller:reset()
    end
end

return Profile
