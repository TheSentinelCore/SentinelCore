local BT = require("ai/BehaviorTree")
local S = BT.Status

local PullSubTree = {}

function PullSubTree.build(bb, navigation)
    local last_dest = nil
    local repath_pending = false
    local pull_attack_sent = false

    return BT.ReactiveSequence:new("pull", {
        -- Gate: has valid target and not yet in combat (re-evaluated every tick)
        -- Resets closure state when gate fails to avoid stale nav data on next pull.
        BT.Condition:new("has_valid_target", function()
            if bb:get("player.in_combat", false) then
                last_dest = nil
                repath_pending = false
                pull_attack_sent = false
                return false
            end
            local target = bb:get("combat.target")
            if not target then
                last_dest = nil
                repath_pending = false
                pull_attack_sent = false
                return false
            end
            local ok, hp = pcall(function() return target:get_health() end)
            if not ok or not hp or hp <= 0 then
                last_dest = nil
                repath_pending = false
                pull_attack_sent = false
                return false
            end
            return true
        end),

        -- Navigate to pull range with timeout
        BT.Timeout:new("pull_timeout", 12.0,
            BT.Action:new("navigate_and_pull", function()
                local target = bb:get("combat.target")
                if not target then return S.FAILURE end

                -- Check if in combat already (pull succeeded)
                if bb:get("player.in_combat", false) then
                    last_dest = nil
                    repath_pending = false
                    pull_attack_sent = false
                    return S.SUCCESS
                end

                local ok, tpos = pcall(function() return target:get_position() end)
                if not ok or not tpos then return S.FAILURE end

                local player_pos = bb:get("player.position")
                if not player_pos then return S.FAILURE end

                local dx = (tpos.x or 0) - (player_pos.x or 0)
                local dy = (tpos.y or 0) - (player_pos.y or 0)
                local dist = math.sqrt(dx * dx + dy * dy)

                -- Navigate toward target (two-phase: move_to when idle, soft_repath while moving)
                if dist > 5 and navigation then
                    if not navigation:is_moving() and not repath_pending then
                        last_dest = tpos
                        pcall(function() navigation:move_to(tpos) end)
                    elseif navigation:is_moving() and not repath_pending and last_dest then
                        local ddx = (tpos.x or 0) - (last_dest.x or 0)
                        local ddy = (tpos.y or 0) - (last_dest.y or 0)
                        if math.sqrt(ddx*ddx + ddy*ddy) > 3.0 then
                            repath_pending = true
                            last_dest = tpos
                            pcall(function()
                                navigation:soft_repath(tpos, function()
                                    repath_pending = false
                                end)
                            end)
                        end
                    end
                end

                -- Ranged pull: cast Judgement at 10yd if available (don't stop nav)
                -- Cooldown check prevents spam naturally — no flag needed.
                if dist <= 10 and dist > 5 then
                    if core.input and core.input.set_target and core.input.cast_target_spell
                        and core.spell_book and core.spell_book.get_spell_cooldown then
                        local cd_ok, cd = pcall(core.spell_book.get_spell_cooldown, 20271)
                        if cd_ok and cd and cd <= 0 then
                            pcall(function()
                                core.input.set_target(target)
                                core.input.cast_target_spell(20271, target) -- Judgement
                            end)
                        end
                    end
                end

                -- Melee range: stop nav, target, auto-attack (only once to avoid toggle spam)
                if not pull_attack_sent and dist <= 5 then
                    if navigation and navigation:is_moving() then
                        pcall(function() navigation:stop() end)
                    end
                    if core.input then
                        pcall(function()
                            if core.input.set_target then
                                core.input.set_target(target)
                            end
                            if core.input.cast_target_spell then
                                core.input.cast_target_spell(6603, target)
                            end
                        end)
                    end
                    pull_attack_sent = true
                end

                return S.RUNNING
            end)
        ),
    })
end

return PullSubTree
