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
    -- Randomize next check interval ±33% to avoid a detectable fixed 300s cadence.
    local jitter = self._idle_check_interval * (0.67 + math.random() * 0.66)
    self._next_idle_check = now + jitter

    if math.random() < self._idle_pause_chance then
        local dur = self._idle_pause_min
            + math.random() * (self._idle_pause_max - self._idle_pause_min)
        self._pause_until = now + dur
        return true
    end
    return false
end

--- Cancel any active idle pause immediately.
--- Called by the grind loop when combat interrupts a pause so the bot does
--- not resume the same pause window after combat ends (phantom pause bug).
function SessionBehavior:cancel_pause()
    self._pause_until = nil
end

return SessionBehavior
