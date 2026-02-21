---@module BGBOT.core.combat_micro.policies.mage_policy
-- Mage combat micro profile (ranged pressure and anti-melee bias).

local constants = require("shared/constants")
local utils = require("shared/utils")

local mage_policy = {}
mage_policy.__index = mage_policy

function mage_policy.new(generic_policy)
    return setmetatable({
        generic = generic_policy,
    }, mage_policy)
end

function mage_policy:get_min_target_score(_world_model, _intent_context)
    return math.max(12, tonumber(constants.COMBAT.TARGET_SCORE_MIN) or 10)
end

function mage_policy:score_adjustment(enemy, world_model, _intent_context)
    local self_state = world_model and world_model:get_self() or nil
    if not self_state or not self_state.position or not enemy or not enemy.position then
        return 0
    end

    local score = 0
    local dist = utils.distance_3d(self_state.position, enemy.position)

    -- Mage profile: prefer mid-range pressure and kite-space.
    if dist < 8 then
        score = score - 18
    elseif dist <= 30 then
        score = score + 10
    else
        score = score - 6
    end

    if enemy.is_casting then
        score = score + 8
    end

    if enemy.has_flag then
        score = score + 12
    end

    return score
end

function mage_policy:get_next_action(target, world_model, intent_context)
    return self.generic:get_next_action(target, world_model, intent_context)
end

return mage_policy
