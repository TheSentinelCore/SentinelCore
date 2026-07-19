---
id: 6
title: "Performance: Stuck event storm due to missing timer reset"
state: open
labels: ["bug", "performance", "ready-for-agent", "area:quest"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

In `_detectStuck`, once a player has been stuck for 30 seconds (`now - prevTime > 30000`), the Stuck event is published. However, `prevTime` is only updated when NOT stuck (in the `else` branch). Once the condition becomes true, it remains true on every subsequent frame/tick, spamming the eventBus.

## Code Context

File: `sentinel/modules/quest/events.lua` lines 379-405

```lua
function Events.Detector:_detectStuck()
    local pos = self._blackboard:get("player.position")
    if pos then
        local prevPos = self._prevState.position
        local prevTime = self._prevState.positionTime or 0
        local now = self._blackboard:get("system.now_ms", 0)

        if prevPos then
            local dist = ...
            if dist < 0.5 then
                if now - prevTime > 30000 then -- 30 seconds
                    self:_publish(Events.Names.Stuck, {...})
                    -- BUG: Missing self._prevState.positionTime = now
                end
            else
                self._prevState.positionTime = now  -- Only updated when NOT stuck!
            end
        end
        self._prevState.position = {x = pos.x, y = pos.y, z = pos.z}
    end
end
```

## Impact

- Event bus saturation with Stuck events
- Frame rate degradation if listeners perform heavy operations
- Log spam obscuring real stuck events

## Acceptance Criteria

- [ ] Reset `positionTime` immediately after publishing Stuck event
- [ ] Add cooldown to prevent rapid re-notification (e.g., 30s after event fired)
- [ ] Manual stuck detection test confirms single event per stuck incident

## References

- ADR-0004 - Event catalog includes Stuck event