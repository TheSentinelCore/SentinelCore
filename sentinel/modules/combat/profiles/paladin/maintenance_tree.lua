local BT = require("core/bt/factory")
local Cond = require("modules/combat/profiles/paladin/retribution_conditions")
local Act = require("modules/combat/profiles/paladin/retribution_actions")

local MaintenanceTree = {}

function MaintenanceTree.build()
    return BT.selector("ret_paladin_maintenance", {
        BT.sequence("ensure_retribution_aura", {
            BT.condition("missing_retribution_aura", Cond.missing_retribution_aura),
            BT.condition("retribution_aura_ready", Cond.spell_ready("retribution_aura", nil, "self")),
            BT.action("queue_retribution_aura", Act.queue_retribution_aura),
        }),
        BT.sequence("ensure_seal", {
            BT.condition("baseline_seal_missing", Cond.baseline_seal_missing),
            BT.condition("seal_of_blood_ready", Cond.spell_ready("seal_of_blood", nil, "self")),
            BT.action("queue_seal_of_blood", Act.queue_seal_of_blood),
        }),
        BT.sequence("ensure_blessing_of_kings", {
            BT.condition("preferred_blessing_is_kings", Cond.preferred_blessing_is_kings),
            BT.condition("missing_kings", Cond.missing_kings),
            BT.condition("blessing_of_kings_ready", Cond.spell_ready("blessing_of_kings", nil, "self")),
            BT.action("queue_blessing_of_kings", Act.queue_blessing_of_kings),
        }),
        BT.sequence("ensure_blessing_of_might", {
            BT.condition("preferred_blessing_is_not_kings", function(blackboard)
                return not Cond.preferred_blessing_is_kings(blackboard)
            end),
            BT.condition("missing_might", Cond.missing_might),
            BT.condition("blessing_of_might_ready", Cond.spell_ready("blessing_of_might", nil, "self")),
            BT.action("queue_blessing_of_might", Act.queue_blessing_of_might),
        }),
    })
end

return MaintenanceTree
