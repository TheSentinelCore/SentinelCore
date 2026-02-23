local BT = require("ai/BehaviorTree")
local S = BT.Status

local LootSubTree = {}

function LootSubTree.build(bb, navigation)
    return BT.Sequence:new("loot", {
        -- Gate: has lootable corpse nearby and not in combat
        BT.Condition:new("has_lootable", function()
            local lootables = bb:get("loot.lootable_objects")
            return lootables and #lootables > 0
                and not bb:get("player.in_combat", false)
        end),

        -- Navigate and loot with timeout
        BT.Timeout:new("loot_timeout", 8.0,
            BT.Action:new("navigate_and_loot", function()
                local lootables = bb:get("loot.lootable_objects")
                if not lootables or #lootables == 0 then
                    return S.SUCCESS  -- nothing left to loot
                end

                local target = lootables[1]
                local ok, pos = pcall(function() return target:get_position() end)
                if not ok or not pos then
                    return S.FAILURE
                end

                -- Check distance
                local player_pos = bb:get("player.position")
                if player_pos then
                    local dx = (pos.x or 0) - (player_pos.x or 0)
                    local dy = (pos.y or 0) - (player_pos.y or 0)
                    local dist = math.sqrt(dx*dx + dy*dy)

                    if dist > 5 then
                        -- Navigate to lootable
                        if navigation and navigation.move_to then
                            pcall(function() navigation:move_to(pos) end)
                        end
                        return S.RUNNING
                    end
                end

                -- Close enough, loot
                if core.input and core.input.loot_object then
                    pcall(function() core.input.loot_object(target) end)
                end
                return S.RUNNING
            end)
        ),
    })
end

return LootSubTree
