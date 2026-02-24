local BT = require("ai/BehaviorTree")
local S = BT.Status

local LootSubTree = {}

function LootSubTree.build(bb, navigation)
    local last_loot_dest = nil
    local loot_repath_pending = false

    return BT.ReactiveSequence:new("loot", {
        -- Gate: has pending loot target and not in combat.
        -- Auto-detects kills: if combat.target is dead, promotes it to loot.pending_target.
        -- Resets closure nav state when gate fails to avoid stale data.
        BT.Condition:new("has_lootable", function()
            if bb:get("player.in_combat", false) then
                last_loot_dest = nil
                loot_repath_pending = false
                return false
            end

            local pending = bb:get("loot.pending_target")
            if pending then return true end

            -- Kill detection: combat.target dead → mark for looting
            local target = bb:get("combat.target")
            if target then
                local ok, dead = pcall(function() return target:is_dead() end)
                if ok and dead then
                    bb:set("loot.pending_target", target)
                    bb:clear("combat.target")
                    return true
                end
            end

            last_loot_dest = nil
            loot_repath_pending = false
            return false
        end),

        -- Navigate and loot with timeout
        BT.Timeout:new("loot_timeout", 10.0,
            BT.Action:new("navigate_and_loot", function()
                local target = bb:get("loot.pending_target")
                if not target then
                    return S.SUCCESS  -- cleared externally
                end

                -- Validate target still exists
                local ok, pos = pcall(function() return target:get_position() end)
                if not ok or not pos then
                    bb:clear("loot.pending_target")
                    last_loot_dest = nil
                    loot_repath_pending = false
                    return S.SUCCESS
                end

                -- Check distance
                local player_pos = bb:get("player.position")
                if player_pos then
                    local dx = (pos.x or 0) - (player_pos.x or 0)
                    local dy = (pos.y or 0) - (player_pos.y or 0)
                    local dist = math.sqrt(dx*dx + dy*dy)

                    if dist > 5 then
                        -- Two-phase: move_to when idle, soft_repath if corpse drifted
                        if navigation then
                            if not navigation:is_moving() and not loot_repath_pending then
                                last_loot_dest = pos
                                pcall(function() navigation:move_to(pos) end)
                            elseif navigation:is_moving() and not loot_repath_pending and last_loot_dest then
                                local ddx = (pos.x or 0) - (last_loot_dest.x or 0)
                                local ddy = (pos.y or 0) - (last_loot_dest.y or 0)
                                if math.sqrt(ddx*ddx + ddy*ddy) > 3.0 then
                                    loot_repath_pending = true
                                    last_loot_dest = pos
                                    pcall(function()
                                        navigation:soft_repath(pos, function()
                                            loot_repath_pending = false
                                        end)
                                    end)
                                end
                            end
                        end
                        return S.RUNNING
                    end
                end

                -- Close enough: stop nav, loot the corpse
                if navigation and navigation:is_moving() then
                    pcall(function() navigation:stop() end)
                end
                if core.input and core.input.loot_object then
                    pcall(function() core.input.loot_object(target) end)
                end
                bb:clear("loot.pending_target")
                last_loot_dest = nil
                loot_repath_pending = false
                return S.SUCCESS
            end)
        ),
    })
end

return LootSubTree
