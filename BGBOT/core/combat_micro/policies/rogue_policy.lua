---@module BGBOT.core.combat_micro.policies.rogue_policy
-- Rogue combat micro profile (close-range picks and execution pressure).

local constants = require("shared/constants")
local utils = require("shared/utils")

local rogue_policy = {}
rogue_policy.__index = rogue_policy

function rogue_policy.new(generic_policy)
    return setmetatable({
        generic = generic_policy,
    }, rogue_policy)
end

function rogue_policy:get_min_target_score(_world_model, _intent_context)
    return math.max(8, tonumber(constants.COMBAT.TARGET_SCORE_MIN) or 10)
end

function rogue_policy:score_adjustment(enemy, world_model, _intent_context)
    local self_state = world_model and world_model:get_self() or nil
    if not self_state or not self_state.position or not enemy or not enemy.position then
        return 0
    end

    local score = 0
    local dist = utils.distance_3d(self_state.position, enemy.position)
    local hp = tonumber(enemy.health_pct) or 100

    if dist <= 8 then
        score = score + 15
    elseif dist <= 18 then
        score = score + 6
    else
        score = score - 16
    end

    if hp <= 45 then
        score = score + 10
    end

    if enemy.has_flag then
        score = score + 10
    end

    return score
end

function rogue_policy:get_next_action(target, world_model, intent_context)
    return self.generic:get_next_action(target, world_model, intent_context)
end

return rogue_policy
