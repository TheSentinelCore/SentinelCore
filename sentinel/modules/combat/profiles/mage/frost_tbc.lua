local BT = require("core/bt/factory")
local Runner = require("core/bt/runner")
local Cond = require("modules/combat/profiles/mage/frost_conditions")
local Act = require("modules/combat/profiles/mage/frost_actions")
local MaintenanceTree = require("modules/combat/profiles/mage/maintenance_tree")
local AoeTree = require("modules/combat/profiles/mage/aoe_tree")

local Profile = {}
Profile.__index = Profile

local function build_off_gcd_root()
    return BT.selector("frost_mage_off_gcd", {
        BT.sequence("ice_barrier", {
            BT.condition("level_at_least_30", Cond.level_at_least(30)),
            BT.condition("ice_barrier_ready", Cond.spell_ready("ice_barrier", nil, "self")),
            BT.action("queue_ice_barrier", Act.queue_ice_barrier),
        }),
        BT.sequence("icy_veins", {
            BT.condition("in_combat", Cond.in_combat),
            BT.condition("icy_veins_ready", Cond.spell_ready("icy_veins", nil, "self")),
            BT.action("queue_icy_veins", Act.queue_icy_veins),
        }),
        BT.sequence("cold_snap", {
            BT.condition("health_below_30", Cond.health_below(0.30)),
            BT.condition("cold_snap_ready", Cond.spell_ready("cold_snap", nil, "self")),
            BT.action("queue_cold_snap", Act.queue_cold_snap),
        }),
        BT.sequence("evocation", {
            BT.condition("mana_below_15", Cond.mana_below(0.15)),
            BT.condition("evocation_ready", Cond.spell_ready("evocation", nil, "self")),
            BT.action("queue_evocation", Act.queue_evocation),
        }),
    })
end

local function build_gcd_root()
    return BT.selector("frost_mage_gcd", {
        BT.sequence("counterspell", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("target_casting_interruptible", Cond.target_casting_interruptible),
            BT.condition("counterspell_ready", Cond.spell_ready("counterspell")),
            BT.action("queue_counterspell", Act.queue_counterspell),
        }),
        BT.sequence("ice_block_emergency", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("health_below_15", Cond.health_below(0.15)),
            BT.condition("ice_block_ready", Cond.spell_ready("ice_block", nil, "self")),
            BT.action("queue_ice_block", Act.queue_ice_block),
        }),
        BT.sequence("frost_nova_escape", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("enemies_in_melee_1", Cond.enemies_in_melee(1)),
            BT.condition("frost_nova_ready", Cond.spell_ready("frost_nova")),
            BT.action("queue_frost_nova", Act.queue_frost_nova),
        }),
        BT.sequence("cone_of_cold", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("enemies_in_melee_1", Cond.enemies_in_melee(1)),
            BT.condition("cone_of_cold_ready", Cond.spell_ready("cone_of_cold")),
            BT.action("queue_cone_of_cold", Act.queue_cone_of_cold),
        }),
        BT.sequence("fire_blast_runner", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("moving_or_execute", function(bb)
                if Cond.player_is_moving(bb) then
                    return true
                end
                local target = bb:get("combat.target") or bb:get("player.target")
                if not target then
                    return false
                end
                local ok, hp = pcall(target.get_health_percentage, target)
                return ok and (tonumber(hp) or 1) <= 0.20
            end),
            BT.condition("fire_blast_ready", Cond.spell_ready("fire_blast")),
            BT.action("queue_fire_blast", Act.queue_fire_blast),
        }),
        BT.sequence("ice_lance", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("level_at_least_66", Cond.level_at_least(66)),
            BT.condition("ice_lance_ready", Cond.spell_ready("ice_lance")),
            BT.action("queue_ice_lance", Act.queue_ice_lance),
        }),
        BT.sequence("frostbolt", {
            BT.condition("gcd_ready", Cond.gcd_ready),
            BT.condition("frostbolt_ready", Cond.spell_ready("frostbolt")),
            BT.action("queue_frostbolt", Act.queue_frostbolt),
        }),
        BT.action("fallback_noop", Act.noop),
    })
end

function Profile.build(blackboard, event_bus)
    local o = setmetatable({}, Profile)
    o.id = "mage_frost_tbc"
    o._maintenance = Runner:new(BT.cooldown("frost_maintenance_cd", 250,
        MaintenanceTree.build(), { key = "combat_frost_maintenance" }))
    o._off_gcd = Runner:new(BT.cooldown("frost_offgcd_cd", 75,
        build_off_gcd_root(), { key = "combat_frost_offgcd" }))
    o._gcd = Runner:new(BT.cooldown("frost_gcd_cd", 75,
        build_gcd_root(), { key = "combat_frost_gcd" }))
    o._aoe_tree = Runner:new(AoeTree.build())
    blackboard:set("rotation.profile_id", o.id)
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

function Profile:tick_pull(bb, target)
    if self:get_pull_strategy(bb) == "aoe" then
        return self._aoe_tree:tick(bb)
    end
    return Act.queue_frostbolt(bb)
end

function Profile:prepare_rest(bb)
    return self._maintenance:tick(bb)
end

return Profile
