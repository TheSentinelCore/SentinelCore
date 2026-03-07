local Events = require("modules/combat/events")

local CombatStateMachine = {}
CombatStateMachine.__index = CombatStateMachine

function CombatStateMachine:new(event_bus, blackboard)
    local o = setmetatable({}, CombatStateMachine)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._state = "IDLE"
    o._blackboard:set("combat.state", o._state)
    return o
end

function CombatStateMachine:get_state()
    return self._state
end

function CombatStateMachine:transition(next_state, reason)
    next_state = tostring(next_state or self._state)
    if self._state == next_state then
        self._blackboard:set("combat.state", next_state)
        return
    end
    local previous = self._state
    self._state = next_state
    self._blackboard:set("combat.state", next_state)
    self._event_bus:publish(Events.STATE_CHANGED, {
        from = previous,
        to = next_state,
        reason = reason or "transition",
    })
end

return CombatStateMachine
