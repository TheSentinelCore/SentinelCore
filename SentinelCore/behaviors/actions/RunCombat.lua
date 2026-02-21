local BT = require("lib/BehaviorTree")
local ErrorCodes = require("events/ErrorCodes")

---@param targeting TargetingService
---@param combat CombatService
---@return table
return function(targeting, combat)
    return BT.Action:new(function(bb)
        local state_machine = bb:get("core.state_machine")
        if combat:is_active() then
            local ok, err = combat:update()
            if not ok then
                bb:set("core.fail_reason", err or ErrorCodes.COMBAT_TIMEOUT)
                return BT.FAILURE
            end

            if state_machine then
                state_machine:set_substate("running.grind.combat")
            end

            if combat:get_state() == "idle" then
                return BT.SUCCESS
            end

            return BT.RUNNING
        end

        if combat.run_maintenance then
            local maintained, maintenance_err = combat:run_maintenance()
            if maintenance_err then
                bb:set("core.fail_reason", maintenance_err)
                return BT.FAILURE
            end
            if maintained then
                if state_machine then
                    state_machine:set_substate("running.grind.combat")
                end
                return BT.RUNNING
            end
        end

        if combat.should_hold_for_maintenance and combat:should_hold_for_maintenance() then
            if state_machine then
                state_machine:set_substate("running.grind.combat")
            end
            return BT.RUNNING
        end

        local target, err = targeting:acquire_target()
        if not target then
            if err == ErrorCodes.TARGET_NOT_FOUND then
                if state_machine then
                    state_machine:set_substate("running.grind.scout")
                end
                return BT.FAILURE
            end
            bb:set("core.fail_reason", err or ErrorCodes.TARGET_NOT_FOUND)
            return BT.FAILURE
        end

        if state_machine then
            state_machine:set_substate("running.grind.pull")
        end

        local started, start_err = combat:start(target)
        if not started then
            bb:set("core.fail_reason", start_err or ErrorCodes.PULL_FAILED)
            return BT.FAILURE
        end

        return BT.RUNNING
    end, "RunCombat")
end
