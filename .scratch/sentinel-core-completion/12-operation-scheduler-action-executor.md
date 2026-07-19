---
id: 12
title: "Operation Scheduler + Action Executor (Lua)"
state: open
labels: ["enhancement", "ready-for-agent", "size:large"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 12 — Operation Scheduler + Action Executor (Lua)

**What to build:** The core runtime execution loop — an Operation Scheduler that selects which Operation to run based on entry conditions and priority, and an Action Executor that dispatches each RuntimeAction to the appropriate game interaction via Sylvannas APIs.

**Blocked by:** #11 (Query Client + Profile Manager — needs a loaded profile to schedule from)

**Acceptance criteria:**

**Operation Scheduler:**
- [ ] New module at `sentinel/runtime/operation_scheduler.lua`
- [ ] Reads `RuntimeProfile.operations` from the active profile
- [ ] Filters Operations by `entry_conditions` — evaluates each condition against current character state via blackboard
- [ ] Skips Operations with status: Completed, Failed, Aborted, Skipped
- [ ] Selects next Operation: status=Ready, sorted by priority (highest first), then declaration order
- [ ] Tracks current Operation and current Action index within that Operation
- [ ] On Action completion: advance to next Action. On Operation completion: mark Completed, select next Operation.
- [ ] Per-Operation state machine: `Locked → Ready → Active → Completed / Failed / Aborted / Skipped`

**Action Executor:**
- [ ] New module at `sentinel/runtime/action_executor.lua`
- [ ] Receives a `RuntimeAction` and dispatches on `ResolvedActionPayload` variant:
  - `PickupQuest` → interact NPC (via object_manager), select quest in dialogue, accept
  - `TurnInQuest` → interact NPC, complete quest, select reward
  - `GoTo` → invoke NavigationAdapter to path to destination coordinates
  - `GrindArea` → hand off to combat module with polygon bounds + target entries
  - `KillTarget` → target creature entry, engage combat rotation
  - `Vendor` → interact vendor NPC, sell configured items, buy configured items
  - `Repair` → interact repair NPC, repair all equipment
  - `Train` → interact trainer NPC, learn configured spells
  - `FlightPath` → interact flight master NPC, select destination flight path
  - `Hearth` → use hearthstone item from inventory
  - `Mailbox` → interact mailbox NPC, send/read mail
  - `Bank` → interact banker NPC, deposit/withdraw items
  - `UseItem` → use item from inventory by name/ID
  - `Wait` → sleep for configured duration
  - `SetVariable` → write value to Variable Store
  - `Branch` → evaluate condition, route to true/false action lists
  - `DungeonMarker` → set flag, wait for dungeon entry detection
  - `DeathSkip` → die, take spirit healer, resume from death point
- [ ] Each action handler returns: `{ status: "running" | "succeeded" | "failed", error?: string }`
- [ ] RetryPolicy applied on failure: retry_count, retry_delay_ms, backoff_multiplier
- [ ] Action timeout: if action exceeds `timeout_ms`, force-fail with timeout error
- [ ] Unit tests for each action type (mock Sylvannas APIs via offline harness): valid action → succeeded, invalid NPC → failed, timeout → force-fail, retry → eventual success
