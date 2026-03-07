local BT = require("core/bt/factory")
local Cond = require("modules/combat/profiles/mage/frost_conditions")
local Act = require("modules/combat/profiles/mage/frost_actions")

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
            BT.condition("needs_food", function(bb)
                return (bb:get("module.grind.needs_food", true))
            end),
            BT.condition("conjure_food_ready", Cond.spell_ready("conjure_food", nil, "self")),
            BT.action("queue_conjure_food", Act.queue_conjure_food),
        }),
        BT.sequence("conjure_water", {
            BT.condition("not_in_combat", Cond.not_in_combat),
            BT.condition("needs_water", function(bb)
                return (bb:get("module.grind.needs_water", true))
            end),
            BT.condition("conjure_water_ready", Cond.spell_ready("conjure_water", nil, "self")),
            BT.action("queue_conjure_water", Act.queue_conjure_water),
        }),
    })
end

return MaintenanceTree
