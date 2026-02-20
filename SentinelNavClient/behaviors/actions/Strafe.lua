-- Strafe.lua
-- BT Action: strafes for a duration. Returns RUNNING while strafing.
local BT = require("lib/BehaviorTree")

---@param duration? number Strafe duration in seconds (default 0.5)
---@param direction? string "left" or "right" (default "left")
return function(duration, direction)
    duration = duration or 0.5
    direction = direction or "left"

    local start_time = nil

    return BT.Action:new(function(bb, dt)
        local now = bb:get("_time", 0)

        if not start_time then
            start_time = now
            if direction == "left" then
                core.input.start_strafe_left()
            else
                core.input.start_strafe_right()
            end
            return BT.RUNNING
        end

        if now - start_time >= duration then
            core.input.stop_strafe()
            start_time = nil
            return BT.SUCCESS
        end

        return BT.RUNNING
    end, "Strafe")
end
