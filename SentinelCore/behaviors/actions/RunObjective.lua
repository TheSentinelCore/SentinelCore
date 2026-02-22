local BT = require("lib/BehaviorTree")
local ErrorCodes = require("events/ErrorCodes")
local ModeState = require("core/ModeState")

---@param objective_service ObjectiveService|nil
---@return table
return function(objective_service)
    return BT.Action:new(function(bb)
        if not objective_service or type(objective_service.tick) ~= "function" then
            return BT.FAILURE
        end

        ModeState.set_phase(bb, "objective")
        local status, error_code = objective_service:tick()
        if status == "running" then
            return BT.RUNNING
        end

        if status == "success" then
            ModeState.set_phase(bb, "scout")
            return BT.SUCCESS
        end

        if status == "idle" and error_code == ErrorCodes.OBJECTIVE_NONE_AVAILABLE then
            ModeState.set_phase(bb, "scout")
            return BT.FAILURE
        end

        if error_code and error_code ~= ErrorCodes.OBJECTIVE_NONE_AVAILABLE then
            bb:set("objective.last_error", error_code)
        end
        ModeState.set_phase(bb, "scout")
        return BT.FAILURE
    end, "RunObjective")
end
