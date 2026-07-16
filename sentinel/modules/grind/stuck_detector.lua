local StuckDetector = {}
StuckDetector.__index = StuckDetector

local SAMPLE_INTERVAL_MS = 2000
local MIN_MOVEMENT_YD = 1.0
local STUCK_SAMPLES = 3
local MAX_ATTEMPTS = 3

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Create a new StuckDetector instance.
---@return table detector
function StuckDetector:new()
    local o = {
        last_sample_time = nil,
        last_position = nil,
        low_movement_count = 0,
        attempt_count = 0,
        _last_phase = nil,
    }
    setmetatable(o, self)
    return o
end

---Record a position sample at the given timestamp.
---Ignores samples within SAMPLE_INTERVAL_MS of the last sample.
---When phase_tag is provided, auto-resets if the phase changed since last sample.
---@param now_ms number Current time in milliseconds
---@param position table { x, y, z }
---@param phase_tag string|nil Optional phase identifier for cross-phase reset
function StuckDetector:sample(now_ms, position, phase_tag)
    if phase_tag and phase_tag ~= self._last_phase then
        self:reset()
        self._last_phase = phase_tag
    end
    if self.last_sample_time and (now_ms - self.last_sample_time) < SAMPLE_INTERVAL_MS then
        return
    end

    if self.last_position then
        local dist = distance_3d(self.last_position, position)
        if dist < MIN_MOVEMENT_YD then
            self.low_movement_count = self.low_movement_count + 1
        else
            self.low_movement_count = 0
        end
    end

    self.last_sample_time = now_ms
    self.last_position = { x = position.x, y = position.y, z = position.z }
end

---Check if the detector considers the bot stuck.
---Returns true when 3+ consecutive low-movement samples have been recorded.
---@return boolean
function StuckDetector:is_stuck()
    return self.low_movement_count >= STUCK_SAMPLES
end

---Increment the unstuck attempt counter.
function StuckDetector:record_attempt()
    self.attempt_count = self.attempt_count + 1
end

---Get the current unstuck attempt count.
---@return number
function StuckDetector:get_attempt_count()
    return self.attempt_count
end

---Check if too many unstuck attempts have been made.
---Returns true when 3+ attempts have been recorded.
---@return boolean
function StuckDetector:should_give_up()
    return self.attempt_count >= MAX_ATTEMPTS
end

---Clear samples and low-movement counter.
---Does NOT reset the attempt counter.
function StuckDetector:reset()
    self.last_sample_time = nil
    self.last_position = nil
    self.low_movement_count = 0
end

return StuckDetector
