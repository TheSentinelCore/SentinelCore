local BT = require("lib/BehaviorTree")

---@param recovery_service RecoveryService
---@param command_handlers table
---@return table
return function(recovery_service, command_handlers)
    command_handlers = command_handlers or {}

    return BT.Action:new(function(bb)
        local now = bb:get("_time", 0)
        local command = recovery_service:update(now)
        if not command then
            return BT.RUNNING
        end

        if command.action == "pause" then
            if command_handlers.pause then
                command_handlers.pause(command.error_code)
            end
            return BT.RUNNING
        end

        if command.action == "restart" then
            if command_handlers.restart then
                local ok = command_handlers.restart(command)
                recovery_service:complete_restart_attempt(ok == true)
                if ok then
                    return BT.SUCCESS
                end
                return BT.RUNNING
            end
            return BT.RUNNING
        end

        if command.action == "fail" then
            if command_handlers.fail then
                command_handlers.fail(command.error_code)
            end
            return BT.FAILURE
        end

        return BT.RUNNING
    end, "RunRecovery")
end
