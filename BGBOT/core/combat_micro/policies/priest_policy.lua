---@module BGBOT.core.combat_micro.policies.priest_policy
-- Priest combat micro profile with deterministic support/shadow modes.

local constants = require("shared/constants")
local utils = require("shared/utils")

local priest_policy = {}
priest_policy.__index = priest_policy

function priest_policy.new(generic_policy, mode)
    return setmetatable({
        generic = generic_policy,
        mode = tostring(mode or "support"),
    }, priest_policy)
end

function priest_policy:get_min_target_score(_world_model, _intent_context)
    if self.mode == "shadow" then
        return math.max(12, tonumber(constants.COMBAT.TARGET_SCORE_MIN) or 10)
    end
    return math.max(22, tonumber(constants.COMBAT.TARGET_SCORE_MIN) or 10)
end

function priest_policy:score_adjustment(enemy, world_model, _intent_context)
    local self_state = world_model and world_model:get_self() or nil
    if not self_state or not self_state.position or not enemy or not enemy.position then
        return 0
    end

    local score = 0
    local dist = utils.distance_3d(self_state.position, enemy.position)
    local self_hp = tonumber(self_state.health_pct) or 100

    if enemy.has_flag then
        score = score + 20
    end

    if enemy.is_casting then
        score = score + 10
    end

    if tonumber(enemy.group_role) == constants.GROUP_ROLE.HEALER then
        score = score + 6
    end

    if self.mode == "shadow" then
        if dist <= 20 then
            score = score + 8
        elseif dist > 32 then
            score = score - 8
        end
        return score
    end

    -- Support profile: conserve aggression unless threat is local/objective.
    if dist <= 18 then
        score = score + 4
    elseif dist > 28 then
        score = score - 20
    end

    if self_hp < 40 then
        score = score - 25
    end

    return score
end

function priest_policy:get_next_action(target, world_model, intent_context)
    local cmd = self.generic:get_next_action(target, world_model, intent_context)
    if not cmd then return nil end

    local self_state = world_model and world_model:get_self() or nil
    if not self_state or not self_state.position or not target or not target.position then
        return cmd
    end

    local dist = utils.distance_3d(self_state.position, target.position)
    if self.mode == "shadow" then
        if dist < 15.0 then
            local dx = self_state.position.x - target.position.x
            local dy = self_state.position.y - target.position.y
            local len = math.sqrt(dx*dx + dy*dy)
            if len > 0.1 then
                cmd.movement_override = {
                    x = self_state.position.x + (dx / len) * 10.0,
                    y = self_state.position.y + (dy / len) * 10.0,
                    z = self_state.position.z
                }
            end
        elseif dist >= 15.0 and dist <= 30.0 then
            cmd.halt_movement = true
        end
    else
        -- Support: stay further back
        if dist < 20.0 then
            local dx = self_state.position.x - target.position.x
            local dy = self_state.position.y - target.position.y
            local len = math.sqrt(dx*dx + dy*dy)
            if len > 0.1 then
                cmd.movement_override = {
                    x = self_state.position.x + (dx / len) * 15.0,
                    y = self_state.position.y + (dy / len) * 15.0,
                    z = self_state.position.z
                }
            end
        elseif dist >= 25.0 and dist <= 35.0 then
            cmd.halt_movement = true
        end
    end

    return cmd
end

return priest_policy
