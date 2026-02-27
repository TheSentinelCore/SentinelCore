local StateMachine = {}
StateMachine.__index = StateMachine

---@return StateMachine
function StateMachine:new()
    return setmetatable({
        _state = "idle",
        _last_error = nil,
    }, StateMachine)
end

---@return string
function StateMachine:get_state()
    return self._state
end

---@return string|nil
function StateMachine:get_last_error()
    return self._last_error
end

---@param error_code? string
function StateMachine:fail(error_code)
    self._state = "failed"
    self._last_error = error_code or "unknown"
end

function StateMachine:start()
    self._state = "running"
    self._last_error = nil
end

function StateMachine:pause()
    if self._state == "running" then
        self._state = "paused"
    end
end

function StateMachine:resume()
    if self._state == "paused" then
        self._state = "running"
    end
end

function StateMachine:stop()
    self._state = "idle"
    self._last_error = nil
end

---@return boolean
function StateMachine:is_running()
    return self._state == "running"
end

return StateMachine
