local PathEntropy = {}
PathEntropy.__index = PathEntropy

local DEFAULT_CONFIG = {
    waypoint_jitter_radius = 3.0,
    suboptimal_path_chance = 0.08,
    micro_pause_chance = 0.03,
    micro_pause_duration_min = 0.5,
    micro_pause_duration_max = 1.5,
    approach_angle_jitter = 15,
}

function PathEntropy:new(config)
    local o = setmetatable({}, PathEntropy)
    config = config or {}
    o._cfg = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        o._cfg[k] = config[k] or v
    end
    o._pause_until = nil
    return o
end

function PathEntropy:jitter_position(pos)
    local angle = math.random() * 2 * math.pi
    local radius = math.random() * self._cfg.waypoint_jitter_radius
    return {
        x = (pos.x or 0) + math.cos(angle) * radius,
        y = (pos.y or 0) + math.sin(angle) * radius,
        z = pos.z or 0,
    }
end

function PathEntropy:should_pick_suboptimal()
    return math.random() < self._cfg.suboptimal_path_chance
end

function PathEntropy:should_micro_pause()
    return math.random() < self._cfg.micro_pause_chance
end

function PathEntropy:get_micro_pause_duration()
    return self._cfg.micro_pause_duration_min
        + math.random() * (self._cfg.micro_pause_duration_max - self._cfg.micro_pause_duration_min)
end

function PathEntropy:jitter_approach_angle(dx, dy)
    local jitter_deg = (math.random() * 2 - 1) * self._cfg.approach_angle_jitter
    local jitter_rad = jitter_deg * math.pi / 180
    local cos_j = math.cos(jitter_rad)
    local sin_j = math.sin(jitter_rad)
    return dx * cos_j - dy * sin_j, dx * sin_j + dy * cos_j
end

function PathEntropy:check_pause(now)
    if self._pause_until and now < self._pause_until then
        return true
    end
    self._pause_until = nil
    if self:should_micro_pause() then
        self._pause_until = now + self:get_micro_pause_duration()
        return true
    end
    return false
end

return PathEntropy
