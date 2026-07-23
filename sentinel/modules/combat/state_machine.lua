local Events = require("modules/combat/events")

local CombatStateMachine = {}
CombatStateMachine.__index = CombatStateMachine

-- The only legal combat states. transition() previously accepted any string
-- with no legal-transition set (audit C7) — a typo silently created a valid
-- but unreachable state, and any guard comparing get_state() against one of
-- these five literals would then permanently fail without erroring.
local LEGAL_STATES = {
    IDLE = true,
    ENGAGING = true,
    WAITING_GCD = true,
    CASTING = true,
    COOLDOWN = true,
}

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
    if not LEGAL_STATES[next_state] then
        if core and type(core.log) == "function" then
            pcall(core.log, string.format(
                "[CombatStateMachine] rejected illegal transition to %s (reason=%s, staying %s)",
                tostring(next_state), tostring(reason), self._state))
        end
        return
    end
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
