local BT = require("core/bt/factory")
local Runner = require("core/bt/runner")
local Cond = require("modules/combat/profiles/warlock/affliction_conditions")
local Act = require("modules/combat/profiles/warlock/affliction_actions")
local MaintenanceTree = require("modules/combat/profiles/warlock/maintenance_tree")
local PetController = require("modules/combat/profiles/warlock/pet_controller")
local PriorityBuilder = require("kernel/lib/priority_builder")
local SharedConditions = require("modules/combat/condition_library")
local ActionLibrary = require("modules/combat/action_library")

local Profile = {}
Profile.__index = Profile

-- ---------------------------------------------------------------------------
-- Off-GCD tree (selector, 75ms tick)
-- Voidwalker summon + attack. MVP only -- see pet_controller.lua for the
-- Torment/threat deferral note.
-- ---------------------------------------------------------------------------
local function build_off_gcd_root()
    return BT.selector("warlock_affliction_off_gcd", {
        -- Summon gates: out of combat (a 10s summon cast mid-combat stalls the
        -- chase) AND "usable" (trained + Soul Shard reagent present via
        -- core.spell_book.is_usable_spell) — "known" alone retried forever with
        -- zero shards. When it can't summon, the selector falls through and
        -- combat proceeds pet-less.
        BT.sequence("summon_voidwalker", {
            BT.condition("missing_voidwalker", Cond.missing_voidwalker),
            BT.condition("out_of_combat", SharedConditions.not_in_combat),
            BT.condition("summon_voidwalker_usable", SharedConditions.spell_available("summon_voidwalker", "usable")),
            BT.condition("summon_voidwalker_ready", SharedConditions.spell_ready("summon_voidwalker", nil, "self")),
            BT.action("queue_summon_voidwalker", Act.summon_voidwalker),
        }),
        BT.sequence("pet_attack", {
            BT.condition("has_voidwalker", Cond.has_voidwalker),
            BT.condition("target_valid", SharedConditions.target_valid),
            BT.condition("pet_not_on_target", SharedConditions.pet_not_attacking_target()),
            BT.action("send_pet", ActionLibrary.pet_attack()),
        }),
    })
end

-- ---------------------------------------------------------------------------
-- GCD tree (PriorityBuilder, 75ms tick)
-- Every DoT/filler entry is gated by spell_available (trained-status), so an
-- untrained spell auto-skips and the rotation falls through cleanly --
-- graceful 1-70 scaling with no hand-typed level checks.
-- ---------------------------------------------------------------------------
local function build_gcd_root(blackboard)
    local builder = PriorityBuilder.new("WARLOCK", "AFFLICTION")

    -- 1-3. DoT maintenance, strict priority order: Corruption > Curse of
    -- Agony > Immolate. Each only fires while its own debuff is missing from
    -- the target AND the spell is trained.
    builder:add_priority("corruption_maintain", {
        SharedConditions.gcd_ready,
        SharedConditions.target_valid,
        Cond.target_missing_dot("corruption"),
        SharedConditions.spell_available("corruption"),
    }, Act.cast_corruption, nil, 10)

    builder:add_priority("curse_of_agony_maintain", {
        SharedConditions.gcd_ready,
        SharedConditions.target_valid,
        Cond.target_missing_dot("curse_of_agony"),
        SharedConditions.spell_available("curse_of_agony"),
    }, Act.cast_curse_of_agony, nil, 20)

    builder:add_priority("immolate_maintain", {
        SharedConditions.gcd_ready,
        SharedConditions.target_valid,
        Cond.target_missing_dot("immolate"),
        SharedConditions.spell_available("immolate"),
    }, Act.cast_immolate, nil, 30)

    -- 4. SUSTAIN: Drain Life when low health (drain-tank survivability).
    builder:add_priority("drain_life_sustain", {
        SharedConditions.gcd_ready,
        SharedConditions.target_valid,
        SharedConditions.health_below(0.40),
        SharedConditions.spell_available("drain_life"),
    }, Act.cast_drain_life, nil, 40)

    -- 4b. RECOVERY: Drain Life in the low-mana/low-HP wedge. Below 50% HP Life
    -- Tap is blocked (health_above(0.50)) and above 40% HP drain_life_sustain is
    -- blocked (health_below(0.40)); with mana under 30% the lock wanded forever.
    -- Drain Life converts enemy HP into ours, un-wedging both sustain gates.
    -- Wand (priority 900) remains the final fallback when Drain Life is untrained.
    builder:add_priority("drain_life_recovery", {
        SharedConditions.gcd_ready,
        SharedConditions.target_valid,
        SharedConditions.mana_below(0.30),
        SharedConditions.health_below(0.50),
        SharedConditions.spell_available("drain_life"),
    }, Act.cast_drain_life, nil, 45)

    -- 5. SUSTAIN: Life Tap when mana is low and health can afford it.
    builder:add_priority("life_tap_sustain", {
        SharedConditions.gcd_ready,
        SharedConditions.mana_below(0.30),
        SharedConditions.health_above(0.50),
        SharedConditions.spell_available("life_tap"),
    }, Act.cast_life_tap, nil, 50)

    -- 6. FILLER: Shadow Bolt when mana-rich and DoTs/sustain didn't fire.
    builder:add_priority("shadow_bolt_filler", {
        SharedConditions.gcd_ready,
        SharedConditions.target_valid,
        SharedConditions.mana_above(0.40),
        SharedConditions.spell_available("shadow_bolt"),
    }, Act.cast_shadow_bolt, nil, 60)

    -- 7. FINISHER: wand (Shoot) -- lowest priority, always available as long
    -- as a valid target exists. Not gated on gcd_ready: wand auto-attack is
    -- not on the global cooldown in-game.
    builder:add_priority("wand_finish", {
        SharedConditions.target_valid,
    }, Act.cast_shoot, nil, 900)

    -- 8. NOOP
    builder:add_priority("fallback_noop", nil, Act.noop, nil, 1000)

    return builder:build(blackboard)
end

-- ---------------------------------------------------------------------------
-- Profile lifecycle
-- ---------------------------------------------------------------------------

function Profile.build(blackboard, event_bus)
    local o = setmetatable({}, Profile)
    o.id = "warlock_affliction_tbc"
    o._pet_controller = PetController:new()
    blackboard:set("module.combat.pet_controller", o._pet_controller)
    o._maintenance = Runner:new(BT.cooldown("warlock_maintenance_cooldown", 250,
        MaintenanceTree.build(), { key = "combat_warlock_maintenance" }))
    o._off_gcd = Runner:new(BT.cooldown("warlock_off_gcd_cooldown", 75,
        build_off_gcd_root(), { key = "combat_warlock_offgcd" }))
    o._gcd = Runner:new(BT.cooldown("warlock_gcd_cooldown", 75,
        build_gcd_root(blackboard), { key = "combat_warlock_gcd" }))
    blackboard:set("rotation.profile_id", o.id)
    -- Warlock is a caster; leveling combat range mirrors Mage (28yd), not melee.
    blackboard:set("module.combat.combat_range", 28)
    event_bus:publish("rotation:profile_loaded", {
        rotation_id = o.id,
        class_id = 9,
        spec_id = 0,
    })
    return o
end

function Profile:tick_maintenance(blackboard)
    return self._maintenance:tick(blackboard)
end

function Profile:tick_off_gcd(blackboard)
    self._pet_controller:refresh(blackboard)
    return self._off_gcd:tick(blackboard)
end

function Profile:tick_gcd(blackboard)
    return self._gcd:tick(blackboard)
end

function Profile:reset()
    self._maintenance:reset()
    self._off_gcd:reset()
    self._gcd:reset()
    self._pet_controller:reset()
end

return Profile
