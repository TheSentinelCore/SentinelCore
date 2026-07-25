local API = require("rotations/mage_frost/sentinel_api")
local BT = setmetatable({}, { __index = function(_, k) return API.bt and API.bt[k] or nil end })
local Cond = require("rotations/mage_frost/frost_conditions")
local Act = require("rotations/mage_frost/frost_actions")

local MaintenanceTree = {}

function MaintenanceTree.build()
    return BT.selector("frost_mage_maintenance", {
        BT.sequence("ensure_ice_armor", {
            BT.condition("level_at_least_30", Cond.level_at_least(30)),
            BT.condition("missing_ice_armor", Cond.missing_ice_armor),
            BT.condition("ice_armor_ready", Cond.spell_ready("ice_armor", nil, "self")),
            BT.action("queue_ice_armor", Act.queue_ice_armor),
        }),
        BT.sequence("ensure_frost_armor", {
            BT.condition("below_level_30", function(bb)
                return not Cond.level_at_least(30)(bb)
            end),
            BT.condition("missing_frost_armor", Cond.missing_frost_armor),
            BT.condition("frost_armor_ready", Cond.spell_ready("frost_armor", nil, "self")),
            BT.action("queue_frost_armor", Act.queue_frost_armor),
        }),
        BT.sequence("ensure_arcane_intellect", {
            BT.condition("missing_arcane_intellect", Cond.missing_arcane_intellect),
            BT.condition("arcane_intellect_ready", Cond.spell_ready("arcane_intellect", nil, "self")),
            BT.action("queue_arcane_intellect", Act.queue_arcane_intellect),
        }),
        BT.sequence("conjure_food", {
            BT.condition("not_in_combat", Cond.not_in_combat),
            BT.condition("not_casting", Cond.not_casting_or_channeling),
            BT.condition("not_moving", function(bb) return bb:get("player.is_moving", false) ~= true end),
            BT.condition("needs_food", function(bb)
                if not bb:get("module.grind.needs_food", false) then return false end
                local free = bb:get("module.grind.bag_free_slots", 0)
                return free >= 4
            end),
            BT.condition("conjure_food_ready", Cond.spell_ready("conjure_food", nil, "self")),
            BT.action("queue_conjure_food", Act.queue_conjure_food),
        }),
        BT.sequence("conjure_water", {
            BT.condition("not_in_combat", Cond.not_in_combat),
            BT.condition("not_casting", Cond.not_casting_or_channeling),
            BT.condition("not_moving", function(bb) return bb:get("player.is_moving", false) ~= true end),
            BT.condition("needs_water", function(bb)
                if not bb:get("module.grind.needs_water", false) then return false end
                local free = bb:get("module.grind.bag_free_slots", 0)
                return free >= 4
            end),
            BT.condition("conjure_water_ready", Cond.spell_ready("conjure_water", nil, "self")),
            BT.action("queue_conjure_water", Act.queue_conjure_water),
        }),
        BT.sequence("conjure_mana_gem", {
            BT.condition("not_in_combat", Cond.not_in_combat),
            BT.condition("not_casting", Cond.not_casting_or_channeling),
            BT.condition("not_moving", function(bb) return bb:get("player.is_moving", false) ~= true end),
            BT.condition("level_at_least_28", Cond.level_at_least(28)),
            BT.condition("missing_mana_gem", Cond.missing_mana_gem),
            BT.condition("mana_above_50", Cond.mana_above(0.50)),
            BT.action("queue_conjure_mana_gem", Act.queue_conjure_mana_gem),
        }),
    })
end

return MaintenanceTree
