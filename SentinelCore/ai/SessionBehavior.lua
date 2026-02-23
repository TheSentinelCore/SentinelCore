local SessionBehavior = {}
SessionBehavior.__index = SessionBehavior

function SessionBehavior:new(config)
    local o = setmetatable({}, SessionBehavior)
    config = config or {}
    o._session_start = nil
    o._idle_check_interval = config.idle_check_interval or 300
    o._idle_pause_chance = config.idle_pause_chance or 0.05
    o._idle_pause_min = config.idle_pause_min or 2.0
    o._idle_pause_max = config.idle_pause_max or 8.0
    o._fatigue_ramp_minutes = config.fatigue_ramp_minutes or 60
    o._next_idle_check = 0
    o._pause_until = nil
    return o
end

function SessionBehavior:start(now)
    self._session_start = now
    self._next_idle_check = now + self._idle_check_interval
end

function SessionBehavior:get_fatigue_factor(now)
    if not self._session_start then return 1.0 end
    local elapsed_min = (now - self._session_start) / 60
    local factor = 1.0 + (elapsed_min / self._fatigue_ramp_minutes) * 0.3
    if factor > 1.5 then factor = 1.5 end
    return factor
end

function SessionBehavior:check_idle_pause(now)
    if self._pause_until and now < self._pause_until then
        return true
    end
    self._pause_until = nil

    if now < self._next_idle_check then
        return false
    end
    self._next_idle_check = now + self._idle_check_interval

    if math.random() < self._idle_pause_chance then
        local dur = self._idle_pause_min
            + math.random() * (self._idle_pause_max - self._idle_pause_min)
        self._pause_until = now + dur
        return true
    end
    return false
end

return SessionBehavior
