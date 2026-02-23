local BT = require("ai/BehaviorTree")
local S = BT.Status

local ExploreSubTree = {}

function ExploreSubTree.build(bb, navigation, exploration_service)
    return BT.Sequence:new("explore", {
        -- Gate: nothing else to do (no target, not in combat)
        BT.Condition:new("idle", function()
            if bb:get("player.in_combat", false) then return false end
            local target = bb:get("combat.target")
            if target then
                local ok, hp = pcall(function() return target:get_health() end)
                if ok and hp and hp > 0 then return false end
            end
            return true
        end),

        -- Navigate to next waypoint
        BT.Action:new("explore_waypoint", function()
            if exploration_service then
                local ok = pcall(function()
                    exploration_service:tick()
                end)
                if not ok then return S.FAILURE end
            end

            -- Check if we have an active exploration destination
            local dest = bb:get("exploration.destination")
            if dest and navigation and navigation.move_to then
                pcall(function() navigation:move_to(dest) end)
                return S.RUNNING
            end

            return S.RUNNING  -- keep exploring
        end),
    })
end

return ExploreSubTree
