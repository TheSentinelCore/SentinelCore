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
        -- Gate: player must be in combat
        BT.condition("player_in_combat", function(bb)
            return bb:get("player.in_combat") == true
        end),

        -- Yield: combat module handles fighting
        BT.action("yield", function(bb)
            return Status.SUCCESS
        end),
    })
end

return Combat
