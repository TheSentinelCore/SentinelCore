---@class SwingTimer
local SwingTimer = {}
SwingTimer.__index = SwingTimer

---@param time_fn fun(): number  Returns current time in seconds
function SwingTimer:new(time_fn)
    local o = setmetatable({}, SwingTimer)
    o._time_fn = time_fn or function() return core and core.time() or 0 end
    o._last_swing = 0
    o._weapon_speed = 3.5
    o._haste_modifier = 1.0
    o._prep_threshold = 0.80   -- seconds remaining to start prep
    o._twist_threshold = 0.40  -- seconds remaining to start twist
    return o
end

function SwingTimer:set_weapon_speed(speed)
    self._weapon_speed = speed
end

function SwingTimer:set_haste_modifier(mod)
    self._haste_modifier = (mod and mod > 0.01) and mod or 0.01
end

function SwingTimer:record_swing()
    self._last_swing = self._time_fn()
end

---@return number seconds  Time interval between swings (haste-adjusted)
function SwingTimer:get_swing_interval()
    return self._weapon_speed / self._haste_modifier
end

---@return number seconds  Time until next auto-attack (clamped >= 0)
function SwingTimer:time_until_swing()
    local interval = self:get_swing_interval()
    local elapsed = self._time_fn() - self._last_swing
    local remaining = interval - elapsed
    return remaining > 0 and remaining or 0
end

---True when early in swing cycle (good time to apply SoC R1)
function SwingTimer:in_prep_window()
    local remaining = self:time_until_swing()
    return remaining > self._prep_threshold
end

---True when in last 0.4s before swing (twist to SoB)
function SwingTimer:in_twist_window()
    local remaining = self:time_until_swing()
    return remaining > 0 and remaining <= self._twist_threshold
end

return SwingTimer
