local AutoAttackHelper = require("lib/AutoAttackHelper")

---@class SwingTimer
---@field private _last_swing_at number|nil
local SwingTimer = {}
SwingTimer.__index = SwingTimer

---@param time_fn fun(): number  Returns current time in seconds
function SwingTimer:new(time_fn)
    local o = setmetatable({}, SwingTimer)
    o._time_fn = time_fn or function() return core and core.time() or 0 end
    o._player = nil
    o._weapon_speed = 3.5
    o._haste_modifier = 1.0
    o._prep_threshold = 0.80   -- seconds remaining to start prep
    o._twist_threshold = 0.40  -- seconds remaining to start twist
    o._last_swing_at = nil     -- fallback: timestamp of last detected swing
    return o
end

--- Set the player object for auto_attack_helper queries.
---@param player game_object|nil
function SwingTimer:set_player(player)
    self._player = player
end

function SwingTimer:set_weapon_speed(speed)
    self._weapon_speed = speed
end

function SwingTimer:set_haste_modifier(mod)
    self._haste_modifier = (mod and mod > 0.01) and mod or 0.01
end

---@return number seconds  Time interval between swings (haste-adjusted)
function SwingTimer:get_swing_interval()
    return self._weapon_speed / self._haste_modifier
end

---Record that a melee swing just landed (for fallback timing).
function SwingTimer:record_swing()
    self._last_swing_at = self._time_fn()
end

---@return number seconds  Time until next auto-attack (clamped >= 0)
function SwingTimer:time_until_swing()
    -- Primary: SDK auto_attack_helper (real swing data from the engine)
    local aa = AutoAttackHelper.get()
    if aa and aa.get_next_attack_core_time and self._player then
        local ok, next_swing = pcall(function()
            return aa:get_next_attack_core_time(self._player)
        end)
        if ok and next_swing and next_swing > 0 then
            local now = self._time_fn()
            local remaining = next_swing - now
            if remaining > 0 then
                -- Keep _last_swing_at in sync so fallback transition is smooth
                local interval = self:get_swing_interval()
                self._last_swing_at = now - (interval - remaining)
                return remaining
            end
            -- Swing already landed or past due
            self._last_swing_at = next_swing
            return 0
        end
    end

    -- Fallback: use recorded swing timing (modular to handle missed swings)
    if self._last_swing_at then
        local now = self._time_fn()
        local interval = self:get_swing_interval()
        local elapsed = now - self._last_swing_at
        local remaining = interval - (elapsed % interval)
        return remaining > 0 and remaining or 0
    end

    -- Last resort: midpoint estimate (no swing data available yet)
    return self:get_swing_interval() * 0.5
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
