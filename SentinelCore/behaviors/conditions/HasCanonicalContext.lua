local BT = require("lib/BehaviorTree")

---@param blackboard Blackboard
---@return table
return function(blackboard)
    return BT.Condition:new(function()
        return blackboard:has("context.canonical")
    end, "HasCanonicalContext")
end
