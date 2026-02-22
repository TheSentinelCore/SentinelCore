local BT = require("lib/BehaviorTree")
local ErrorCodes = require("events/ErrorCodes")
local ModeState = require("core/ModeState")

---@param vendor_service VendorService
---@return table
return function(vendor_service)
    return BT.Action:new(function(bb)
        ModeState.set_phase(bb, "vendor")
        local canonical = bb:get("context.canonical")
        if not canonical then
            bb:set("core.fail_reason", ErrorCodes.CTX_UNRESOLVED)
            return BT.FAILURE
        end

        if not vendor_service:is_active() and vendor_service:get_state() ~= "completed" then
            local ok, err = vendor_service:start(canonical)
            if not ok then
                bb:set("core.fail_reason", err or ErrorCodes.VENDOR_NONE_VIABLE)
                return BT.FAILURE
            end
            return BT.RUNNING
        end

        local ok, err = vendor_service:update()
        if not ok then
            bb:set("core.fail_reason", err or ErrorCodes.VENDOR_NONE_VIABLE)
            return BT.FAILURE
        end

        if vendor_service:get_state() == "completed" then
            vendor_service:reset()
            bb:set("inventory.needs_vendor", false)
            ModeState.set_phase(bb, "scout")
            return BT.SUCCESS
        end

        return BT.RUNNING
    end, "RunVendor")
end
