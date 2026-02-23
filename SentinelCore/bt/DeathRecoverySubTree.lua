local BT = require("ai/BehaviorTree")
local S = BT.Status

local DeathRecoverySubTree = {}

function DeathRecoverySubTree.build(bb, navigation)
    local release_time = nil
    local RELEASE_DELAY = 2.0  -- wait before releasing spirit

    return BT.Sequence:new("death_recovery", {
        -- Gate: must be dead or ghost
        BT.Condition:new("is_dead_or_ghost", function()
            return bb:get("player.is_dead", false)
                or bb:get("player.is_ghost", false)
        end),

        -- Phase: release spirit (when dead body, not yet ghost)
        BT.Action:new("release_spirit", function()
            if not bb:get("player.is_dead", false) then
                return S.SUCCESS  -- already ghost or alive
            end

            local now = core.time()
            if not release_time then
                release_time = now + RELEASE_DELAY + math.random() * 1.0
            end

            if now < release_time then
                return S.RUNNING  -- waiting with jitter
            end

            -- Release spirit
            release_time = nil
            if core.game_ui and core.game_ui.repop_me then
                pcall(function() core.game_ui.repop_me() end)
            end
            return S.RUNNING  -- wait for ghost state
        end),

        -- Phase: corpse run
        BT.Action:new("corpse_run", function()
            if not bb:get("player.is_ghost", false) then
                return S.SUCCESS  -- not a ghost anymore
            end

            local corpse_pos = bb:get("player.corpse_position")
            if not corpse_pos then
                return S.RUNNING  -- waiting for corpse position
            end

            -- Navigate toward corpse
            if navigation and navigation.move_to then
                pcall(function() navigation:move_to(corpse_pos) end)
            end

            -- Check if close enough to resurrect
            local player_pos = bb:get("player.position")
            if player_pos and corpse_pos then
                local dx = (corpse_pos.x or 0) - (player_pos.x or 0)
                local dy = (corpse_pos.y or 0) - (player_pos.y or 0)
                local dist = math.sqrt(dx*dx + dy*dy)
                if dist < 30 then
                    -- Attempt resurrect
                    if core.game_ui and core.game_ui.retrieve_corpse then
                        pcall(function() core.game_ui.retrieve_corpse() end)
                    end
                end
            end

            return S.RUNNING
        end),
    })
end

return DeathRecoverySubTree
