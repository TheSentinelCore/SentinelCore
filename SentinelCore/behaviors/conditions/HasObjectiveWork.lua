local BT = require("lib/BehaviorTree")

---@param objective_service ObjectiveService|nil
---@return table
return function(objective_service)
    return BT.Condition:new(function(bb)
        if not objective_service or type(objective_service.has_work) ~= "function" then
            return false
        end
        if bb and bb:get("player.in_combat", false) == true then
            return false
        end
        return objective_service:has_work()
    end, "HasObjectiveWork")
end
