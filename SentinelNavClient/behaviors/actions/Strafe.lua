-- Strafe.lua
-- BT Action: strafes for a duration using MovementService (simple_movement).
-- Returns RUNNING while strafing.
local BT = require("lib/BehaviorTree")

---@param movement_service table MovementService instance
---@param duration? number Strafe duration in seconds (default 0.5)
---@param direction? string "left" or "right" (default "left")
return function(movement_service, duration, direction)
    duration = duration or 0.5
    direction = direction or "left"

    local start_time = nil

    return BT.Action:new(function(bb, dt)
        local now = bb:get("_time", 0)

        -- Guard: reset stale start_time if tree was reset mid-action
        if start_time and (now - start_time) > duration * 2 then
            start_time = nil
        end

        if not start_time then
            start_time = now
            movement_service:strafe(direction)
            return BT.RUNNING
        end

        if now - start_time >= duration then
            movement_service:strafe(nil)
            start_time = nil
            return BT.SUCCESS
        end

        return BT.RUNNING
    end, "Strafe")
end
