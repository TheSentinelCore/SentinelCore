---
id: 13
title: "Variable Store + Event Dispatcher + State Machine (Lua)"
state: open
labels: ["enhancement", "ready-for-agent", "size:medium"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 13 — Variable Store + Event Dispatcher + State Machine (Lua)

**What to build:** Three supporting subsystems for the runtime engine: a typed variable store for profile state, an event dispatcher that maps Sylvannas game events to runtime events, and the top-level profile state machine.

**Blocked by:** #12 (Operation Scheduler + Action Executor — needs the core execution loop to exist)

**Acceptance criteria:**

**Variable Store:**
- [ ] New module at `sentinel/runtime/variable_store.lua`
- [ ] Typed key-value store supporting: Bool, Integer, Float, String, Position (x,y,zone)
- [ ] Two scopes: global (profile-level) and operation-level (cleared when Operation completes)
- [ ] `set(scope, key, value)` — write with type checking
- [ ] `get(scope, key)` — read, returns nil if not set
- [ ] `has(scope, key)` — check existence
- [ ] `delete(scope, key)` — remove
- [ ] `list(scope)` — return all keys in scope
- [ ] Operation-level variables inherit global scope (read-through)
- [ ] Stored in blackboard at `module.runtime.variables.global` and `module.runtime.variables.<operation_id>`

**Event Dispatcher:**
- [ ] New module at `sentinel/runtime/event_dispatcher.lua`
- [ ] Wraps existing `core.event_bus` with runtime-specific event types
- [ ] Maps Sylvannas game events to runtime events:
  - `QUEST_LOG_UPDATE` → `QuestAccepted`, `QuestCompleted`, `QuestFailed`
  - `UNIT_HEALTH` changes → `HealthChanged`
  - `BAG_UPDATE` → `InventoryChanged`
  - `PLAYER_ENTERING_WORLD` → `ZoneEntered`
  - Combat kill → `KillEvent` (with creature entry, position)
  - Player death → `DeathEvent` (with position, killer)
- [ ] Runtime modules subscribe to these events for exit condition evaluation and state updates
- [ ] Event data includes relevant context (quest ID, NPC entry, position, etc.)

**Profile State Machine:**
- [ ] New module at `sentinel/runtime/profile_state.lua`
- [ ] Per-Profile states: `Idle → Ready → Executing → Waiting → Finished → Idle`
- [ ] Per-Operation states: `Locked → Ready → Active → Completed / Failed / Aborted / Skipped`
- [ ] State transitions validated (cannot go from Idle to Executing without Ready)
- [ ] Error recovery: `Failed → Recovering → Retry → Active` or `Failed → Aborted`
- [ ] State persisted in blackboard at `module.runtime.profile_state` and `module.runtime.operations.<id>.state`
- [ ] State changes published to event bus for UI observation
- [ ] Unit tests: valid transitions succeed, invalid transitions error, error recovery path works
