local BT = require("ai/BehaviorTree")
local S = BT.Status

local PullSubTree = {}

function PullSubTree.build(bb, navigation)
    return BT.Sequence:new("pull", {
        -- Gate: has valid target and ready to pull
        BT.Condition:new("has_valid_target", function()
            local target = bb:get("combat.target")
            if not target then return false end
            local ok, hp = pcall(function() return target:get_health() end)
            return ok and hp and hp > 0
        end),

        -- Navigate to pull range with timeout
        BT.Timeout:new("pull_timeout", 12.0,
            BT.Action:new("navigate_and_pull", function()
                local target = bb:get("combat.target")
                if not target then return S.FAILURE end

                -- Check if in combat already (pull succeeded)
                if bb:get("player.in_combat", false) then
                    return S.SUCCESS
                end

                local ok, tpos = pcall(function() return target:get_position() end)
                if not ok or not tpos then return S.FAILURE end

                local player_pos = bb:get("player.position")
                if not player_pos then return S.FAILURE end

                local dx = (tpos.x or 0) - (player_pos.x or 0)
                local dy = (tpos.y or 0) - (player_pos.y or 0)
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist > 30 then
                    -- Too far, navigate closer
                    if navigation and navigation.move_to then
                        pcall(function() navigation:move_to(tpos) end)
                    end
                    return S.RUNNING
                end

                -- In pull range, auto-attack to pull
                if core.input and core.input.attack_target then
                    pcall(function() core.input.attack_target(target) end)
                end
                return S.RUNNING
            end)
        ),
    })
end

return PullSubTree
