---@module BGBOT.core.humanization.reaction_profiles
-- Reaction profile lookup and delay computation.

local profiles = {}

profiles.TABLE = {
    target_switch  = { base_ms = 200, jitter_ms = 400 },
    interrupt      = { base_ms = 150, jitter_ms = 350 },
    flag_interact  = { base_ms = 100, jitter_ms = 300 },
    spell_cast     = { base_ms = 50,  jitter_ms = 200 },
    movement_start = { base_ms = 100, jitter_ms = 200 },
}

function profiles.get(action_type)
    return profiles.TABLE[action_type]
end

function profiles.compute_delay_ms(action_type, multiplier)
    local p = profiles.get(action_type)
    if not p then
        return 0
    end

    local m = tonumber(multiplier) or 1.0
    local delay = (p.base_ms + (math.random() * p.jitter_ms)) * m
    if delay < 0 then
        return 0
    end
    return delay
end

function profiles.compute_fatigue_factor(run_time_ms, enabled, max_factor)
    if not enabled then
        return 1.0
    end

    local max_f = tonumber(max_factor) or 1.4
    local minutes = (tonumber(run_time_ms) or 0) / 60000.0
    local factor = 1.0 + (minutes * 0.015)
    if factor > max_f then
        factor = max_f
    end
    if factor < 1.0 then
        factor = 1.0
    end
    return factor
end

return profiles
