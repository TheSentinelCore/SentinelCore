---
id: 2
title: "StatechartExecutor — Hierarchical Event-Driven State Machine Runtime"
state: done
labels: ["enhancement", "ready-for-agent", "area:quest", "priority:high", "size:large"]
created: "2026-07-16T00:00:00Z"
updated: "2026-07-16T00:00:00Z"
---

## What to build

A Lua module `StatechartExecutor` that loads a `CompiledProfile` and runs the event-driven hierarchical statechart. This is the core runtime replacing `QuestPlanner` + `ObjectivePlanner`.

## Requirements

### Core Loop
- Maintain active state stack (one leaf per parallel region)
- On event: evaluate enabled transitions from innermost active leaf states (depth-first)
- Guard evaluation: compile guard expression → Lua function → call with `(event, bb, profile, state)`
- Transition execution: exit source (run exit actions) → run transition actions → enter target (run entry actions)
- History states: on re-entry to compound state with history, resume last active leaf
- Final state: when `Questing` region reaches `Finished`, publish `ProfileComplete`

### Concurrency
- Parallel regions: all regions active simultaneously, each with own active leaf
- Exclusive states: only one child active
- Transitions can cross regions (source in one region, target in another)

### Action Scheduling
- Actions are async Lua coroutines (from compiled bytecode)
- Executor `await`s actions sequentially per transition
- On state exit: cancel any running actions from that state (timeout guard)

### API
```lua
local executor = StatechartExecutor.new(compiledProfile, context)
executor:start()  -- enters initial states
executor:handleEvent(eventName, payload)  -- processes event
executor:stop()  -- cleanup
executor:getActiveStates()  -- for debugging: {Questing="KillKobolds", Survival.HealthManagement="Healthy", ...}
```

### Context
Passed to guards/actions: `engine`, `nav`, `combat`, `consume`, `vendor`, `loot`, `profile` (variable store), `bb` (blackboard proxy), `state` (current state context), `ctx:awaitEvent(name, filter, timeoutMs)`, `ctx:callAction(name, args)`

## Acceptance Criteria

- [x] Loads compiled profile, enters initial states of all parallel regions
- [x] `QuestAccepted` event with matching guard transitions `AcceptQuests` → `TravelToObjective`
- [x] Parallel regions work: `Survival.HealthManagement` and `Logistics.Inventory` update independently
- [x] History state: exit `KillKobolds` → enter `TurnIn` → re-enter `CompleteObjectives` (history) → resumes `KillKobolds` sub-state
- [x] Guard expressions evaluate with access to `event`, `bb`, `profile`, `state`
- [x] Actions run as coroutines, `awaitEvent` blocks until matching event or timeout
- [x] State exit cancels running actions (no leaks)
- [x] `ProfileComplete` published when `Questing` region reaches `Finished`
- [x] Performance: <1ms per event handling for 500-state profile

## Blocked by

- **01-profile-compiler** — needs `CompiledProfile` format
- **03-engine-event-system** — needs event publishing from engine

## Files to Create

- `sentinel/modules/quest/statechart_executor.lua`
- `sentinel/modules/quest/profile_context.lua` (Context API for guards/actions)