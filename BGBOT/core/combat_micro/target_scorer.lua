---@module BGBOT.core.combat_micro.target_scorer
-- Lightweight PvP target scoring for combat micro.

local constants = require("shared/constants")
local config    = require("shared/config")
local utils     = require("shared/utils")

local scorer = {}

local function same_handle(a, b)
    if not a or not b then
        return false
    end
    return tostring(a) == tostring(b)
end

---Score an enemy entity for target selection.
---@param enemy EntityRecord
---@param world_model WorldModel
---@param intent_context table|nil
---@return number
function scorer.score_target(enemy, world_model, intent_context)
    if not enemy or enemy.is_dead then
        return -999
    end

    local self_state = world_model and world_model:get_self() or nil
    if not self_state or not self_state.position or not enemy.position then
        return -999
    end

    local score = 0
    local hp = tonumber(enemy.health_pct) or 100
    local max_chase = tonumber(intent_context and intent_context.max_chase_range)
        or tonumber(config.combat.chase_range)
        or constants.COMBAT.DEFAULT_CHASE_RANGE
    local dist = utils.distance_3d(self_state.position, enemy.position)

    -- Kill opportunity.
    if hp < 20 then
        score = score + 40
    elseif hp < 40 then
        score = score + 25
    elseif hp < 60 then
        score = score + 10
    end

    -- Objective pressure.
    if enemy.has_flag then
        score = score + 50
    end

    -- Caster pressure/interrupt opportunity.
    if enemy.is_casting then
        score = score + 20
    end

    -- Healer pressure.
    if tonumber(enemy.group_role) == constants.GROUP_ROLE.HEALER then
        score = score + 15
    end

    -- Distance budget.
    if dist <= 10 then
        score = score + 15
    elseif dist <= 20 then
        score = score + 10
    elseif dist <= 30 then
        score = score + 5
    else
        score = score - 8
    end

    -- Intent hint.
    if intent_context and intent_context.priority_target
        and same_handle(enemy.handle, intent_context.priority_target) then
        score = score + 25
    end

    if dist > max_chase then
        score = score - 40
    end

    -- De-prioritize stale observations.
    local confidence = tonumber(enemy.confidence) or 0
    if confidence < 0.2 then
        score = score - 30
    elseif confidence < 0.5 then
        score = score - 10
    end

    return score
end

return scorer
