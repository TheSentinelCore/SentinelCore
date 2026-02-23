local BT = require("ai/BehaviorTree")
local S = BT.Status

local CombatInterruptSubTree = {}

function CombatInterruptSubTree.build(bb)
    return BT.Sequence:new("combat_interrupt", {
        -- Gate: in combat AND was doing something non-combat
        BT.Condition:new("interrupted", function()
            if not bb:get("player.in_combat", false) then return false end
            return bb:get("combat.was_resting", false)
                or bb:get("combat.was_looting", false)
        end),

        -- Cancel current action and clear flags
        BT.Action:new("cancel_and_stand", function()
            bb:set("combat.was_resting", false)
            bb:set("combat.was_looting", false)
            -- Stop any movement/channeling
            if core.input and core.input.stop_casting then
                pcall(function() core.input.stop_casting() end)
            end
            return S.SUCCESS
        end),
    })
end

return CombatInterruptSubTree
