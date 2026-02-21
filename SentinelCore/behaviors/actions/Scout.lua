local BT = require("lib/BehaviorTree")

---@return table
return function()
    return BT.Action:new(function(bb)
        local sm = bb:get("core.state_machine")
        if sm then
            sm:set_substate("running.grind.scout")
        end
        return BT.SUCCESS
    end, "Scout")
end
