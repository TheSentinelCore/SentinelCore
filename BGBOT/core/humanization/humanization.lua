---@module BGBOT.core.humanization.humanization
-- Humanization policy layer that modifies timing/jitter without changing strategy.

local constants = require("shared/constants")
local config    = require("shared/config")
local utils     = require("shared/utils")
local profiles  = require("core/humanization/reaction_profiles")

local humanization = {}
humanization.__index = humanization

function humanization.new()
    local self = setmetatable({}, humanization)
    self._next_target_switch_at = 0
    self._last_combat_target = nil
    self._last_intent_id = ""
    self._hesitation_until = 0
    return self
end

local function same_handle(a, b)
    if not a or not b then
        return false
    end
    return tostring(a) == tostring(b)
end

local function can_hesitate(world_model)
    local self_state = world_model and world_model:get_self() or nil
    if not self_state then
        return false
    end
    if self_state.is_in_combat then
        return false
    end
    if self_state.has_flag then
        return false
    end
    if (tonumber(self_state.health_pct) or 100) < 40 then
        return false
    end
    return true
end

local function copy_command(cmd)
    if not cmd then
        return nil
    end
    return {
        nav_goal = cmd.nav_goal,
        interact_target = cmd.interact_target,
        face_target = cmd.face_target,
        combat_target = cmd.combat_target,
        stop_attack = cmd.stop_attack == true,
    }
end

local function jitter_goal(goal, intent_id)
    if not goal or goal.x == nil or goal.y == nil or goal.z == nil then
        return goal
    end

    local j = tonumber(config.humanization.nav_jitter_yards) or 3.0
    if intent_id == "carry_flag" or intent_id == "return_flag" then
        j = 1.0
    end
    if j <= 0 then
        return goal
    end

    return {
        x = goal.x + ((math.random() - 0.5) * j * 2.0),
        y = goal.y + ((math.random() - 0.5) * j * 2.0),
        z = goal.z,
    }
end

---Apply humanization while preserving hard safety priorities.
---@param command table|nil
---@param world_model WorldModel
---@param intent_id string|nil
---@return table|nil
function humanization:apply(command, world_model, intent_id)
    if not command then
        return nil
    end

    if not config.humanization or config.humanization.enabled == false then
        return command
    end

    local now = core.time()
    local out = copy_command(command)
    local current_intent = tostring(intent_id or "")

    local bg = world_model and world_model:get_bg_state() or nil
    local fatigue = profiles.compute_fatigue_factor(
        bg and bg.run_time or 0,
        config.humanization.fatigue_enabled ~= false,
        config.humanization.fatigue_max_factor
    )

    -- Intent-switch hesitation (small, suppressed in risky contexts).
    if current_intent ~= "" and current_intent ~= self._last_intent_id then
        self._last_intent_id = current_intent
        local chance = tonumber(config.humanization.hesitation_chance) or 0.08
        if can_hesitate(world_model) and math.random() <= chance then
            local min_h = tonumber(constants.HUMAN.HESITATION_MIN) or 0.2
            local max_h = tonumber(constants.HUMAN.HESITATION_MAX) or 0.6
            local span = math.max(0, max_h - min_h)
            self._hesitation_until = now + min_h + (math.random() * span)
        end
    end

    if self._hesitation_until > now and not out.interact_target then
        -- During hesitation, pause movement but keep combat emergency flags.
        out.nav_goal = nil
    end

    -- Target-switch reaction delay (does not block objective interaction).
    if out.combat_target and not out.interact_target then
        if not same_handle(out.combat_target, self._last_combat_target) then
            self._last_combat_target = out.combat_target
            local delay_ms = profiles.compute_delay_ms("target_switch", fatigue)
            self._next_target_switch_at = now + (delay_ms / 1000.0)
        end

        if now < self._next_target_switch_at then
            out.combat_target = nil
            if out.face_target and not out.interact_target then
                out.face_target = nil
            end
        end
    end

    if out.nav_goal then
        out.nav_goal = jitter_goal(out.nav_goal, current_intent)
    end

    return out
end

return humanization
