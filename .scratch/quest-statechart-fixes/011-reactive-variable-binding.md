---
id: 11
title: "Architecture: Reactive Variable Binding System"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "architecture"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

Replace pull-based variable binding updates with push-based event subscriptions. Currently `_updateBoundVariables()` polls blackboard every tick, contradicting ADR-0004's event-driven design.

## Background

Per ADR-0004: "Event Driven / Data Driven architecture, all polling/tick based design should be switched to event / data driven when found."

Current implementation (statechart_executor.lua:463-474) calls `bb:get()` for every bound variable on every event tick.

## Acceptance Criteria

- [ ] `_updateBoundVariables` is removed or converted to subscription model
- [ ] Variables with `bind` expressions subscribe to relevant events
- [ ] Path-to-event mapping implemented (player.level -> LevelUp, etc.)
- [ ] Subscriptions cleaned up on executor stop
- [ ] Performance test shows reduced CPU during idle ticks

## References

- ADR-0004 - "bind expressions are evaluated on each event tick (reactive) -> should be push-based"