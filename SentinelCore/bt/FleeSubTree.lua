local BT = require("ai/BehaviorTree")
local S = BT.Status

local FleeSubTree = {}

function FleeSubTree.build(bb, navigation)
    return BT.Sequence:new("flee", {
        -- Gate: should flee (overwhelmed, low HP, no cooldowns)
        BT.Condition:new("should_flee", function()
            if not bb:get("player.in_combat", false) then return false end
            local hp = bb:get("player.health", 0)
            local max_hp = bb:get("player.max_health", 1)
            local hp_pct = max_hp > 0 and (hp / max_hp) or 1
            local enemies = bb:get("combat.enemy_count", 0)
            -- Flee if low HP with multiple enemies
            return hp_pct < 0.20 and enemies >= 2
        end),

        -- Flee action
        BT.Action:new("flee_navigate", function()
            -- Try Blessing of Freedom if snared
            if core.input and core.input.cast_self_spell then
                pcall(function() core.input.cast_self_spell(1044) end)
            end

            -- Navigate away from enemies
            local player_pos = bb:get("player.position")
            local target = bb:get("combat.target")
            if player_pos and target and navigation then
                local ok, tpos = pcall(function() return target:get_position() end)
                if ok and tpos then
                    -- Move opposite direction from enemy
                    local dx = (player_pos.x or 0) - (tpos.x or 0)
                    local dy = (player_pos.y or 0) - (tpos.y or 0)
                    local len = math.sqrt(dx*dx + dy*dy)
                    if len > 0 then
                        dx, dy = dx / len, dy / len
                    end
                    local flee_pos = {
                        x = (player_pos.x or 0) + dx * 30,
                        y = (player_pos.y or 0) + dy * 30,
                        z = player_pos.z or 0,
                    }
                    pcall(function() navigation:move_to(flee_pos) end)
                end
            end

            -- Check if out of combat
            if not bb:get("player.in_combat", false) then
                return S.SUCCESS
            end

            return S.RUNNING
        end),
    })
end

return FleeSubTree
