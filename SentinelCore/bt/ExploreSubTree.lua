local BT = require("ai/BehaviorTree")
local S = BT.Status

local ExploreSubTree = {}

function ExploreSubTree.build(bb, navigation, exploration_service)
    return BT.ReactiveSequence:new("explore", {
        -- Gate: nothing else to do (re-evaluated every tick)
        BT.Condition:new("idle", function()
            if bb:get("player.in_combat", false) then return false end
            if bb:get("player.is_dead", false) then return false end
            if bb:get("player.is_ghost", false) then return false end
            local target = bb:get("combat.target")
            if target then
                local ok, hp = pcall(function() return target:get_health() end)
                if ok and hp and hp > 0 then return false end
            end
            return true
        end),

        -- Navigate to next waypoint
        BT.Action:new("explore_waypoint", function()
            -- Let ExplorationService select and navigate to the next destination.
            -- ExplorationService.tick() handles frontier/pursuit selection and
            -- issues navigation commands internally via NavigationAdapter.
            if exploration_service and exploration_service.tick then
                local ok = pcall(function()
                    exploration_service:tick()
                end)
                if not ok then return S.FAILURE end
            end

            -- Check if exploration has an active destination
            local dest = bb:get("exploration.destination")
            if dest then
                return S.RUNNING
            end

            -- No destination — exploration has nothing to do
            return S.FAILURE
        end),
    })
end

return ExploreSubTree
