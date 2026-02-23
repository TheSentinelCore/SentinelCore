local BT = require("ai/BehaviorTree")
local S = BT.Status

local FindTargetSubTree = {}

function FindTargetSubTree.build(bb, targeting_service)
    return BT.Sequence:new("find_target", {
        -- Gate: no valid target currently
        BT.Condition:new("no_target", function()
            local target = bb:get("combat.target")
            if not target then return true end
            local ok, hp = pcall(function() return target:get_health() end)
            if not ok or not hp or hp <= 0 then return true end
            return false
        end),

        -- Scan and select
        BT.Action:new("scan_score_select", function()
            if not targeting_service then return S.FAILURE end

            local ok, target = pcall(function()
                return targeting_service:acquire_target()
            end)

            if ok and target then
                bb:set("combat.target", target)
                return S.SUCCESS
            end

            return S.FAILURE
        end),
    })
end

return FindTargetSubTree
