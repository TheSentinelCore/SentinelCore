local BT = require("lib/BehaviorTree")
local ErrorCodes = require("events/ErrorCodes")

---@param vendor_service VendorService
---@return table
return function(vendor_service)
    return BT.Action:new(function(bb)
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
            return BT.SUCCESS
        end

        return BT.RUNNING
    end, "RunVendor")
end
