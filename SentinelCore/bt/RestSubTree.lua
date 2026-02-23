local BT = require("ai/BehaviorTree")
local S = BT.Status

local RestSubTree = {}

function RestSubTree.build(bb)
    local rest_start_time = nil

    return BT.Sequence:new("rest", {
        -- Gate: needs recovery and not in combat
        BT.Condition:new("needs_rest", function()
            if bb:get("player.in_combat", false) then return false end
            local hp = bb:get("player.health", 0)
            local max_hp = bb:get("player.max_health", 1)
            local hp_pct = max_hp > 0 and (hp / max_hp) or 1
            return hp_pct < 0.80
        end),

        -- Eat/drink action
        BT.Action:new("eat_drink", function()
            if not rest_start_time then
                rest_start_time = core.time()
                bb:set("combat.was_resting", true)
            end

            -- Check if recovered
            local hp = bb:get("player.health", 0)
            local max_hp = bb:get("player.max_health", 1)
            local hp_pct = max_hp > 0 and (hp / max_hp) or 1

            if hp_pct >= 0.90 then
                rest_start_time = nil
                bb:set("combat.was_resting", false)
                return S.SUCCESS
            end

            -- Interrupted by combat
            if bb:get("player.in_combat", false) then
                rest_start_time = nil
                bb:set("combat.was_resting", false)
                return S.FAILURE
            end

            return S.RUNNING
        end),
    })
end

return RestSubTree
