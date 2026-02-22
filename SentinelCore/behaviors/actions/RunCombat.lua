local BT = require("lib/BehaviorTree")
local ErrorCodes = require("events/ErrorCodes")
local ModeState = require("core/ModeState")

---@param targeting TargetingService
---@param combat CombatService
---@return table
return function(targeting, combat)
    return BT.Action:new(function(bb)
        if combat:is_active() then
            local ok, err = combat:update()
            if not ok then
                bb:set("core.fail_reason", err or ErrorCodes.COMBAT_TIMEOUT)
                return BT.FAILURE
            end

            ModeState.set_phase(bb, "combat")

            if combat:get_state() == "idle" then
                return BT.SUCCESS
            end

            return BT.RUNNING
        end

        local holding_for_maintenance = combat.should_hold_for_maintenance and combat:should_hold_for_maintenance()
        if holding_for_maintenance then
            if combat.run_maintenance then
                local maintained, maintenance_err = combat:run_maintenance()
                if maintenance_err then
                    bb:set("core.fail_reason", maintenance_err)
                    return BT.FAILURE
                end
            end
            ModeState.set_phase(bb, "combat")
            return BT.RUNNING
        end

        local target, err = targeting:acquire_target()
        if not target then
            if err == ErrorCodes.TARGET_NOT_FOUND then
                ModeState.set_phase(bb, "scout")
                return BT.FAILURE
            end
            bb:set("core.fail_reason", err or ErrorCodes.TARGET_NOT_FOUND)
            return BT.FAILURE
        end

        ModeState.set_phase(bb, "pull")

        local started, start_err = combat:start(target)
        if not started then
            if start_err == ErrorCodes.MAINTENANCE_REQUIRED then
                if combat.run_maintenance then
                    local maintained, maintenance_err = combat:run_maintenance(true)
                    if maintenance_err then
                        bb:set("core.fail_reason", maintenance_err)
                        return BT.FAILURE
                    end
                end
                ModeState.set_phase(bb, "combat")
                return BT.RUNNING
            end
            bb:set("core.fail_reason", start_err or ErrorCodes.PULL_FAILED)
            return BT.FAILURE
        end

        return BT.RUNNING
    end, "RunCombat")
end
