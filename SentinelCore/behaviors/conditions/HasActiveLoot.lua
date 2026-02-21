local BT = require("lib/BehaviorTree")

---@param loot_service LootService
---@return table
return function(loot_service)
    return BT.Condition:new(function()
        return loot_service:is_active()
    end, "HasActiveLoot")
end
