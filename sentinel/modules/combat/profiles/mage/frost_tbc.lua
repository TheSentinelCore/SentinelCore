local BT = require("core/bt/factory")
local Runner = require("core/bt/runner")
local Cond = require("modules/combat/profiles/mage/frost_conditions")
local Act = require("modules/combat/profiles/mage/frost_actions")
local MaintenanceTree = require("modules/combat/profiles/mage/maintenance_tree")
local AoeTree = require("modules/combat/profiles/mage/aoe_tree")
local FrostCombatState = require("modules/combat/profiles/mage/frost_combat_state")
local KiteController = require("modules/combat/profiles/mage/kite_controller")
local PetController = require("modules/combat/profiles/mage/pet_controller")
local Status = require("core/bt/status")

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
-- GCD tree (priority_selector, 75ms tick)
-- Always evaluates from top for preemption (interrupts, emergencies, etc.)
-- ---------------------------------------------------------------------------
local function build_gcd_root()
    return BT.priority_selector("frost_mage_gcd", {
        -- 1. INTERRUPT: Counterspell
        BT.sequence("counterspell", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("target_casting", Cond.target_casting_interruptible),
            BT.condition("counterspell_ready", Cond.spell_ready("counterspell")),
            BT.action("queue_counterspell", Act.queue_counterspell),
        }),
        -- 2. EMERGENCY: Ice Block (health < 15%)
        BT.sequence("ice_block_emergency", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("health_below_15", Cond.health_below(0.15)),
            BT.condition("ice_block_ready", Cond.spell_ready("ice_block", nil, "self")),
            BT.action("queue_ice_block", Act.queue_ice_block),
        }),
        -- 3. EMERGENCY: Mana Shield (health < 30%, mana > 30%, not already active)
        BT.sequence("mana_shield_emergency", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("health_below_30", Cond.health_below(0.30)),
            BT.condition("mana_above_30", Cond.mana_above(0.30)),
            BT.condition("missing_mana_shield", Cond.missing_mana_shield),
            BT.condition("mana_shield_ready", Cond.spell_ready("mana_shield", nil, "self")),
            BT.action("queue_mana_shield", Act.queue_mana_shield),
        }),
        -- 4. CC (PvE): Polymorph second hostile (2+ enemies, not AoE mode)
        BT.sequence("polymorph_pve", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("level_at_least_8", Cond.level_at_least(8)),
            BT.condition("2_plus_enemies", Cond.hostile_count_at_least(2, 30)),
            BT.condition("not_aoe_mode", function(bb) return not Cond.should_use_aoe(bb) end),
            BT.condition("polymorph_ready", Cond.spell_ready("polymorph")),
            BT.action("queue_polymorph", Act.queue_polymorph),
        }),
        -- 5. CC (PvP): Polymorph secondary hostile (level 8+, 2+ enemies)
        BT.sequence("polymorph_pvp", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("level_at_least_8", Cond.level_at_least(8)),
            BT.condition("target_is_player", Cond.target_is_player),
            BT.condition("2_plus_enemies", Cond.hostile_count_at_least(2, 30)),
            BT.condition("polymorph_ready", Cond.spell_ready("polymorph")),
            BT.action("queue_polymorph", Act.queue_polymorph),
        }),
        -- 6. KILL-SECURE: Fire Blast (instant finish, 20yd range)
        BT.sequence("fire_blast_kill", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("not_running_away", Cond.not_running_away),
            BT.condition("target_killable", Cond.target_killable_instant),
            BT.condition("in_fire_blast_range", Cond.target_in_range(20)),
            BT.condition("fire_blast_ready", Cond.spell_ready("fire_blast")),
            BT.action("queue_fire_blast_kill", Act.queue_fire_blast_kill),
        }),
        -- 7. KILL-SECURE: Ice Lance (instant finish, level 66+)
        BT.sequence("ice_lance_kill", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("not_running_away", Cond.not_running_away),
            BT.condition("level_at_least_66", Cond.level_at_least(66)),
            BT.condition("target_killable", Cond.target_killable_instant),
            BT.condition("ice_lance_ready", Cond.spell_ready("ice_lance")),
            BT.action("queue_ice_lance_kill", Act.queue_ice_lance_frozen),
        }),
        -- 8. KITE: Frost Nova + start kite (enemy in melee, not already kiting)
        BT.sequence("frost_nova_kite", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("enemies_melee", Cond.enemies_in_melee(1)),
            BT.condition("not_kiting", Cond.not_kiting),
            BT.condition("frost_nova_ready", Cond.spell_ready("frost_nova")),
            BT.action("queue_frost_nova", Act.queue_frost_nova),
            BT.action("start_kite", Act.start_kite),
        }),
        -- 9. KITE: Blink for instant distance while running away
        BT.sequence("blink_kite", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("is_running_away", Cond.is_running_away),
            BT.condition("blink_ready", Cond.spell_ready("blink", nil, "self")),
            BT.action("queue_blink", Act.queue_blink),
        }),
        -- 10. KITE FALLBACK: Cone of Cold (enemy in melee, nova on CD)
        BT.sequence("cone_of_cold_kite", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("enemies_melee", Cond.enemies_in_melee(1)),
            BT.condition("cone_of_cold_ready", Cond.spell_ready("cone_of_cold")),
            BT.action("queue_cone_of_cold", Act.queue_cone_of_cold),
        }),
        -- 11. SPELLSTEAL (level 70, target has magic buff)
        BT.sequence("spellsteal", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("level_70", Cond.level_at_least(70)),
            BT.condition("target_has_stealable", Cond.target_has_stealable_buff),
            BT.condition("mana_above_20", Cond.mana_above(0.20)),
            BT.condition("spellsteal_ready", Cond.spell_ready("spellsteal")),
            BT.action("queue_spellsteal", Act.queue_spellsteal),
        }),
        -- 12. SHATTER: Ice Lance on frozen target (3x damage, level 66+)
        BT.sequence("ice_lance_shatter", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("not_running_away", Cond.not_running_away),
            BT.condition("level_at_least_66", Cond.level_at_least(66)),
            BT.condition("target_frozen", Cond.target_is_frozen),
            BT.condition("ice_lance_ready", Cond.spell_ready("ice_lance")),
            BT.action("queue_ice_lance_frozen", Act.queue_ice_lance_frozen),
        }),
        -- 13. SHATTER: Fire Blast on frozen target (20yd range)
        BT.sequence("fire_blast_shatter", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("not_running_away", Cond.not_running_away),
            BT.condition("target_frozen", Cond.target_is_frozen),
            BT.condition("in_fire_blast_range", Cond.target_in_range(20)),
            BT.condition("fire_blast_ready", Cond.spell_ready("fire_blast")),
            BT.action("queue_fire_blast", Act.queue_fire_blast),
        }),
        -- 14. PVP BURST: Frostbolt on frozen player (shatter combo)
        BT.sequence("frostbolt_pvp_shatter", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("target_is_player", Cond.target_is_player),
            BT.condition("target_frozen", Cond.target_is_frozen),
            BT.condition("not_moving", function(bb) return not Cond.player_is_moving(bb) end),
            BT.condition("frostbolt_ready", Cond.spell_ready("frostbolt")),
            BT.action("queue_frostbolt", Act.queue_frostbolt),
        }),
        -- 15. AOE: Blizzard > Arcane Explosion > Cone of Cold (3+ enemies)
        BT.sequence("aoe_rotation", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("should_aoe", Cond.should_use_aoe),
            BT.condition("not_kiting", Cond.not_kiting),
            BT.selector("aoe_spells", {
                BT.sequence("blizzard", {
                    BT.condition("blizzard_ready", Cond.spell_ready("blizzard")),
                    BT.action("queue_blizzard", Act.queue_blizzard),
                }),
                BT.sequence("arcane_explosion", {
                    BT.condition("ae_ready", Cond.spell_ready("arcane_explosion")),
                    BT.action("queue_ae", Act.queue_arcane_explosion),
                }),
                BT.sequence("cone_of_cold_aoe", {
                    BT.condition("coc_ready", Cond.spell_ready("cone_of_cold")),
                    BT.action("queue_coc", Act.queue_cone_of_cold),
                }),
            }),
        }),
        -- 16. MANA: Use mana gem (mana < 40%)
        BT.sequence("use_mana_gem", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("mana_below_40", Cond.mana_below(0.40)),
            BT.condition("has_mana_gem", Cond.has_mana_gem),
            BT.action("use_mana_gem", Act.use_mana_gem),
        }),
        -- 17. MANA: Evocation (mana < 20%, safe)
        BT.sequence("evocation", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("mana_below_20", Cond.mana_below(0.20)),
            BT.condition("safe_to_evocate", Cond.safe_to_evocate),
            BT.condition("evocation_ready", Cond.spell_ready("evocation", nil, "self")),
            BT.action("queue_evocation", Act.queue_evocation),
        }),
        -- 18. SUMMON: Water Elemental (level 50+, pet absent)
        BT.sequence("summon_water_elemental", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("level_at_least_50", Cond.level_at_least(50)),
            BT.condition("missing_water_elemental", Cond.missing_water_elemental),
            BT.condition("not_moving", function(bb) return not Cond.player_is_moving(bb) end),
            BT.condition("summon_ready", Cond.spell_ready("summon_water_elemental", nil, "self")),
            BT.action("queue_summon", Act.queue_summon_water_elemental),
        }),
        -- 19. MOVEMENT: Fire Blast (moving but NOT kite-running — can't face target)
        BT.sequence("fire_blast_moving", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("moving_not_kiting", function(bb)
                return Cond.player_is_moving(bb) and not Cond.is_running_away(bb)
            end),
            BT.condition("in_fire_blast_range", Cond.target_in_range(20)),
            BT.condition("fire_blast_ready", Cond.spell_ready("fire_blast")),
            BT.action("queue_fire_blast", Act.queue_fire_blast),
        }),
        -- 20. MOVEMENT: Ice Lance (moving but NOT kite-running, level 66+)
        BT.sequence("ice_lance_moving", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("level_at_least_66", Cond.level_at_least(66)),
            BT.condition("moving_not_kiting", function(bb)
                return Cond.player_is_moving(bb) and not Cond.is_running_away(bb)
            end),
            BT.condition("ice_lance_ready", Cond.spell_ready("ice_lance")),
            BT.action("queue_ice_lance", Act.queue_ice_lance),
        }),
        -- 21. FILLER: Frostbolt (standing still)
        BT.sequence("frostbolt", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("not_moving", function(bb) return not Cond.player_is_moving(bb) end),
            BT.condition("frostbolt_ready", Cond.spell_ready("frostbolt")),
            BT.action("queue_frostbolt", Act.queue_frostbolt),
        }),
        -- 22. FALLBACK: Fireball (levels 1-3 before Frostbolt)
        BT.sequence("fireball_fallback", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("not_moving", function(bb) return not Cond.player_is_moving(bb) end),
            BT.condition("fireball_ready", Cond.spell_ready("fireball")),
            BT.action("queue_fireball", Act.queue_fireball),
        }),
        -- 23. NOOP
        BT.action("fallback_noop", Act.noop),
    })
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
        build_gcd_root(), { key = "combat_frost_gcd" }))
    o._aoe_tree = Runner:new(AoeTree.build())
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
    return self._gcd:tick(blackboard)
end

function Profile:reset()
    self._maintenance:reset()
    self._off_gcd:reset()
    self._gcd:reset()
    self._aoe_tree:reset()
    self._combat_state:reset()
    self._kite_controller:reset()
    if self._pet_controller then
        self._pet_controller:reset()
    end
end

function Profile:get_pull_strategy(bb)
    local spot = bb:get("module.grind.current_spot")
    if spot and spot.aoe_enabled then
        local level = bb:get("player.level", 1)
        if level >= 20 then
            return "aoe"
        end
    end
    return "single"
end

function Profile:tick_pull(bb, _target)
    if self:get_pull_strategy(bb) == "aoe" then
        return self._aoe_tree:tick(bb)
    end
    local result = Act.queue_frostbolt(bb)
    if result ~= Status.SUCCESS then
        result = Act.queue_fireball(bb)
    end
    return result
end

function Profile:prepare_rest(bb)
    self._maintenance:tick(bb)
    -- Stay in rest when no water and mana isn't full — spirit regen will
    -- eventually allow conjure_water to fire from the maintenance tree.
    local water_count = bb:get("module.grind.water_count", 0)
    if water_count == 0 and bb:get("player.mana_pct", 1) < 0.95 then
        return Status.RUNNING
    end
    -- Maintenance FAILURE just means "nothing to conjure/buff right now"
    -- (cooldown throttled, fully stocked, or bags full). The rest.lua
    -- prepare_rest action handles the is_casting gate separately.
    return Status.SUCCESS
end

return Profile
