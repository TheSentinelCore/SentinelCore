local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local Combat = {}

---Build the combat phase sub-tree.
---This is the simplest phase: it yields when the player is in combat,
---allowing the combat module to handle fighting without interference
---from the grind selector.
---@return table BT node
function Combat.build()
    return BT.sequence("combat_active", {
        -- Gate: combat module must be actively engaged (not just WoW combat linger)
        BT.condition("combat_engaged", function(bb)
            return bb:get("combat.source") ~= nil
        end),

        -- Yield: combat module handles fighting.
        -- Must return RUNNING so the priority selector keeps this child active
        -- without falling through to lower-priority phases (pull/acquire).
        -- Returning SUCCESS would also keep the selector here (priority_selector
        -- treats SUCCESS as "this child satisfied, stop"), but SUCCESS is
        -- semantically wrong — combat hasn't finished until disengage clears
        -- combat.source.
        BT.action("yield", function(bb)
            return Status.RUNNING
        end),
    })
end

return Combat
