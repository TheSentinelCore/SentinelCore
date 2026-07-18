local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local VendorStateMachine = require("modules/grind/vendor_state_machine")

local Vendor = {}

---Build the vendor phase sub-tree.
---Uses the extracted VendorStateMachine module instead of inline state management.
---All vendor interaction state is internal to VendorStateMachine — no blackboard keys
---are leaked for vendor_state, vendor_data, vendor_retries, etc.
---@param blackboard table Blackboard instance
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Vendor.build(blackboard, event_bus, nav_adapter)
    local vendor_sm = VendorStateMachine:new(event_bus, nav_adapter)

    return BT.sequence("vendor_run", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Gate: combat module must not be actively engaged
        BT.condition("not_engaged", function(bb)
            return bb:get("combat.source") == nil
        end),

        -- Gate: needs vendor visit (bags full, needs repair, needs food/water)
        BT.condition("needs_vendor", function(bb)
            local free = bb:get("module.grind.bag_free_slots", 99)
            if free <= 2 then return true end
            if bb:get("module.grind.needs_repair") == true then return true end
            local pm = bb:get("module.grind.profile_manager")
            if pm then
                local player_pos = bb:get("player.position")
                if player_pos then
                    if bb:get("module.grind.needs_food") and pm:get_nearest_vendor(player_pos, "food") then
                        return true
                    end
                    if bb:get("module.grind.needs_water") and pm:get_nearest_vendor(player_pos, "water") then
                        return true
                    end
                end
            end
            return false
        end),

        -- Delegate all vendor interaction to VendorStateMachine.
        -- The state machine owns its own internal state (traveling, interacting,
        -- repairing, selling, buying food/water, etc.) and reads external data
        -- from the blackboard as needed.
        BT.action("vendor_action", function(bb)
            return vendor_sm:tick(bb)
        end),
    })
end

return Vendor
