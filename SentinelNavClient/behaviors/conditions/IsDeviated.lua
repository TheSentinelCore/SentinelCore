-- IsDeviated.lua
-- BT Condition: returns SUCCESS if player has deviated from path.
-- Requires a PathValidationService instance and EventBus passed to factory.
local BT = require("lib/BehaviorTree")
local Events = require("events/Events")

--- Factory: returns a BT.Condition node that checks path deviation.
---@param validation_service table PathValidationService instance
---@param event_bus table EventBus instance
---@return table BT.Condition node
return function(validation_service, event_bus)
    return BT.Condition:new(function(bb)
        local now = bb:get("_time", 0)
        local tick = bb:get("_tick", 0)
        local eval_tick = bb:get("deviation.eval_tick", -1)
        if eval_tick == tick then
            return bb:get("deviation.eval_result", false)
        end

        local forced_repath = bb:get("deviation.needs_repath", false)
        local interval = bb:get("config.deviation_check_interval", 1.0)
        local last_check = bb:get("deviation.last_check", 0)
        local deviated = false

        if forced_repath then
            deviated = true
            bb:set("deviation.last_result", true)
        elseif now - last_check < interval then
            deviated = bb:get("deviation.last_result", false)
        else
            bb:set("deviation.last_check", now)

            local pos = bb:get("player.position")
            local waypoints = bb:get("path.waypoints")
            local index = bb:get("path.index", 1)
            local widths = bb:get("path.corridor_widths")
            if pos and waypoints and #waypoints > 0 then
                local result = validation_service:check_deviation(pos, waypoints, index, widths)
                deviated = result.deviated
                bb:set("deviation.last_result", result.deviated)

                if result.deviated then
                    bb:set("deviation.last_drift", result.drift)
                    event_bus:emit(Events.DEVIATION_DETECTED, {
                        drift = result.drift,
                        position = pos,
                        path_index = index,
                    })
                end
            end
        end

        bb:set("deviation.eval_tick", tick)
        bb:set("deviation.eval_result", deviated)
        return deviated
    end, "IsDeviated")
end
