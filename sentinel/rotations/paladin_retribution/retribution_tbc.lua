local API = require("rotations/paladin_retribution/sentinel_api")

-- The kernel-published BT library (§10 `Sentinel.bt`), late-bound: a tree built before the kernel
-- publishes still resolves once it has, and `require("core/bt/factory")` is a cross-package require
-- the audit refuses.
local BT = setmetatable({}, { __index = function(_, k) return API.bt and API.bt[k] or nil end })
-- The tree RUNNER, not a node constructor -- `Sentinel.bt.Runner`. Each of the three trees below is
-- wrapped in one.
-- Forwards `new` explicitly rather than proxying through `__index`: `Runner:new(root)` would pass
-- THIS table as `self`, and the real constructor uses its own table as the instance metatable.
local Runner = {
    new = function(_, root) return API.bt.Runner:new(root) end,
}
local Cond = require("rotations/paladin_retribution/retribution_conditions")
local Act = require("rotations/paladin_retribution/retribution_actions")
local MaintenanceTree = require("rotations/paladin_retribution/maintenance_tree")

-- `Sentinel.rotation` is the promoted PriorityBuilder (ADR §5.4). Resolved live so the plugin does
-- not capture nil if it loads before the kernel publishes.
--
-- The old profile required `kernel/lib/priority_builder` directly. That is the SAME OBJECT --
-- `kernel/api.lua:209` publishes exactly that module as `Sentinel.rotation` -- so this is a route
-- change, not a library swap.
local PriorityBuilder = setmetatable({}, { __index = function(_, k)
    return API.rotation and API.rotation[k] or nil
end })

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

local function build_gcd_root(blackboard)
    local builder = PriorityBuilder.new("PALADIN", "RETRIBUTION")
    -- `SharedConditions.target_valid` from `modules/combat/condition_library` used to sit here,
    -- alongside `Cond.target_valid` on every other priority. The two are the SAME FUNCTION BODY --
    -- both read `player_and_target` and `safe_call(target, "is_dead")` with the identical
    -- fail-open `not ok_dead or dead ~= true` -- so collapsing onto the package's own copy removes
    -- a cross-package require without changing an answer. `condition_library` keeps its other
    -- callers; nothing is orphaned.
    builder:add_priority("hammer_of_justice_interrupt", {
        Cond.target_valid,
        Cond.in_judgement_range,
        Cond.target_casting_interruptible,
        Cond.spell_ready("hammer_of_justice"),
    }, Act.queue_hammer_of_justice, nil, 10)
    -- Level-aware: queues whichever seal the character actually knows
    -- (blood > command > righteousness). Hardcoding Seal of Blood here meant no
    -- Paladin below level 64 ever put up a seal, which killed judgement too.
    builder:add_priority("apply_seal_before_combat", {
        Cond.gcd_ready,
        Cond.target_valid,
        Cond.baseline_seal_missing,
        Cond.primary_seal_castable,
    }, Act.queue_desired_seal, nil, 15)
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
    builder:add_priority("seal_of_righteousness_maintain", {
        Cond.gcd_ready,
        Cond.in_combat_context,
        Cond.target_valid,
        Cond.righteousness_not_active,
        Cond.blood_not_active,
        Cond.command_not_active,
        Cond.spell_ready("seal_of_righteousness", nil, "self"),
    }, Act.queue_seal_of_righteousness, nil, 95)
    builder:add_priority("melee_fallback", {
        Cond.target_valid,
    }, Act.melee_fallback, nil, 990)
    builder:add_priority("fallback_noop", nil, Act.noop, nil, 1000)
    return BT.cooldown("ret_gcd_cooldown", 75, builder:build(blackboard), { key = "combat_ret_gcd" })
end

function Profile.build(blackboard, event_bus)
    local o = setmetatable({}, Profile)
    o.id = "paladin_retribution_tbc"
    o._maintenance = Runner:new(BT.cooldown("ret_maintenance_cooldown", 250, MaintenanceTree.build(), { key = "combat_ret_maintenance" }))
    o._off_gcd = Runner:new(build_off_gcd_root())
    o._gcd = Runner:new(build_gcd_root(blackboard))
    blackboard:set("rotation.profile_id", o.id)
    -- Paladin combat range is melee (5 yd). Needed by pull phase (defaults to 28)
    -- and chase controller (defaults to 4.5) to set correct approach distance.
    blackboard:set("module.combat.combat_range", 5)
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
