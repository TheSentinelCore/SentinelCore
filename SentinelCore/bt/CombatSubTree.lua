local BT = require("ai/BehaviorTree")
local CombatContext = require("ai/CombatContext")
local S = BT.Status

local CombatSubTree = {}

function CombatSubTree.build(bb, evaluator, swing_timer, human_timing, spell_executor, navigation)
    local pending_action = nil
    local pending_delay_until = nil
    local combat_start_time = nil
    local last_chase_dest = nil
    local chase_repath_pending = false

    return BT.ReactiveSequence:new("combat", {
        -- Gate: must be in combat WITH a valid living target.
        -- If in combat but target is dead/nil, fail so FindTargetSubTree can acquire the next mob.
        -- Also resets closure state when combat ends to avoid stale data in next fight.
        BT.Condition:new("in_combat", function()
            local in_combat = bb:get("player.in_combat", false)
                or bb:get("combat.has_aggro", false)
            if not in_combat then
                combat_start_time = nil
                pending_action = nil
                pending_delay_until = nil
                last_chase_dest = nil
                chase_repath_pending = false
                return false
            end
            -- Require a valid living target to proceed with combat actions
            local target = bb:get("combat.target")
            if not target then return false end
            local ok, hp = pcall(function() return target:get_health() end)
            if not ok or not hp or hp <= 0 then return false end
            return true
        end),

        -- Track combat start
        BT.Action:new("track_combat_time", function()
            if not combat_start_time then
                combat_start_time = core.time()
            end
            bb:set("combat.time_in_combat", core.time() - combat_start_time)
            return S.SUCCESS
        end),

        -- Chase: close distance to melee range (handles knockback, fleeing mobs)
        BT.Action:new("chase_target", function()
            local target = bb:get("combat.target")
            if not target then return S.SUCCESS end

            local ok, tpos = pcall(function() return target:get_position() end)
            if not ok or not tpos then return S.SUCCESS end

            local player_pos = bb:get("player.position")
            if not player_pos then return S.SUCCESS end

            local dx = (tpos.x or 0) - (player_pos.x or 0)
            local dy = (tpos.y or 0) - (player_pos.y or 0)
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist <= 5 then
                -- In melee range: stop nav if still chasing
                if navigation and navigation:is_moving() then
                    pcall(function() navigation:stop() end)
                    last_chase_dest = nil
                    chase_repath_pending = false
                end
                return S.SUCCESS
            end

            -- Too far — chase (two-phase smooth movement)
            if navigation then
                if not navigation:is_moving() and not chase_repath_pending then
                    last_chase_dest = tpos
                    pcall(function() navigation:move_to(tpos) end)
                elseif navigation:is_moving() and not chase_repath_pending and last_chase_dest then
                    local ddx = (tpos.x or 0) - (last_chase_dest.x or 0)
                    local ddy = (tpos.y or 0) - (last_chase_dest.y or 0)
                    if math.sqrt(ddx*ddx + ddy*ddy) > 3.0 then
                        chase_repath_pending = true
                        last_chase_dest = tpos
                        pcall(function()
                            navigation:soft_repath(tpos, function()
                                chase_repath_pending = false
                            end)
                        end)
                    end
                end
            end

            return S.SUCCESS  -- don't block rotation while chasing
        end),

        -- Facing
        BT.Action:new("face_target", function()
            local target = bb:get("combat.target")
            if not target then return S.SUCCESS end
            local ok, pos = pcall(function() return target:get_position() end)
            if ok and pos and core.input and core.input.look_at then
                pcall(function() core.input.look_at(pos) end)
            end
            return S.SUCCESS
        end),

        -- Evaluate + execute
        BT.Action:new("evaluate_and_execute", function()
            local now = core.time()

            -- If we have a pending action with human delay, wait
            if pending_action and pending_delay_until and now < pending_delay_until then
                return S.RUNNING
            end

            -- Execute pending action if delay expired
            if pending_action then
                local action = pending_action
                pending_action = nil
                pending_delay_until = nil
                if spell_executor then
                    spell_executor(action)
                end
                return S.RUNNING
            end

            -- Build context and evaluate
            local ctx = CombatContext.build(bb, swing_timer)
            local result = evaluator:evaluate(ctx)

            if not result then
                return S.RUNNING  -- nothing scored, wait for GCD/cooldowns
            end

            -- Apply human timing delay
            local delay = human_timing:get_action_delay(result.action.intent or "rotation")
            pending_action = result.action
            pending_delay_until = now + delay
            return S.RUNNING
        end),
    })
end

return CombatSubTree
