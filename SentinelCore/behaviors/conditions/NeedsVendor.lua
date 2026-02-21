local BT = require("lib/BehaviorTree")

---@param inventory_service InventoryService
---@param vendor_service VendorService
---@return table
return function(inventory_service, vendor_service)
    return BT.Condition:new(function()
        if vendor_service:is_active() then
            return true
        end
        return inventory_service:needs_vendor_trip()
    end, "NeedsVendor")
end
