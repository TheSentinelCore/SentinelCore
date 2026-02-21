---@module BGBOT.core.combat_micro.policies.warrior_policy
-- Warrior combat micro profile (sticky melee intercept).

local constants = require("shared/constants")
local utils = require("shared/utils")

local warrior_policy = {}
warrior_policy.__index = warrior_policy

function warrior_policy.new(generic_policy)
    return setmetatable({
        generic = generic_policy,
    }, warrior_policy)
end

function warrior_policy:get_min_target_score(_world_model, _intent_context)
    return math.max(10, tonumber(constants.COMBAT.TARGET_SCORE_MIN) or 10)
end

function warrior_policy:score_adjustment(enemy, world_model, _intent_context)
    local self_state = world_model and world_model:get_self() or nil
    if not self_state or not self_state.position or not enemy or not enemy.position then
        return 0
    end

    local score = 0
    local dist = utils.distance_3d(self_state.position, enemy.position)

    -- Sticky melee: prefer close targets
    if dist <= 12 then
        score = score + 15
    elseif dist <= 25 then
        score = score + 5
    else
        score = score - 10
    end

    if enemy.is_casting then
        score = score + 5
    end

    if enemy.has_flag then
        score = score + 15
    end

    return score
end

function warrior_policy:get_next_action(target, world_model, intent_context)
    local cmd = self.generic:get_next_action(target, world_model, intent_context)
    if not cmd then return nil end

    local self_state = world_model and world_model:get_self() or nil
    if not self_state or not self_state.position or not target or not target.position then
        return cmd
    end

    local dist = utils.distance_3d(self_state.position, target.position)
    if dist >= 3.0 and dist <= 25.0 then
        -- Sticky melee intercept vector directly at target
        cmd.movement_override = {
            x = target.position.x,
            y = target.position.y,
            z = target.position.z
        }
    end

    return cmd
end

return warrior_policy
