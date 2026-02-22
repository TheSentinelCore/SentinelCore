local BT = require("lib/BehaviorTree")
local ErrorCodes = require("events/ErrorCodes")
local ModeState = require("core/ModeState")

---@param loot_service LootService
---@return table
return function(loot_service)
    return BT.Action:new(function(bb)
        local function clear_pending()
            if loot_service and loot_service.reset then
                loot_service:reset()
            end
            bb:clear("loot.pending_target")
        end

        if loot_service:get_state() == "completed" then
            clear_pending()
            ModeState.set_phase(bb, "scout")
            return BT.SUCCESS
        end

        if not loot_service:is_active() then
            local loot_target = bb:get("loot.pending_target")
            if not loot_target then
                return BT.FAILURE
            end

            if loot_target.is_valid then
                local ok_valid, valid = pcall(loot_target.is_valid, loot_target)
                if not ok_valid or valid ~= true then
                    clear_pending()
                    return BT.FAILURE
                end
            end

            local ok, err = loot_service:start(loot_target)
            if not ok then
                clear_pending()
                bb:set("core.fail_reason", err or ErrorCodes.LOOT_FAILED)
                return BT.FAILURE
            end
            ModeState.set_phase(bb, "loot")
            return BT.RUNNING
        end

        ModeState.set_phase(bb, "loot")
        local ok, err = loot_service:update()
        if not ok then
            clear_pending()
            bb:set("core.fail_reason", err or ErrorCodes.LOOT_FAILED)
            return BT.FAILURE
        end

        if loot_service:get_state() == "completed" then
            clear_pending()
            ModeState.set_phase(bb, "scout")
            return BT.SUCCESS
        end

        return BT.RUNNING
    end, "RunLoot")
end
