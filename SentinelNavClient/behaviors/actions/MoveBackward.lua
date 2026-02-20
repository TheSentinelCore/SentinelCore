-- MoveBackward.lua
-- BT Action: moves backward for a duration. Returns RUNNING while moving.
local BT = require("lib/BehaviorTree")

---@param duration? number Move duration in seconds (default 1.0)
return function(duration)
    duration = duration or 1.0

    local start_time = nil

    return BT.Action:new(function(bb, dt)
        local now = bb:get("_time", 0)

        -- Guard: reset stale start_time if tree was reset mid-action
        if start_time and (now - start_time) > duration * 2 then
            start_time = nil
        end

        if not start_time then
            start_time = now
            core.input.start_move_backward()
            return BT.RUNNING
        end

        if now - start_time >= duration then
            core.input.stop_move_backward()
            start_time = nil
            return BT.SUCCESS
        end

        return BT.RUNNING
    end, "MoveBackward")
end
