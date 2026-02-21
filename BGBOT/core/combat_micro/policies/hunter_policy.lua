---@module BGBOT.core.combat_micro.policies.hunter_policy
-- Hunter combat micro profile (distance tether class behaviors).

local constants = require("shared/constants")
local utils = require("shared/utils")

local hunter_policy = {}
hunter_policy.__index = hunter_policy

function hunter_policy.new(generic_policy)
    return setmetatable({
        generic = generic_policy,
    }, hunter_policy)
end

function hunter_policy:get_min_target_score(_world_model, _intent_context)
    return math.max(12, tonumber(constants.COMBAT.TARGET_SCORE_MIN) or 10)
end

function hunter_policy:score_adjustment(enemy, world_model, _intent_context)
    local self_state = world_model and world_model:get_self() or nil
    if not self_state or not self_state.position or not enemy or not enemy.position then
        return 0
    end

    local score = 0
    local dist = utils.distance_3d(self_state.position, enemy.position)

    if dist < 8 then
        score = score - 15 -- Dislike dead zone / melee
    elseif dist >= 15 and dist <= 35 then
        score = score + 15 -- Ideal range
    else
        score = score - 5
    end

    if enemy.has_flag then
        score = score + 12
    end

    return score
end

function hunter_policy:get_next_action(target, world_model, intent_context)
    local cmd = self.generic:get_next_action(target, world_model, intent_context)
    if not cmd then return nil end

    local self_state = world_model and world_model:get_self() or nil
    if not self_state or not self_state.position or not target or not target.position then
        return cmd
    end

    local dist = utils.distance_3d(self_state.position, target.position)
    if dist < 12.0 then
        -- Kite away
        local dx = self_state.position.x - target.position.x
        local dy = self_state.position.y - target.position.y
        local dz = self_state.position.z - target.position.z
        local len = math.sqrt(dx*dx + dy*dy + dz*dz)
        if len > 0.1 then
            cmd.movement_override = {
                x = self_state.position.x + (dx / len) * 20.0,
                y = self_state.position.y + (dy / len) * 20.0,
                z = self_state.position.z
            }
        end
    elseif dist >= 25.0 and dist <= 35.0 then
        cmd.halt_movement = true
    end

    return cmd
end

return hunter_policy
