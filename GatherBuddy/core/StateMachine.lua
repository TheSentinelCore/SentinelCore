---@class StateContext
---@field entered_at number Timestamp when state was entered
---@field data table State-specific data
---@field previous_state string|nil Previous state name

---@class StateMachine
---@field private _current_state string
---@field private _context StateContext
---@field private _event_bus EventBus
---@field private _transitions table<string, string[]>
---@field private _log Logger|nil
local StateMachine = {}
StateMachine.__index = StateMachine

-- Import dependencies (relative paths since we're in GatherBuddy folder)
local Constants = require("core/Constants")
local STATES = Constants.STATES
local EVENTS = Constants.EVENTS
local VALID_TRANSITIONS = Constants.VALID_TRANSITIONS

-- Import logger if available
local Logger
local function get_logger()
    if not Logger then
        local success, result = pcall(require, "lib/Logger")
        if success then
            Logger = result
        end
    end
    if Logger then
        return Logger:new("StateMachine")
    end
    return nil
end

---Create a new StateMachine instance
---@param event_bus EventBus The event bus for publishing state changes
---@param initial_state? string Initial state (default IDLE)
---@return StateMachine
function StateMachine:new(event_bus, initial_state)
    local instance = setmetatable({}, StateMachine)

    instance._event_bus = event_bus
    instance._current_state = initial_state or STATES.IDLE
    instance._log = get_logger()

    instance._context = {
        entered_at = core.time(),
        data = {},
        previous_state = nil
    }

    if instance._log then
        instance._log:info("Initialized in state: %s", instance._current_state)
    end

    return instance
end

---Check if a transition from current state to new state is valid
---@param new_state string The target state
---@return boolean valid True if transition is allowed
function StateMachine:can_transition(new_state)
    if not new_state then
        return false
    end

    local valid_targets = VALID_TRANSITIONS[self._current_state]
    if not valid_targets then
        return false
    end

    for _, state in ipairs(valid_targets) do
        if state == new_state then
            return true
        end
    end

    return false
end

---Transition to a new state
---@param new_state string The target state
---@param data? table State-specific data
---@return boolean success True if transition was successful
function StateMachine:transition(new_state, data)
    if not new_state then
        if self._log then
            self._log:warn("Transition failed: new_state is nil")
        end
        return false
    end

    -- Same state transition (allowed for refreshing state data)
    if new_state == self._current_state then
        -- Update context data without changing state
        if data then
            for k, v in pairs(data) do
                self._context.data[k] = v
            end
        end
        return true
    end

    -- Validate transition
    if not self:can_transition(new_state) then
        if self._log then
            self._log:warn("Invalid transition: %s -> %s", self._current_state, new_state)
        else
            core.log_warning("[StateMachine] Invalid transition: " ..
                self._current_state .. " -> " .. new_state)
        end
        return false
    end

    local previous = self._current_state
    local now = core.time()

    -- Store previous context for reference
    local previous_context = self._context

    -- Update state
    self._current_state = new_state

    -- Create new context
    self._context = {
        entered_at = now,
        data = data or {},
        previous_state = previous
    }

    if self._log then
        self._log:info("%s -> %s", previous, new_state)
    else
        core.log("[StateMachine] " .. previous .. " -> " .. new_state)
    end

    -- Publish state change event
    if self._event_bus then
        self._event_bus:publish(EVENTS.STATE_CHANGED, {
            from = previous,
            to = new_state,
            context = self._context,
            previous_context = previous_context,
            timestamp = now
        })
    end

    return true
end

---Force a state change without validation (use sparingly)
---@param new_state string The target state
---@param data? table State-specific data
---@return boolean success
function StateMachine:force_transition(new_state, data)
    if not new_state then
        return false
    end

    local previous = self._current_state
    local now = core.time()

    self._current_state = new_state
    self._context = {
        entered_at = now,
        data = data or {},
        previous_state = previous
    }

    if self._log then
        self._log:warn("Forced transition: %s -> %s", previous, new_state)
    end

    if self._event_bus then
        self._event_bus:publish(EVENTS.STATE_CHANGED, {
            from = previous,
            to = new_state,
            context = self._context,
            forced = true,
            timestamp = now
        })
    end

    return true
end

---Get the current state
---@return string current_state
function StateMachine:get_state()
    return self._current_state
end

---Get the current state context
---@return StateContext
function StateMachine:get_context()
    return self._context
end

---Get time spent in current state
---@return number seconds Time in seconds
function StateMachine:get_time_in_state()
    return core.time() - self._context.entered_at
end

---Get the previous state (before the current one)
---@return string|nil previous_state
function StateMachine:get_previous_state()
    return self._context.previous_state
end

---Check if currently in a specific state
---@param state string The state to check
---@return boolean
function StateMachine:is_state(state)
    return self._current_state == state
end

---Check if in any of the given states
---@param states string[] Array of states to check
---@return boolean
function StateMachine:is_any_state(states)
    for _, state in ipairs(states) do
        if self._current_state == state then
            return true
        end
    end
    return false
end

---Get context data value
---@param key string The key to get
---@param default? any Default value if not found
---@return any
function StateMachine:get_data(key, default)
    local value = self._context.data[key]
    if value == nil then
        return default
    end
    return value
end

---Set context data value
---@param key string The key to set
---@param value any The value to set
function StateMachine:set_data(key, value)
    self._context.data[key] = value
end

---Get all valid transitions from current state
---@return string[] valid_states
function StateMachine:get_valid_transitions()
    local valid = VALID_TRANSITIONS[self._current_state]
    return valid or {}
end

---Check if in an active (non-idle/paused) state
---@return boolean
function StateMachine:is_active()
    return self._current_state ~= STATES.IDLE and
           self._current_state ~= STATES.PAUSED
end

---Check if in a movement-related state
---@return boolean
function StateMachine:is_moving()
    return self._current_state == STATES.TRAVELING or
           self._current_state == STATES.APPROACHING or
           self._current_state == STATES.CORPSE_RUN or
           self._current_state == STATES.FLEEING
end

---Check if in a gathering-related state
---@return boolean
function StateMachine:is_gathering()
    return self._current_state == STATES.GATHERING or
           self._current_state == STATES.LOOTING or
           self._current_state == STATES.APPROACHING or
           self._current_state == STATES.DISMOUNTING
end

---Check if in a danger state
---@return boolean
function StateMachine:is_in_danger()
    return self._current_state == STATES.COMBAT or
           self._current_state == STATES.FLEEING or
           self._current_state == STATES.DEAD or
           self._current_state == STATES.CORPSE_RUN
end

---Return to previous state (if valid)
---@param data? table Optional new context data
---@return boolean success
function StateMachine:return_to_previous(data)
    local previous = self._context.previous_state
    if not previous then
        if self._log then
            self._log:warn("No previous state to return to")
        end
        return false
    end

    return self:transition(previous, data)
end

---Reset to idle state
---@param data? table Optional context data
---@return boolean success
function StateMachine:reset(data)
    return self:force_transition(STATES.IDLE, data)
end

---Run unit tests
---@return table<string, boolean> Test results
function StateMachine:_test()
    local results = {}

    -- Create mock event bus
    local mock_bus = {
        events = {},
        publish = function(self, event, data)
            table.insert(self.events, { event = event, data = data })
        end
    }

    -- Test 1: Initial state
    local sm = StateMachine:new(mock_bus, STATES.IDLE)
    results.initial = (sm:get_state() == STATES.IDLE)

    -- Test 2: Valid transition
    results.valid_transition = sm:transition(STATES.LOADING)
    results.after_transition = (sm:get_state() == STATES.LOADING)

    -- Test 3: Invalid transition
    results.invalid_transition = not sm:transition(STATES.GATHERING)
    results.state_unchanged = (sm:get_state() == STATES.LOADING)

    -- Test 4: Can transition check
    results.can_transition_valid = sm:can_transition(STATES.TRAVELING)
    results.can_transition_invalid = not sm:can_transition(STATES.CORPSE_RUN)

    -- Test 5: Context and data
    sm:transition(STATES.TRAVELING, { waypoint = 1 })
    local ctx = sm:get_context()
    results.context_data = (ctx.data.waypoint == 1)
    results.context_previous = (ctx.previous_state == STATES.LOADING)

    -- Test 6: Time in state
    results.time_in_state = (sm:get_time_in_state() >= 0)

    -- Test 7: Previous state
    results.previous_state = (sm:get_previous_state() == STATES.LOADING)

    -- Test 8: Is state checks
    results.is_state = sm:is_state(STATES.TRAVELING)
    results.is_any_state = sm:is_any_state({STATES.IDLE, STATES.TRAVELING})
    results.is_any_state_false = not sm:is_any_state({STATES.DEAD, STATES.COMBAT})

    -- Test 9: Get/Set data
    sm:set_data("test_key", "test_value")
    results.get_set_data = (sm:get_data("test_key") == "test_value")
    results.get_data_default = (sm:get_data("nonexistent", 123) == 123)

    -- Test 10: Event published
    results.event_published = (#mock_bus.events > 0)

    -- Test 11: Force transition
    results.force_transition = sm:force_transition(STATES.COMBAT)
    results.force_state = (sm:get_state() == STATES.COMBAT)

    -- Test 12: Helper methods
    sm:force_transition(STATES.GATHERING)
    results.is_gathering = sm:is_gathering()
    sm:force_transition(STATES.TRAVELING)
    results.is_moving = sm:is_moving()
    sm:force_transition(STATES.COMBAT)
    results.is_in_danger = sm:is_in_danger()

    -- Test 13: Reset
    sm:reset()
    results.reset = (sm:get_state() == STATES.IDLE)

    return results
end

return StateMachine
