local BT = require("lib/BehaviorTree")

---@param combat_service CombatService
---@return table
return function(combat_service)
    return BT.Condition:new(function()
        return combat_service:is_active()
    end, "HasActiveCombat")
end
