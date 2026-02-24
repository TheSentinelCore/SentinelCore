local BT = require("ai/BehaviorTree")
local S = BT.Status

local VendorSubTree = {}

function VendorSubTree.build(bb, vendor_service)
    return BT.ReactiveSequence:new("vendor", {
        -- Gate: bags near full or durability low (re-evaluated every tick)
        BT.Condition:new("needs_vendor", function()
            if bb:get("player.in_combat", false) then return false end
            local free = bb:get("inventory.free_slots", 99)
            local durability = bb:get("player.durability_pct", 1.0)
            return free <= 3 or durability < 0.25
        end),

        -- Vendor trip with timeout
        BT.Timeout:new("vendor_timeout", 120.0,
            BT.Action:new("vendor_trip", function()
                if not vendor_service then
                    return S.FAILURE
                end

                local state = vendor_service:get_state()

                -- Start vendor trip if idle
                if state == "idle" then
                    local ctx = {
                        map_id = bb:get("context.ui_map_id", 0),
                    }
                    local ok, err = vendor_service:start(ctx)
                    if not ok then return S.FAILURE end
                    return S.RUNNING
                end

                -- Update active vendor trip
                if vendor_service:is_active() then
                    pcall(function() vendor_service:update() end)
                    return S.RUNNING
                end

                -- Completed or failed
                if state == "completed" then
                    vendor_service:reset()
                    return S.SUCCESS
                end

                vendor_service:reset()
                return S.FAILURE
            end)
        ),
    })
end

return VendorSubTree
