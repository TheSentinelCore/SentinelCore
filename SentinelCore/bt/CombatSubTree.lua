local BT = require("ai/BehaviorTree")
local CombatContext = require("ai/CombatContext")
local S = BT.Status

local CombatSubTree = {}

function CombatSubTree.build(bb, evaluator, swing_timer, human_timing, spell_executor)
    local pending_action = nil
    local pending_delay_until = nil
    local combat_start_time = nil

    return BT.Sequence:new("combat", {
        -- Gate: must be in combat
        BT.Condition:new("in_combat", function()
            return bb:get("player.in_combat", false)
                or bb:get("combat.has_aggro", false)
        end),

        -- Track combat start
        BT.Action:new("track_combat_time", function()
            if not combat_start_time then
                combat_start_time = core.time()
            end
            bb:set("combat.time_in_combat", core.time() - combat_start_time)
            return S.SUCCESS
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
                return S.RUNNING  -- nothing to do, wait
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
