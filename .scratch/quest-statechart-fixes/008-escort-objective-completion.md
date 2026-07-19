---
id: 8
title: "Logic: Fix escort objective premature completion"
state: open
labels: ["bug", "correctness", "ready-for-agent", "area:quest"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

In the escort objective phase, when waypoints are provided and navigation starts, the phase immediately marks `phase_done = true` and returns SUCCESS before the player has traversed the path or finished the escort.

## Code Context

File: `sentinel/modules/quest/quest_phases.lua` lines 221-228

```lua
if waypoints and #waypoints > 0 then
    local nav = bb:get("module.quest.nav_adapter")
    if nav then
        nav:follow_path(waypoints)
    end
    bb:set("module.quest.phase_done", true)  -- Wrong: immediately marks done
    return Status.SUCCESS
end
```

## Comparison: Correct Pattern from Travel Phase

Lines 24-35 show the correct pattern:
```lua
local state = nav:get_state()
local progress = nav:get_progress()

if state == "arrived" then
    bb:set("module.quest.phase_done", true)
    return Status.SUCCESS
elseif state == "failed" then
    return Status.FAILURE
elseif state == "moving" or state == "requesting_path" then
    return Status.RUNNING
end
```

## Impact

Escort quests are abandoned immediately after path is requested. The NPC is left behind, objectives never completed, and the profile cannot progress.

## Acceptance Criteria

- [ ] Escort phase checks navigation state on each tick
- [ ] Returns RUNNING while `state == "moving" or state == "requesting_path"`
- [ ] Only marks phase_done when waypoints are fully traversed or NPC not found
- [ ] Integration test with mock NPC shows correct phase completion behavior

## References

- ADR-0004 - EscortExecutor was intended to handle this pattern