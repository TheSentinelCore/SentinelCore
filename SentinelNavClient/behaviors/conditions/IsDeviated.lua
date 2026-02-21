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

        local substate = bb:get("hsm.substate")
        if substate ~= "following_path" then
            bb:set("deviation.eval_tick", tick)
            bb:set("deviation.eval_result", false)
            bb:set("deviation.last_result", false)
            bb:set("deviation.last_raw_result", false)
            bb:set("deviation.consecutive_count", 0)
            bb:set("deviation.confirmed_prev", false)
            bb:set("deviation.last_check", now)
            return false
        end

        -- Forced repaths from ValidatePath are handled in a dedicated BT branch and
        -- should not consume or bypass deviation budget here.
        local count = tonumber(bb:get("deviation.count", 0)) or 0
        local max = tonumber(bb:get("config.max_deviation_repaths", 5)) or 5
        if max < 1 then
            max = 1
        end
        local hard_escalation = bb:get("config.deviation_hard_escalation_enabled", false) == true
        if (not hard_escalation) and count >= max then
            bb:set("deviation.eval_tick", tick)
            bb:set("deviation.eval_result", false)
            bb:set("deviation.last_result", false)
            bb:set("deviation.last_raw_result", false)
            bb:set("deviation.consecutive_count", 0)
            bb:set("deviation.confirmed_prev", false)
            bb:set("deviation.last_check", now)
            return false
        end

        local grace_until = bb:get("deviation.repath_grace_until", 0)
        if now < grace_until then
            bb:set("deviation.eval_tick", tick)
            bb:set("deviation.eval_result", false)
            bb:set("deviation.last_result", false)
            bb:set("deviation.last_raw_result", false)
            bb:set("deviation.consecutive_count", 0)
            bb:set("deviation.confirmed_prev", false)
            return false
        end

        local interval = bb:get("config.deviation_check_interval", 1.0)
        local last_check = bb:get("deviation.last_check", 0)
        local raw_deviated = false
        local sampled = false

        if now - last_check < interval then
            raw_deviated = bb:get("deviation.last_raw_result", false)
        else
            sampled = true
            bb:set("deviation.last_check", now)

            local pos = bb:get("player.position")
            local waypoints = bb:get("path.waypoints")
            local index = bb:get("path.index", 1)
            local widths = bb:get("path.corridor_widths")
            if pos and waypoints and #waypoints > 0 then
                local deviation_result = validation_service:check_deviation(pos, waypoints, index, widths)
                raw_deviated = deviation_result.deviated
                bb:set("deviation.last_raw_result", raw_deviated)
                bb:set("deviation.last_vertical_drift", deviation_result.vertical_drift or 0)
                bb:set("deviation.last_threshold", deviation_result.threshold or 0)
                if raw_deviated then
                    bb:set("deviation.last_drift", deviation_result.drift)
                end
            end
        end

        local confirmations = tonumber(bb:get("config.deviation_confirmation_ticks", 2)) or 2
        if confirmations < 1 then
            confirmations = 1
        end

        local consecutive = tonumber(bb:get("deviation.consecutive_count", 0)) or 0
        if sampled then
            if raw_deviated then
                consecutive = consecutive + 1
            else
                consecutive = 0
            end
        end
        bb:set("deviation.consecutive_count", consecutive)

        local vertical = tonumber(bb:get("deviation.last_vertical_drift", 0)) or 0
        local vertical_threshold = tonumber(bb:get("config.deviation_vertical_threshold", 2.0)) or 2.0
        local vertical_critical_factor = tonumber(bb:get("config.deviation_vertical_critical_factor", 1.5)) or 1.5
        if vertical_critical_factor < 1.0 then
            vertical_critical_factor = 1.0
        end
        local critical_vertical = vertical >= (vertical_threshold * vertical_critical_factor)

        local deviated = raw_deviated and (critical_vertical or consecutive >= confirmations)
        local prev_confirmed = bb:get("deviation.confirmed_prev", false)
        bb:set("deviation.confirmed_prev", deviated)
        bb:set("deviation.last_result", deviated)

        if deviated and not prev_confirmed then
            local pos = bb:get("player.position")
            event_bus:emit(Events.DEVIATION_DETECTED, {
                drift = bb:get("deviation.last_drift", 0),
                vertical_drift = vertical,
                threshold = bb:get("deviation.last_threshold", 0),
                position = pos,
                path_index = bb:get("path.index", 1),
                confirmations = consecutive,
                critical_vertical = critical_vertical,
            })
        end

        bb:set("deviation.eval_tick", tick)
        bb:set("deviation.eval_result", deviated)
        return deviated
    end, "IsDeviated")
end
