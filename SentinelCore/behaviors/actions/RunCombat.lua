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
                local dead_target = bb:get("combat.target")
                if dead_target and dead_target.is_dead and dead_target:is_dead() then
                    bb:set("loot.pending_target", dead_target)
                end
                return BT.SUCCESS
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
