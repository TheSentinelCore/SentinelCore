---
id: 2
title: "Crash: Pass eventBus to ProfileExecutor and fix shadowed loadProfile method"
state: open
labels: ["bug", "correctness", "ready-for-agent", "area:quest"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

Two related bugs prevent ProfileExecutor from functioning:

1. `ProfileExecutor.new` accepts `blackboard, engine, nav_adapter` but NOT `eventBus`. The `awaitEvent` helper at line 55 calls `self._eventBus:subscribe()` which will always be `nil`.

2. `loadProfile` is declared at line 21 with full context-building logic, then completely overwritten at line 127 with a stub that only sets `_compiled`, destroying all context.

## Code Context

File: `sentinel/modules/quest/profile_executor.lua`

Lines 7-18 (constructor missing eventBus):
```lua
function ProfileExecutor.new(blackboard, engine, nav_adapter)
    local self = setmetatable({
        _blackboard = blackboard,
        _engine = engine,
        _nav_adapter = nav_adapter,
        -- Missing: _eventBus = eventBus
```

Lines 21-79 (full loadProfile) vs Lines 127-131 (stub):
```lua
function ProfileExecutor:loadProfile(compiledProfile)
    -- Lines 21-79: Full context building logic
    self._context = { engine = ..., nav = ..., awaitEvent = function(...) ... end }
    return self
end

function ProfileExecutor:loadProfile(compiledProfile)  -- Overwrites above!
    self:stop()
    self._compiled = compiledProfile
    return true  -- No context building!
end
```

File: `sentinel/modules/quest/module.lua` line 19 (caller):
```lua
local profileExecutor = ProfileExecutor.new(blackboard, phaseRunner, nav_adapter)
-- event_bus is available but not passed
```

## Impact

Any profile action that uses `awaitEvent` (the primary async mechanism) crashes the bot entirely with "attempt to index nil value" error.

## Acceptance Criteria

- [ ] ProfileExecutor.new accepts eventBus parameter
- [ ] _eventBus is stored in the instance
- [ ] module.lua passes eventBus when creating ProfileExecutor
- [ ] Duplicate loadProfile method is removed (keep the full context-building version)
- [ ] setProfile method is added (module.lua line 112 calls setProfile which doesn't exist)

## References

- ADR-0004 - Action registry design
- statechart_executor.lua lines 324-348 - awaitEvent implementation expecting eventBus