-- sentinel/runtime/profile_state.lua
-- Profile and Operation state machine.
-- Profile states: idle → ready → executing → waiting → finished (back to idle)
-- Operation states: locked → ready → active → completed|failed|aborted|skipped

local ProfileState = {}
ProfileState.__index = ProfileState

-- Valid profile state transitions
local PROFILE_TRANSITIONS = {
    idle = { ready = true },
    ready = { executing = true },
    executing = { waiting = true, idle = true },
    waiting = { executing = true, idle = true },
    finished = { idle = true },
}

local PROFILE_STATES = {
    idle = true,
    ready = true,
    executing = true,
    waiting = true,
    finished = true,
}

-- Valid operation state transitions
local OP_TRANSITIONS = {
    locked = { ready = true },
    ready = { active = true },
    active = { completed = true, failed = true, aborted = true, skipped = true },
}

local OP_STATES = {
    locked = true,
    ready = true,
    active = true,
    completed = true,
    failed = true,
    aborted = true,
    skipped = true,
}

---Create a new ProfileState
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@return table ProfileState instance
function ProfileState:new(blackboard, event_bus)
    local o = setmetatable({}, ProfileState)
    o._blackboard = blackboard
    o._event_bus = event_bus
    return o
end

---Validate and set the profile state
---@param state string Target state
---@return boolean true if transition was valid and applied, false otherwise
function ProfileState:set_profile_state(state)
    if not PROFILE_STATES[state] then
        return false
    end

    local current = self:get_profile_state()
    if not current then
        -- No current state; set it directly
        self._blackboard:set("module.runtime.profile_state", state)
        if self._event_bus then
            self._event_bus:publish("profile_state_changed", {
                from = nil,
                to = state,
            })
        end
        return true
    end

    -- Allow re-setting to the same state
    if current == state then
        return true
    end

    -- Check if the transition is valid
    local allowed = PROFILE_TRANSITIONS[current]
    if not allowed or not allowed[state] then
        return false
    end

    -- Apply the transition
    self._blackboard:set("module.runtime.profile_state", state)
    if self._event_bus then
        self._event_bus:publish("profile_state_changed", {
            from = current,
            to = state,
        })
    end
    return true
end

---Get the current profile state
---@return string|nil
function ProfileState:get_profile_state()
    return self._blackboard:get("module.runtime.profile_state")
end

---Validate and set an operation's state
---@param op_id string Operation ID
---@param state string Target state
---@return boolean true if transition was valid and applied, false otherwise
function ProfileState:set_operation_state(op_id, state)
    if type(op_id) ~= "string" or op_id == "" then
        return false
    end
    if not OP_STATES[state] then
        return false
    end

    local current = self:get_operation_state(op_id)

    if not current then
        -- No current state; set it directly (must start as "locked")
        if state ~= "locked" then
            return false
        end
        self:_set_op_state_internal(op_id, state, nil)
        return true
    end

    -- Allow re-setting to the same state (idempotent)
    if current == state then
        return true
    end

    -- Check if the transition is valid
    local allowed = OP_TRANSITIONS[current]
    if not allowed or not allowed[state] then
        return false
    end

    self:_set_op_state_internal(op_id, state, current)
    return true
end

---Internal helper to set op state in blackboard and publish event
---@param op_id string
---@param state string
---@param previous string|nil
function ProfileState:_set_op_state_internal(op_id, state, previous)
    local key = "module.runtime.operations." .. tostring(op_id) .. ".state"
    self._blackboard:set(key, state)
    if self._event_bus then
        self._event_bus:publish("operation_state_changed", {
            operation_id = op_id,
            from = previous,
            to = state,
        })
    end
end

---Get the current state of an operation
---@param op_id string Operation ID
---@return string|nil
function ProfileState:get_operation_state(op_id)
    if type(op_id) ~= "string" or op_id == "" then
        return nil
    end
    local key = "module.runtime.operations." .. tostring(op_id) .. ".state"
    return self._blackboard:get(key)
end

---Set recovery action for an operation
---@param op_id string Operation ID
---@param action string "retry"|"skip"|"abort"
---@return boolean
function ProfileState:set_recovery(op_id, action)
    if type(op_id) ~= "string" or op_id == "" then
        return false
    end
    if action ~= "retry" and action ~= "skip" and action ~= "abort" then
        return false
    end
    local key = "module.runtime.operations." .. tostring(op_id) .. ".recovery"
    self._blackboard:set(key, action)
    return true
end

---Get recovery action for an operation
---@param op_id string Operation ID
---@return string|nil
function ProfileState:get_recovery(op_id)
    if type(op_id) ~= "string" or op_id == "" then
        return nil
    end
    local key = "module.runtime.operations." .. tostring(op_id) .. ".recovery"
    return self._blackboard:get(key)
end

---Reset all state: clear profile state and all operation states
function ProfileState:reset()
    -- Clear profile state
    self._blackboard:clear("module.runtime.profile_state")

    -- Clear all operation states
    local prefix = "module.runtime.operations."
    local snapshot = self._blackboard:snapshot(prefix)
    for key, _ in pairs(snapshot) do
        self._blackboard:clear(key)
    end

    if self._event_bus then
        self._event_bus:publish("profile_state_changed", {
            from = nil,
            to = nil,
        })
    end
end

return ProfileState
