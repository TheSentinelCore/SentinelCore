---@class HumanTiming
local HumanTiming = {}
HumanTiming.__index = HumanTiming

function HumanTiming:new()
    local o = setmetatable({}, HumanTiming)
    o._base_reaction_sec = 0.180    -- 180ms baseline
    o._stddev_sec = 0.060           -- 60ms std dev
    o._fatigue = 0.0                -- 0-0.35 multiplier
    o._type_multipliers = {
        interrupt = 1.4,
        defensive = 1.2,
        rotation = 0.9,
        seal_twist = 0.7,
        movement = 1.0,
        loot = 1.1,
    }
    return o
end

---Approximate Gaussian using Box-Muller
local function gaussian_random(mean, stddev)
    local u1 = math.random()
    local u2 = math.random()
    if u1 < 1e-10 then u1 = 1e-10 end
    local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    return mean + z * stddev
end

---Get a human-like delay for an action type.
---@param action_type string  "rotation"|"interrupt"|"defensive"|"seal_twist"|"movement"|"loot"
---@return number  Delay in seconds (minimum 0.030)
function HumanTiming:get_action_delay(action_type)
    local mult = self._type_multipliers[action_type] or 1.0
    local base = self._base_reaction_sec * (1 + self._fatigue) * mult
    local jitter = gaussian_random(0, self._stddev_sec)
    return math.max(0.030, base + jitter)
end

---Set fatigue factor (0.0 = fresh, 0.35 = max tired).
---@param factor number
function HumanTiming:set_fatigue(factor)
    self._fatigue = math.min(factor, 0.35)
end

---Should this action "fumble" (intentionally fail for anti-detection)?
---@param rate number  Probability 0-1 (e.g., 0.05 for 5%)
---@return boolean
function HumanTiming:should_fumble(rate)
    return math.random() < rate
end

---Select from candidates with Gaussian noise on utility scores.
---@param candidates table[]  Array of { id, utility, ... }
---@param jitter_factor number  Noise as fraction of score (e.g., 0.05 = 5%)
---@return table  Selected candidate
function HumanTiming:stochastic_select(candidates, jitter_factor)
    if #candidates == 0 then return nil end
    if #candidates == 1 then return candidates[1] end

    local best = nil
    local best_noisy = -math.huge

    for i = 1, #candidates do
        local c = candidates[i]
        local noise = gaussian_random(0, c.utility * jitter_factor)
        local noisy = c.utility + noise
        if noisy > best_noisy then
            best_noisy = noisy
            best = c
        end
    end

    return best
end

return HumanTiming
