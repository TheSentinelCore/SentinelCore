---
id: 4
title: "Logic: Fix statechart compound state to enter initial child"
state: open
labels: ["bug", "correctness", "ready-for-agent", "area:quest"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

In `_enterStateHierarchy`, when the executor drills down into a target state, if it encounters a compound state without history, it falls through to the else block and calls `_enterState(..., stateId, {})`. This marks the compound state itself as the active leaf state in `_activeStates`, completely failing to enter the compound state's initial child state.

## Code Context

File: `sentinel/modules/quest/statechart_executor.lua` lines 241-267

```lua
function StatechartExecutor:_enterStateHierarchy(targetStateId, lca)
    -- ... builds path ...
    
    for _, stateId in ipairs(path) do
        local state = self._compiled.states[stateId]
        if state then
            if state.type == "compound" and self._history[stateId] then
                -- History restore path
            elseif state.type == "parallel" then
                -- Parallel region handling (correct)
            else
                -- BUG: Treats compound states as atomic
                self:_enterState(state.region or self:_getRegionForState(stateId), stateId, {})
            end
        end
    end
end
```

## Impact

Transitions targeting compound states halt the state machine at the parent level. Transitions defined on child states will never evaluate. The profile cannot make progress through its designed state hierarchy.

## Acceptance Criteria

- [ ] `_enterStateHierarchy` recursively enters the initial child of compound states
- [ ] Unit tests verify compound state entry with and without history
- [ ] Profile statecharts can successfully transition through nested compound states

## References

- ADR-0004 - State hierarchy semantics (SCXML/Harel model)