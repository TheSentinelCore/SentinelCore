---
id: 3
title: "Leak: Implement cancellation for event subscriptions in statechart executor"
state: open
labels: ["bug", "performance", "ready-for-agent", "area:quest"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

When a state is exited (e.g., via a transition on a parallel region), `_cancelStateActions` is called to stop running inline action coroutines. While it abandons the Lua coroutine, it does NOT unsubscribe the `awaitEvent` listener from the eventBus.

## Code Context

File: `sentinel/modules/quest/statechart_executor.lua`

Lines 393-403:
```lua
function StatechartExecutor:_cancelStateActions(stateId)
    local actions = self._runningActions[stateId]
    if actions then
        for _, co in ipairs(actions) do
            if coroutine.status(co) ~= "dead" then
                -- Can't actually cancel Lua coroutine, but we can mark it
            end
        end
        self._runningActions[stateId] = nil
    end
end
```

Lines 324-341 (where subscriptions are created):
```lua
subscriptionId = self._context.eventBus:subscribe(eventName, function(payload)
    if not filter or self:_matchFilter(payload, filter) then
        if self._context.getTime and self._context.getTime() > deadline then
            self._context.eventBus:unsubscribe(subscriptionId)
            coroutine.resume(co, false, "timeout")
        else
            self._context.eventBus:unsubscribe(subscriptionId)
            coroutine.resume(co, true, payload)
        end
    end
end)
```

## Impact

- Memory leak (unbounded growth of event bus subscriptions)
- If the event fires later, it will attempt to resume a discarded coroutine
- Potential state corruption if dead coroutines are resumed with stale payloads

## Acceptance Criteria

- [ ] `_runningActions` entries track subscription IDs alongside coroutines
- [ ] `_cancelStateActions` unsubscribes all tracked subscriptions for the state
- [ ] Tests verify subscriptions are cleaned up on state exit
- [ ] Memory profiling shows stable subscription count over time

## References

- ADR-0004 - "Lua coroutine management for async actions must be robust (timeouts, cancellation on state exit)"