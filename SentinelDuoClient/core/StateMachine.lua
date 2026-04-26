-- StateMachine.lua — Generic table-driven FSM.
-- State handlers: { enter=fn, update=fn, exit=fn }
-- update() returns next_state_name string or nil (nil = stay in current state).

local helpers = require("lib/helpers")

---@class StateMachine
---@field _name string
---@field _states table<string, table>
---@field _current string
---@field _initialized boolean
---@field _trace table[]  -- circular buffer of last 100 transitions
local StateMachine = {}
StateMachine.__index = StateMachine

---@param name string
---@param states_table table<string, table>
---@param initial_state string
---@return StateMachine
function StateMachine:new(name, states_table, initial_state)
    local self = setmetatable({
        _name        = name,
        _states      = states_table,
        _current     = initial_state,
        _initialized = false,
        _trace       = {},
    }, StateMachine)
    return self
end

--- Get the current state name.
---@return string
function StateMachine:get_current_state()
    return self._current
end

--- Force a transition to a named state.
---@param state_name string
---@param blackboard Blackboard
function StateMachine:transition_to(state_name, blackboard)
    if not self._states[state_name] then
        helpers.log_err("StateMachine '" .. self._name .. "': unknown state '" .. tostring(state_name) .. "'")
        return
    end

    local old_state = self._current

    -- Exit old state
    local old_def = self._states[old_state]
    if old_def and old_def.exit then
        local ok, err = pcall(old_def.exit, blackboard)
        if not ok then
            helpers.log_err("StateMachine exit error [" .. old_state .. "]: " .. tostring(err))
        end
    end

    self._current = state_name
    self._initialized = false

    -- Log the transition
    local hp  = blackboard and math.floor((blackboard:get("player.hp_pct", 0)) * 100) or 0
    local mp  = blackboard and math.floor((blackboard:get("player.mp_pct", 0)) * 100) or 0
    local pull = blackboard and (blackboard:get("duo.pull_index", 0)) or 0
    local role = blackboard and (blackboard:get("duo.my_client_id", "?")) or "?"

    helpers.log(string.format("STATE: %s → %s  [pull=%d, role=%s, hp=%d%%, mp=%d%%]",
        old_state, state_name, pull, role, hp, mp))

    -- Store in circular trace buffer
    local ok_t, t = pcall(core.time)
    local entry = {
        from  = old_state,
        to    = state_name,
        time  = (ok_t and t) or 0,
        pull  = pull,
        role  = role,
    }
    table.insert(self._trace, entry)
    if #self._trace > 100 then
        table.remove(self._trace, 1)
    end

    if blackboard then
        blackboard:set("duo._state_trace", self._trace)
    end
end

--- Tick the state machine: call enter on first tick, then update each tick.
--- Transitions if update() returns a non-nil state name.
---@param blackboard Blackboard
function StateMachine:tick(blackboard)
    local state_def = self._states[self._current]
    if not state_def then
        helpers.log_err("StateMachine '" .. self._name .. "': no definition for state '" .. tostring(self._current) .. "'")
        return
    end

    -- Call enter on first tick in this state
    if not self._initialized then
        self._initialized = true
        if state_def.enter then
            local ok, err = pcall(state_def.enter, blackboard)
            if not ok then
                helpers.log_err("StateMachine enter error [" .. self._current .. "]: " .. tostring(err))
            end
        end
    end

    -- Call update
    if state_def.update then
        local ok, result = pcall(state_def.update, blackboard)
        if not ok then
            helpers.log_err("StateMachine update error [" .. self._current .. "]: " .. tostring(result))
            return
        end

        -- Transition if a new state was returned
        if type(result) == "string" and result ~= self._current then
            self:transition_to(result, blackboard)
        end
    end
end

return StateMachine
