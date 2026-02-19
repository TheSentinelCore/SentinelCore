-- Jump.lua
-- BT Action: triggers a jump input. Instant action.
local BT = require("lib.BehaviorTree")

return function()
    return BT.Action:new("Jump", function(bb, dt)
        core.input.jump()
        return BT.SUCCESS
    end)
end
