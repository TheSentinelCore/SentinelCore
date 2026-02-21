local BT = require("lib/BehaviorTree")
local ErrorCodes = require("events/ErrorCodes")

---@param loot_service LootService
---@return table
return function(loot_service)
    return BT.Action:new(function(bb)
        if loot_service:get_state() == "completed" then
            loot_service:reset()
            bb:clear("loot.pending_target")
            return BT.SUCCESS
        end

        if not loot_service:is_active() then
            local loot_target = bb:get("loot.pending_target")
            if not loot_target then
                return BT.FAILURE
            end
            local ok, err = loot_service:start(loot_target)
            if not ok then
                bb:set("core.fail_reason", err or ErrorCodes.LOOT_FAILED)
                return BT.FAILURE
            end
            return BT.RUNNING
        end

        local ok, err = loot_service:update()
        if not ok then
            bb:set("core.fail_reason", err or ErrorCodes.LOOT_FAILED)
            return BT.FAILURE
        end

        if loot_service:get_state() == "completed" then
            loot_service:reset()
            bb:clear("loot.pending_target")
            return BT.SUCCESS
        end

        return BT.RUNNING
    end, "RunLoot")
end
