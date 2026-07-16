local BT = require("core/bt/factory")
local Runner = require("core/bt/runner")
local Cond = require("modules/combat/profiles/paladin/retribution_conditions")
local Act = require("modules/combat/profiles/paladin/retribution_actions")
local MaintenanceTree = require("modules/combat/profiles/paladin/maintenance_tree")
local PriorityBuilder = require("modules/combat/priority_builder")
local SharedConditions = require("modules/combat/condition_library")
local SharedActions = require("modules/combat/action_library")

local Profile = {}
Profile.__index = Profile

local function build_off_gcd_root()
    return BT.cooldown("ret_off_gcd_cooldown", 75, BT.selector("ret_paladin_off_gcd", {
        BT.sequence("use_avenging_wrath", {
            BT.condition("burst_context", Cond.burst_context),
            BT.condition("target_valid", Cond.target_valid),
            BT.condition("health_above_40", Cond.health_above(0.40)),
            BT.condition("avenging_wrath_ready", Cond.spell_ready("avenging_wrath", nil, "self")),
            BT.action("queue_avenging_wrath", Act.queue_avenging_wrath),
        }),
    }), { key = "combat_ret_offgcd" })
end

local function build_gcd_root()
    return BT.cooldown("ret_gcd_cooldown", 75, BT.selector("ret_paladin_gcd", {
        BT.sequence("hammer_of_justice_interrupt", {
            BT.condition("target_valid", Cond.target_valid),
            BT.condition("in_judgement_range", Cond.in_judgement_range),
            BT.condition("target_casting_interruptible", Cond.target_casting_interruptible),
            BT.condition("hoj_ready", Cond.spell_ready("hammer_of_justice")),
            BT.action("queue_hammer_of_justice", Act.queue_hammer_of_justice),
        }),
        BT.sequence("apply_seal_before_combat", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("target_valid", Cond.target_valid),
            BT.condition("baseline_seal_missing", Cond.baseline_seal_missing),
            BT.condition("seal_of_blood_ready", Cond.spell_ready("seal_of_blood", nil, "self")),
            BT.action("queue_seal_of_blood_before_combat", Act.queue_seal_of_blood),
        }),
        BT.sequence("seal_twist_prime", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("target_valid", Cond.target_valid),
            BT.condition("in_melee", Cond.in_melee),
            BT.condition("twist_enabled", Cond.twist_enabled),
            BT.condition("twist_window_open", Cond.twist_window_open),
            BT.condition("soc_ready", Cond.spell_ready("seal_of_command", "lowest", "self")),
            BT.action("queue_soc_r1", Act.queue_seal_of_command_rank1),
        }),
        BT.sequence("hammer_of_wrath_execute", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("target_valid", Cond.target_valid),
            BT.condition("not_twisting", Cond.not_twisting),
            BT.condition("target_execute", Cond.target_execute),
            BT.condition("how_ready", Cond.spell_ready("hammer_of_wrath")),
            BT.action("queue_hammer_of_wrath", Act.queue_hammer_of_wrath),
        }),
        BT.sequence("seal_of_blood_reseal_after_judgement", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("in_combat_context", Cond.in_combat_context),
            BT.condition("desired_blood", Cond.desired_seal_is_blood),
            BT.condition("after_judgement_reseal", Cond.after_judgement_reseal),
            BT.condition("blood_not_active", Cond.blood_not_active),
            BT.condition("seal_of_blood_ready", Cond.spell_ready("seal_of_blood", nil, "self")),
            BT.action("queue_seal_of_blood_after_judgement", Act.queue_seal_of_blood),
        }),
        BT.sequence("seal_twist_recover", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("in_combat_context", Cond.in_combat_context),
            BT.condition("desired_blood", Cond.desired_seal_is_blood),
            BT.condition("twist_reseal_pending", Cond.twist_reseal_pending),
            BT.condition("blood_not_active", Cond.blood_not_active),
            BT.condition("seal_of_blood_ready", Cond.spell_ready("seal_of_blood", nil, "self")),
            BT.action("queue_seal_of_blood_after_twist", Act.queue_seal_of_blood),
        }),
        BT.sequence("seal_of_blood_maintain", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("in_combat_context", Cond.in_combat_context),
            BT.condition("target_valid", Cond.target_valid),
            BT.condition("desired_blood", Cond.desired_seal_is_blood),
            BT.condition("blood_not_active", Cond.blood_not_active),
            BT.condition("not_twisting", Cond.not_twisting),
            BT.condition("seal_of_blood_ready", Cond.spell_ready("seal_of_blood", nil, "self")),
            BT.action("queue_seal_of_blood", Act.queue_seal_of_blood),
        }),
        BT.sequence("seal_of_command_aoe_maintain", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("in_combat_context", Cond.in_combat_context),
            BT.condition("target_valid", Cond.target_valid),
            BT.condition("aoe_mode", Cond.aoe_mode),
            BT.condition("desired_command", Cond.desired_seal_is_command),
            BT.condition("command_not_active", Cond.command_not_active),
            BT.condition("seal_of_command_ready", Cond.spell_ready("seal_of_command", nil, "self")),
            BT.action("queue_seal_of_command", Act.queue_seal_of_command),
        }),
        BT.sequence("judgement", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("target_valid", Cond.target_valid),
            BT.condition("active_seal_present", Cond.active_seal_present),
            BT.condition("in_judgement_range", Cond.in_judgement_range),
            BT.condition("judgement_ready", Cond.spell_ready("judgement")),
            BT.action("queue_judgement", Act.queue_judgement),
        }),
        BT.sequence("crusader_strike", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("target_valid", Cond.target_valid),
            BT.condition("in_melee", Cond.in_melee),
            BT.condition("cs_ready", Cond.spell_ready("crusader_strike")),
            BT.action("queue_crusader_strike", Act.queue_crusader_strike),
        }),
        BT.sequence("consecration", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("enemy_count_two", Cond.enemy_count_at_least(2)),
            BT.condition("mana_above_35", Cond.mana_above(0.35)),
            BT.condition("consecration_ready", Cond.spell_ready("consecration", nil, "self")),
            BT.action("queue_consecration", Act.queue_consecration),
        }),
        BT.action("fallback_noop", Act.noop),
    }), { key = "combat_ret_gcd" })
end

local function build_gcd_root_dsl(blackboard)
    local builder = PriorityBuilder.new("PALADIN", "RETRIBUTION")
    builder:add_priority("hammer_of_justice_interrupt", {
        SharedConditions.target_valid,
        Cond.in_judgement_range,
        Cond.target_casting_interruptible,
        Cond.spell_ready("hammer_of_justice"),
    }, Act.queue_hammer_of_justice, nil, 10)
    builder:add_priority("apply_seal_before_combat", {
        Cond.gcd_ready,
        Cond.target_valid,
        Cond.baseline_seal_missing,
        Cond.spell_ready("seal_of_blood", nil, "self"),
    }, function(blackboard) return Act.queue_seal_of_blood(blackboard) end, nil, 15)
    builder:add_priority("seal_twist_prime", {
        Cond.gcd_ready,
        Cond.target_valid,
        Cond.in_melee,
        Cond.twist_enabled,
        Cond.twist_window_open,
        Cond.spell_ready("seal_of_command", "lowest", "self"),
    }, Act.queue_seal_of_command_rank1, nil, 20)
    builder:add_priority("hammer_of_wrath_execute", {
        Cond.gcd_ready,
        Cond.target_valid,
        Cond.not_twisting,
        Cond.target_execute,
        Cond.spell_ready("hammer_of_wrath"),
    }, Act.queue_hammer_of_wrath, nil, 30)
    builder:add_priority("seal_of_blood_reseal_after_judgement", {
        Cond.gcd_ready,
        Cond.in_combat_context,
        Cond.desired_seal_is_blood,
        Cond.after_judgement_reseal,
        Cond.blood_not_active,
        Cond.spell_ready("seal_of_blood", nil, "self"),
    }, Act.queue_seal_of_blood, nil, 40)
    builder:add_priority("seal_twist_recover", {
        Cond.gcd_ready,
        Cond.in_combat_context,
        Cond.desired_seal_is_blood,
        Cond.twist_reseal_pending,
        Cond.blood_not_active,
        Cond.spell_ready("seal_of_blood", nil, "self"),
    }, Act.queue_seal_of_blood, nil, 50)
    builder:add_priority("seal_of_blood_maintain", {
        Cond.gcd_ready,
        Cond.in_combat_context,
        Cond.target_valid,
        Cond.desired_seal_is_blood,
        Cond.blood_not_active,
        Cond.not_twisting,
        Cond.spell_ready("seal_of_blood", nil, "self"),
    }, Act.queue_seal_of_blood, nil, 60)
    builder:add_priority("seal_of_command_aoe_maintain", {
        Cond.gcd_ready,
        Cond.in_combat_context,
        Cond.target_valid,
        Cond.aoe_mode,
        Cond.desired_seal_is_command,
        Cond.command_not_active,
        Cond.spell_ready("seal_of_command", nil, "self"),
    }, Act.queue_seal_of_command, nil, 70)
    builder:add_priority("judgement", {
        Cond.gcd_ready,
        Cond.target_valid,
        Cond.active_seal_present,
        Cond.in_judgement_range,
        Cond.spell_ready("judgement"),
    }, Act.queue_judgement, nil, 80)
    builder:add_priority("crusader_strike", {
        Cond.gcd_ready,
        Cond.target_valid,
        Cond.in_melee,
        Cond.spell_ready("crusader_strike"),
    }, Act.queue_crusader_strike, nil, 90)
    builder:add_priority("consecration", {
        Cond.gcd_ready,
        Cond.enemy_count_at_least(2),
        Cond.mana_above(0.35),
        Cond.spell_ready("consecration", nil, "self"),
    }, Act.queue_consecration, nil, 100)
    builder:add_priority("fallback_noop", nil, Act.noop, nil, 1000)
    return BT.cooldown("ret_gcd_cooldown_dsl", 75, builder:build(blackboard), { key = "combat_ret_gcd_dsl" })
end

function Profile.build(blackboard, event_bus)
    local o = setmetatable({}, Profile)
    o.id = "paladin_retribution_tbc"
    o._maintenance = Runner:new(BT.cooldown("ret_maintenance_cooldown", 250, MaintenanceTree.build(), { key = "combat_ret_maintenance" }))
    o._off_gcd = Runner:new(build_off_gcd_root())
    local engine = blackboard:get("module.combat.rotation_engine", "legacy")
    local gcd_root = engine == "dsl" and build_gcd_root_dsl(blackboard) or build_gcd_root()
    o._gcd = Runner:new(gcd_root)
    blackboard:set("rotation.profile_id", o.id)
    event_bus:publish("rotation:profile_loaded", {
        rotation_id = o.id,
        class_id = 2,
        spec_id = 0,
    })
    return o
end

function Profile:tick_maintenance(blackboard)
    return self._maintenance:tick(blackboard)
end

function Profile:tick_off_gcd(blackboard)
    return self._off_gcd:tick(blackboard)
end

function Profile:tick_gcd(blackboard)
    return self._gcd:tick(blackboard)
end

function Profile:reset()
    self._maintenance:reset()
    self._off_gcd:reset()
    self._gcd:reset()
end

return Profile
