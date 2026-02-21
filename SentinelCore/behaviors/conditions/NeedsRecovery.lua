local BT = require("lib/BehaviorTree")

---@param recovery_service RecoveryService
---@return table
return function(recovery_service)
    return BT.Condition:new(function()
        return recovery_service:is_active()
    end, "NeedsRecovery")
end
