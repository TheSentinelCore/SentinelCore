local Events = require("events/Events")

local STATES = {
    IDLE = "idle",
    RUNNING = "running",
    PAUSED = "paused",
    FAILED = "failed",
}

local RUNNING_SUBSTATES = {
    SCOUT = "running.grind.scout",
    ACQUIRE = "running.grind.acquire",
    PULL = "running.grind.pull",
    COMBAT = "running.grind.combat",
    LOOT = "running.grind.loot",
    VENDOR = "running.grind.vendor",
    RECOVER = "running.grind.recover",
}

local VALID_TOP_TRANSITIONS = {
    [STATES.IDLE] = { STATES.RUNNING },
    [STATES.RUNNING] = { STATES.PAUSED, STATES.FAILED, STATES.IDLE },
    [STATES.PAUSED] = { STATES.RUNNING, STATES.FAILED, STATES.IDLE },
    [STATES.FAILED] = { STATES.IDLE },
}

local VALID_RUNNING_SUBSTATE = {}
for _, value in pairs(RUNNING_SUBSTATES) do
    VALID_RUNNING_SUBSTATE[value] = true
end

local function contains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end
    return false
end

---@class SentinelStateMachine
---@field private _state string
---@field private _substate string|nil
---@field private _failure_code string|nil
---@field private _event_bus EventBus|nil
local StateMachine = {}
StateMachine.__index = StateMachine
StateMachine.STATES = STATES
StateMachine.RUNNING_SUBSTATES = RUNNING_SUBSTATES

---@param event_bus? EventBus
---@return SentinelStateMachine
function StateMachine:new(event_bus)
    local o = setmetatable({}, StateMachine)
    o._state = STATES.IDLE
    o._substate = nil
    o._failure_code = nil
    o._event_bus = event_bus
    return o
end

---@return string
function StateMachine:get_state()
    return self._state
end

---@return string|nil
function StateMachine:get_substate()
    return self._substate
end

---@return string|nil
function StateMachine:get_failure_code()
    return self._failure_code
end

---@return string
function StateMachine:get_full_state()
    return self._substate or self._state
end

---@private
---@param data table
function StateMachine:_emit_change(data)
    if self._event_bus then
        self._event_bus:emit(Events.STATE_CHANGED, data)
    end
end

---@private
---@param failure_code string|nil
---@param detail table|nil
function StateMachine:_emit_failed(failure_code, detail)
    if self._event_bus then
        self._event_bus:emit(Events.FAILED, {
            error_code = failure_code,
            detail = detail,
        })
    end
end

---@param new_state string
---@param opts? table
---@return boolean success
---@return string|nil error_msg
function StateMachine:transition(new_state, opts)
    opts = opts or {}
    local valid = VALID_TOP_TRANSITIONS[self._state]
    if not valid or not contains(valid, new_state) then
        return false, "invalid transition " .. tostring(self._state) .. " -> " .. tostring(new_state)
    end

    local old_state = self._state
    local old_substate = self._substate

    self._state = new_state
    self._substate = nil

    if new_state == STATES.RUNNING then
        local desired_substate = opts.substate or RUNNING_SUBSTATES.SCOUT
        if not VALID_RUNNING_SUBSTATE[desired_substate] then
            self._state = old_state
            self._substate = old_substate
            return false, "invalid running substate " .. tostring(desired_substate)
        end
        self._substate = desired_substate
        self._failure_code = nil
    elseif new_state == STATES.FAILED then
        self._failure_code = opts.failure_code
    else
        self._failure_code = nil
    end

    self:_emit_change({
        from = old_state,
        to = self._state,
        substate_from = old_substate,
        substate_to = self._substate,
        failure_code = self._failure_code,
    })

    if new_state == STATES.FAILED then
        self:_emit_failed(self._failure_code, opts.failure_detail)
    end

    return true, nil
end

---@param substate string
---@return boolean success
---@return string|nil error_msg
function StateMachine:set_substate(substate)
    if self._state ~= STATES.RUNNING then
        return false, "cannot set substate while state=" .. tostring(self._state)
    end
    if not VALID_RUNNING_SUBSTATE[substate] then
        return false, "invalid running substate " .. tostring(substate)
    end

    local old_substate = self._substate
    if old_substate == substate then
        return true, nil
    end

    self._substate = substate
    self:_emit_change({
        from = self._state,
        to = self._state,
        substate_from = old_substate,
        substate_to = substate,
        failure_code = nil,
    })
    return true, nil
end

function StateMachine:reset()
    local old_state = self._state
    local old_substate = self._substate

    self._state = STATES.IDLE
    self._substate = nil
    self._failure_code = nil

    if old_state ~= STATES.IDLE or old_substate ~= nil then
        self:_emit_change({
            from = old_state,
            to = STATES.IDLE,
            substate_from = old_substate,
            substate_to = nil,
            failure_code = nil,
        })
    end
end

return StateMachine
