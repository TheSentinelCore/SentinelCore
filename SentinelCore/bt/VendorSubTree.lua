local BT = require("ai/BehaviorTree")
local S = BT.Status

local VendorSubTree = {}

function VendorSubTree.build(bb, vendor_service)
    return BT.Sequence:new("vendor", {
        -- Gate: bags near full or durability low
        BT.Condition:new("needs_vendor", function()
            if bb:get("player.in_combat", false) then return false end
            local free = bb:get("inventory.free_slots", 99)
            local durability = bb:get("inventory.durability_pct", 1.0)
            return free <= 3 or durability < 0.25
        end),

        -- Vendor trip with timeout
        BT.Timeout:new("vendor_timeout", 120.0,
            BT.Action:new("vendor_trip", function()
                if not vendor_service then
                    return S.FAILURE
                end

                -- Delegate to existing VendorService
                local ok, result = pcall(function()
                    return vendor_service:update()
                end)

                if not ok then
                    return S.FAILURE
                end

                -- Check if vendor trip is complete
                if vendor_service.is_complete and vendor_service:is_complete() then
                    return S.SUCCESS
                end

                return S.RUNNING
            end)
        ),
    })
end

return VendorSubTree
