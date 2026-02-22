local BT = require("lib/BehaviorTree")
local ModeState = require("core/ModeState")

---@return table
return function()
    return BT.Action:new(function(bb)
        ModeState.set_phase(bb, "scout")
        return BT.SUCCESS
    end, "Scout")
end
