local BT = require("lib/BehaviorTree")
local ModeState = require("core/ModeState")

---@return table
---@param exploration ExplorationService|nil
return function(exploration)
    return BT.Action:new(function(bb)
        ModeState.set_phase(bb, "scout")

        if exploration and type(exploration.tick) == "function" then
            exploration:tick()
        end

        return BT.SUCCESS
    end, "Scout")
end
