-- StateMachine.lua
-- Hierarchical State Machine (HSM) for SentinelNavClient navigation lifecycle.
-- 3 levels of state depth: state > substate > sub_substate
--
-- State hierarchy:
--   Idle
--   Navigating
--     AwaitingPath
--     FollowingPath
--     Recovering
--       Jumping
--       Probing
--       Strafing
--       Backtracking
--     Repathing
--     Deferred
--   Arrived
--   Failed (with fail_reason)

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local STATES = {
    IDLE       = "idle",
    NAVIGATING = "navigating",
    ARRIVED    = "arrived",
    FAILED     = "failed",
}

local NAV_SUBSTATES = {
    AWAITING_PATH  = "awaiting_path",
    FOLLOWING_PATH = "following_path",
    RECOVERING     = "recovering",
    REPATHING      = "repathing",
    DEFERRED       = "deferred",
}

local RECOVERY_SUBSTATES = {
    JUMPING      = "jumping",
    PROBING      = "probing",
    STRAFING     = "strafing",
    BACKTRACKING = "backtracking",
}

local FAIL_REASONS = {
    UNREACHABLE         = "unreachable",
    SERVER_TIMEOUT      = "server_timeout",
    MAX_STUCK_EXCEEDED  = "max_stuck_exceeded",
    MAX_REPATH_EXCEEDED = "max_repath_exceeded",
}

--------------------------------------------------------------------------------
-- Transition tables
--------------------------------------------------------------------------------

-- Valid top-level transitions: from_state -> { to_state, ... }
local VALID_TRANSITIONS = {
    [STATES.IDLE]       = { STATES.NAVIGATING },
    [STATES.NAVIGATING] = { STATES.ARRIVED, STATES.FAILED, STATES.IDLE },
    [STATES.ARRIVED]    = { STATES.IDLE, STATES.NAVIGATING },
    [STATES.FAILED]     = { STATES.IDLE, STATES.NAVIGATING },
}

-- Valid nav substate transitions: from_substate -> { to_substate, ... }
local VALID_SUBSTATE_TRANSITIONS = {
    [NAV_SUBSTATES.AWAITING_PATH]  = { NAV_SUBSTATES.FOLLOWING_PATH, NAV_SUBSTATES.DEFERRED },
    [NAV_SUBSTATES.FOLLOWING_PATH] = { NAV_SUBSTATES.RECOVERING, NAV_SUBSTATES.REPATHING, NAV_SUBSTATES.AWAITING_PATH },
    [NAV_SUBSTATES.RECOVERING]     = { NAV_SUBSTATES.FOLLOWING_PATH, NAV_SUBSTATES.REPATHING, NAV_SUBSTATES.AWAITING_PATH },
    [NAV_SUBSTATES.REPATHING]      = { NAV_SUBSTATES.FOLLOWING_PATH, NAV_SUBSTATES.AWAITING_PATH },
    [NAV_SUBSTATES.DEFERRED]       = { NAV_SUBSTATES.AWAITING_PATH },
}

-- Set of valid recovery substates for quick lookup
local VALID_RECOVERY = {}
for _, v in pairs(RECOVERY_SUBSTATES) do
    VALID_RECOVERY[v] = true
end

-- Set of valid nav substates for quick lookup
local VALID_NAV = {}
for _, v in pairs(NAV_SUBSTATES) do
    VALID_NAV[v] = true
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

---Check if a value exists in an array
---@param tbl table
---@param val any
---@return boolean
local function contains(tbl, val)
    for i = 1, #tbl do
        if tbl[i] == val then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Class
--------------------------------------------------------------------------------

---@class NavStateMachine
---@field private _state string
---@field private _substate string|nil
---@field private _sub_substate string|nil
---@field private _fail_reason string|nil
---@field private _event_bus table|nil
local StateMachine = {}
StateMachine.__index = StateMachine

-- Export constants
StateMachine.STATES             = STATES
StateMachine.NAV_SUBSTATES      = NAV_SUBSTATES
StateMachine.RECOVERY_SUBSTATES = RECOVERY_SUBSTATES
StateMachine.FAIL_REASONS       = FAIL_REASONS

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

---Create a new StateMachine instance.
---@param event_bus? table Optional event bus with :emit(event, data) method
---@return NavStateMachine
function StateMachine:new(event_bus)
    local o = setmetatable({}, StateMachine)
    o._state         = STATES.IDLE
    o._substate      = nil
    o._sub_substate  = nil
    o._fail_reason   = nil
    o._event_bus     = event_bus or nil
    return o
end

--------------------------------------------------------------------------------
-- State queries
--------------------------------------------------------------------------------

---Get the current top-level state.
---@return string "idle"|"navigating"|"arrived"|"failed"
function StateMachine:get_state()
    return self._state
end

---Get the current nav substate (only meaningful while navigating).
---@return string|nil
function StateMachine:get_substate()
    return self._substate
end

---Get the current recovery sub-substate (only meaningful while recovering).
---@return string|nil
function StateMachine:get_sub_substate()
    return self._sub_substate
end

---Get a dot-joined full state string.
---Examples: "idle", "navigating.following_path", "navigating.recovering.jumping"
---@return string
function StateMachine:get_full_state()
    local s = self._state
    if self._substate then
        s = s .. "." .. self._substate
        if self._sub_substate then
            s = s .. "." .. self._sub_substate
        end
    end
    return s
end

---Get the failure reason (only meaningful in failed state).
---@return string|nil
function StateMachine:get_failure_reason()
    return self._fail_reason
end

---Check if actively navigating.
---@return boolean
function StateMachine:is_moving()
    return self._state == STATES.NAVIGATING
end

---Check if idle.
---@return boolean
function StateMachine:is_idle()
    return self._state == STATES.IDLE
end

---Check if in a terminal state (arrived or failed).
---@return boolean
function StateMachine:is_terminal()
    return self._state == STATES.ARRIVED or self._state == STATES.FAILED
end

--------------------------------------------------------------------------------
-- Event firing
--------------------------------------------------------------------------------

---@private
---Fire an event on the event bus (if present).
---@param event string
---@param data table
function StateMachine:_fire(event, data)
    if not self._event_bus then return end
    local emit = self._event_bus.emit
    if type(emit) == "function" then
        emit(self._event_bus, event, data)
    end
end

--------------------------------------------------------------------------------
-- Transitions
--------------------------------------------------------------------------------

---Transition to a new top-level state.
---@param new_state string Target top-level state
---@param substate? string Initial nav substate (required when transitioning to navigating)
---@param opts? table { sub_substate?: string, fail_reason?: string, event_data?: table, destination?: table }
---@return boolean success
---@return string|nil error_msg
function StateMachine:transition(new_state, substate, opts)
    opts = opts or {}

    -- Validate top-level transition
    local valid = VALID_TRANSITIONS[self._state]
    if not valid or not contains(valid, new_state) then
        local msg = "Invalid transition: " .. self._state .. " -> " .. new_state
        return false, msg
    end

    -- Capture previous state info for events
    local prev_state        = self._state
    local prev_substate     = self._substate
    local prev_sub_substate = self._sub_substate

    -- Apply new state
    self._state        = new_state
    self._substate     = nil
    self._sub_substate = nil
    self._fail_reason  = nil

    -- State-specific setup
    if new_state == STATES.NAVIGATING then
        -- Default to awaiting_path if no substate provided
        local sub = substate or NAV_SUBSTATES.AWAITING_PATH
        if not VALID_NAV[sub] then
            -- Rollback
            self._state        = prev_state
            self._substate     = prev_substate
            self._sub_substate = prev_sub_substate
            return false, "Invalid nav substate: " .. tostring(sub)
        end
        self._substate = sub
        -- Only allow sub_substate when recovering
        if opts.sub_substate then
            if sub == NAV_SUBSTATES.RECOVERING and VALID_RECOVERY[opts.sub_substate] then
                self._sub_substate = opts.sub_substate
            end
        end
    elseif new_state == STATES.FAILED then
        self._fail_reason = opts.fail_reason or nil
    end

    -- Fire state_changed event
    self:_fire("nav.state_changed", {
        from             = prev_state,
        to               = new_state,
        substate_from    = prev_substate,
        substate_to      = self._substate,
        sub_substate     = self._sub_substate,
        fail_reason      = self._fail_reason,
    })

    -- Fire convenience events
    if new_state == STATES.ARRIVED then
        self:_fire("nav.arrived", opts.event_data or {})
    elseif new_state == STATES.FAILED then
        self:_fire("nav.failed", {
            reason      = self._fail_reason,
            destination = opts.destination,
        })
    end

    return true, nil
end

---Change the nav substate while navigating.
---@param new_substate string Target nav substate
---@param opts? table { sub_substate?: string }
---@return boolean success
---@return string|nil error_msg
function StateMachine:set_substate(new_substate, opts)
    opts = opts or {}

    -- Must be navigating
    if self._state ~= STATES.NAVIGATING then
        return false, "Cannot set substate: not navigating (state=" .. self._state .. ")"
    end

    -- Validate substate value
    if not VALID_NAV[new_substate] then
        return false, "Invalid nav substate: " .. tostring(new_substate)
    end

    -- Validate substate transition
    local current_sub = self._substate
    if current_sub then
        local valid = VALID_SUBSTATE_TRANSITIONS[current_sub]
        if not valid or not contains(valid, new_substate) then
            return false, "Invalid substate transition: " .. tostring(current_sub) .. " -> " .. new_substate
        end
    end

    -- Capture previous for events
    local prev_substate     = self._substate
    local prev_sub_substate = self._sub_substate

    -- Apply
    self._substate     = new_substate
    self._sub_substate = nil

    -- Handle sub_substate for recovering
    if opts.sub_substate then
        if new_substate == NAV_SUBSTATES.RECOVERING and VALID_RECOVERY[opts.sub_substate] then
            self._sub_substate = opts.sub_substate
        end
    end

    -- Fire event
    self:_fire("nav.state_changed", {
        from             = self._state,
        to               = self._state,
        substate_from    = prev_substate,
        substate_to      = self._substate,
        sub_substate     = self._sub_substate,
        fail_reason      = nil,
    })

    return true, nil
end

---Reset to idle, clearing all substates and failure reason.
function StateMachine:reset()
    local prev_state    = self._state
    local prev_substate = self._substate

    self._state         = STATES.IDLE
    self._substate      = nil
    self._sub_substate  = nil
    self._fail_reason   = nil

    if prev_state ~= STATES.IDLE then
        self:_fire("nav.state_changed", {
            from          = prev_state,
            to            = STATES.IDLE,
            substate_from = prev_substate,
            substate_to   = nil,
            sub_substate  = nil,
            fail_reason   = nil,
        })
    end
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

---Run unit tests for the StateMachine.
---@return table<string, boolean> results
function StateMachine:_test()
    local results = {}

    --------------------------------------------------------------------------
    -- Test 1: Initial state is idle
    --------------------------------------------------------------------------
    local sm = StateMachine:new()
    results["1_initial_state_idle"] = (sm:get_state() == "idle")

    --------------------------------------------------------------------------
    -- Test 2: Valid transition (idle -> navigating)
    --------------------------------------------------------------------------
    local ok, err = sm:transition("navigating")
    results["2_idle_to_navigating"] = (ok == true and err == nil)
    results["2_state_is_navigating"] = (sm:get_state() == "navigating")

    --------------------------------------------------------------------------
    -- Test 3: Full state string (navigating.awaiting_path)
    --------------------------------------------------------------------------
    results["3_full_state_string"] = (sm:get_full_state() == "navigating.awaiting_path")
    results["3_substate_awaiting"] = (sm:get_substate() == "awaiting_path")

    --------------------------------------------------------------------------
    -- Test 4: Invalid transition rejected (idle -> arrived)
    --------------------------------------------------------------------------
    local sm2 = StateMachine:new()
    local ok2, err2 = sm2:transition("arrived")
    results["4_invalid_rejected"] = (ok2 == false)
    results["4_error_msg_present"] = (type(err2) == "string" and #err2 > 0)
    results["4_state_unchanged"] = (sm2:get_state() == "idle")

    --------------------------------------------------------------------------
    -- Test 5: is_moving() when navigating
    --------------------------------------------------------------------------
    results["5_is_moving"] = (sm:is_moving() == true)
    results["5_not_idle"] = (sm:is_idle() == false)
    results["5_not_terminal"] = (sm:is_terminal() == false)

    --------------------------------------------------------------------------
    -- Test 6: Substate transition with sub_substate
    -- following_path -> recovering.jumping
    --------------------------------------------------------------------------
    local sm3 = StateMachine:new()
    sm3:transition("navigating", "awaiting_path")
    sm3:set_substate("following_path")
    local ok3, err3 = sm3:set_substate("recovering", { sub_substate = "jumping" })
    results["6_recovering_ok"] = (ok3 == true and err3 == nil)
    results["6_substate_recovering"] = (sm3:get_substate() == "recovering")
    results["6_sub_substate_jumping"] = (sm3:get_sub_substate() == "jumping")
    results["6_full_state_3_levels"] = (sm3:get_full_state() == "navigating.recovering.jumping")

    --------------------------------------------------------------------------
    -- Test 7: Failed with reason
    --------------------------------------------------------------------------
    local sm4 = StateMachine:new()
    sm4:transition("navigating")
    local ok4, _ = sm4:transition("failed", nil, { fail_reason = "unreachable" })
    results["7_failed_ok"] = (ok4 == true)
    results["7_state_failed"] = (sm4:get_state() == "failed")
    results["7_fail_reason"] = (sm4:get_failure_reason() == "unreachable")
    results["7_is_terminal"] = (sm4:is_terminal() == true)

    --------------------------------------------------------------------------
    -- Test 8: Event fired on transition
    --------------------------------------------------------------------------
    local captured_events = {}
    local mock_bus = {
        emit = function(self_bus, event, data)
            captured_events[#captured_events + 1] = { event = event, data = data }
        end,
    }
    local sm5 = StateMachine:new(mock_bus)
    sm5:transition("navigating")
    results["8_event_fired"] = (#captured_events > 0)
    results["8_event_name"] = (captured_events[1].event == "nav.state_changed")
    results["8_event_from"] = (captured_events[1].data.from == "idle")
    results["8_event_to"] = (captured_events[1].data.to == "navigating")
    results["8_event_substate_to"] = (captured_events[1].data.substate_to == "awaiting_path")

    --------------------------------------------------------------------------
    -- Test 9: Arrived convenience event
    --------------------------------------------------------------------------
    local arrived_events = {}
    local mock_bus2 = {
        emit = function(self_bus, event, data)
            arrived_events[#arrived_events + 1] = { event = event, data = data }
        end,
    }
    local sm6 = StateMachine:new(mock_bus2)
    sm6:transition("navigating")
    arrived_events = {} -- reset after navigating event
    sm6:transition("arrived", nil, { event_data = { distance = 42 } })
    local found_arrived = false
    for i = 1, #arrived_events do
        if arrived_events[i].event == "nav.arrived" then
            found_arrived = true
            results["9_arrived_data"] = (arrived_events[i].data.distance == 42)
        end
    end
    results["9_arrived_event"] = found_arrived

    --------------------------------------------------------------------------
    -- Test 10: Reset to idle
    --------------------------------------------------------------------------
    local sm7 = StateMachine:new()
    sm7:transition("navigating", "awaiting_path")
    sm7:set_substate("following_path")
    sm7:set_substate("recovering", { sub_substate = "probing" })
    sm7:reset()
    results["10_reset_state"] = (sm7:get_state() == "idle")
    results["10_reset_substate"] = (sm7:get_substate() == nil)
    results["10_reset_sub_substate"] = (sm7:get_sub_substate() == nil)
    results["10_reset_fail_reason"] = (sm7:get_failure_reason() == nil)
    results["10_full_state_idle"] = (sm7:get_full_state() == "idle")

    return results
end

return StateMachine
