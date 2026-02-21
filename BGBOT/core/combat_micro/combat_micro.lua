---@module BGBOT.core.combat_micro.combat_micro
-- Combat micro orchestrator: picks target and emits lightweight combat commands.

local constants = require("shared/constants")
local config    = require("shared/config")
local scorer    = require("core/combat_micro/target_scorer")
local Generic   = require("core/combat_micro/generic_combat")
local MagePolicy = require("core/combat_micro/policies/mage_policy")
local RoguePolicy = require("core/combat_micro/policies/rogue_policy")
local PriestPolicy = require("core/combat_micro/policies/priest_policy")

local combat_micro = {}
combat_micro.__index = combat_micro

function combat_micro.new()
    local self = setmetatable({}, combat_micro)
    self.generic_policy = Generic.new()
    self.policies = {
        generic = self.generic_policy,
        mage = MagePolicy.new(self.generic_policy),
        rogue = RoguePolicy.new(self.generic_policy),
        priest_support = PriestPolicy.new(self.generic_policy, "support"),
        priest_shadow = PriestPolicy.new(self.generic_policy, "shadow"),
    }
    self._active_policy = self.generic_policy
    self._active_policy_id = "generic"
    self._last_target = nil
    self._last_score = 0
    return self
end

local function resolve_policy_id(self_state)
    local class_id = tonumber(self_state and self_state.class_id) or 0
    local spec_id = tonumber(self_state and self_state.spec_id) or 0

    if class_id == constants.CLASS.MAGE then
        return "mage"
    end

    if class_id == constants.CLASS.ROGUE then
        return "rogue"
    end

    if class_id == constants.CLASS.PRIEST then
        -- Use specialization when available; fall back to support profile.
        if spec_id == 3 or spec_id == 258 then
            return "priest_shadow"
        end
        return "priest_support"
    end

    return "generic"
end

function combat_micro:resolve_policy(world_model)
    local self_state = world_model and world_model:get_self() or nil
    local policy_id = resolve_policy_id(self_state)
    local policy = self.policies[policy_id] or self.generic_policy

    self._active_policy = policy
    self._active_policy_id = policy_id
    return policy, policy_id
end

---Current resolved policy id.
---@return string
function combat_micro:get_active_policy_id()
    return tostring(self._active_policy_id or "generic")
end

---Select best target using score thresholds and intent constraints.
---@param world_model WorldModel
---@param intent_context table|nil
---@return EntityRecord|nil, number, table
function combat_micro:select_target(world_model, intent_context, policy)
    local self_state = world_model and world_model:get_self() or nil
    if not self_state or self_state.is_dead or self_state.is_ghost then
        return nil, -999, policy or self.generic_policy
    end

    if intent_context and intent_context.engage_allowed == false then
        return nil, -999, policy or self.generic_policy
    end

    local active_policy = policy or self.generic_policy
    local enemies = world_model:get_enemies()
    local best_target = nil
    local best_score = -999

    for _, enemy in ipairs(enemies) do
        local score = scorer.score_target(enemy, world_model, intent_context)
        if active_policy and active_policy.score_adjustment then
            score = score + (tonumber(active_policy:score_adjustment(enemy, world_model, intent_context)) or 0)
        end
        if score > best_score then
            best_score = score
            best_target = enemy
        end
    end

    local min_score = tonumber(config.combat.min_target_score) or constants.COMBAT.TARGET_SCORE_MIN
    if active_policy and active_policy.get_min_target_score then
        local policy_min = tonumber(active_policy:get_min_target_score(world_model, intent_context))
        if policy_min and policy_min > min_score then
            min_score = policy_min
        end
    end
    if best_score < min_score then
        return nil, best_score, active_policy
    end

    return best_target, best_score, active_policy
end

---Per-tick combat decision.
---@param world_model WorldModel
---@param intent_context table|nil
---@return table|nil
function combat_micro:tick(world_model, intent_context)
    local policy = self:resolve_policy(world_model)

    local target, score, active_policy = self:select_target(world_model, intent_context, policy)
    self._last_target = target and target.handle or nil
    self._last_score = score or 0

    local cmd = active_policy and active_policy:get_next_action(target, world_model, intent_context) or nil
    if not cmd and active_policy ~= self.generic_policy then
        cmd = self.generic_policy:get_next_action(target, world_model, intent_context)
    end
    if not cmd then
        return nil
    end

    cmd.selected_target = target and target.handle or nil
    cmd.target_score = score or 0
    cmd.policy_id = self:get_active_policy_id()
    return cmd
end

return combat_micro
