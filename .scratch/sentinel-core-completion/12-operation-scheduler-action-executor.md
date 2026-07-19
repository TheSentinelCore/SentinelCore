---
id: 12
title: "Operation Scheduler + Action Executor + Runtime Engine (Lua)"
state: implemented
labels: ["enhancement", "ready-for-agent", "size:large"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T14:00:00Z"
branch: "issue/12-operation-scheduler"
---

# 12 — Operation Scheduler + Action Executor (Lua)

**What to build:** The core runtime execution loop — an Operation Scheduler that selects which Operation to run based on entry conditions and priority, and an Action Executor that dispatches each RuntimeAction to the appropriate game interaction via Sylvannas APIs.

**Blocked by:** #11 (Query Client + Profile Manager — needs a loaded profile to schedule from)

**Acceptance criteria:**

**Operation Scheduler:**
- [x] New module at `sentinel/runtime/operation_scheduler.lua`
- [x] Reads `RuntimeProfile.operations` from the active profile
- [x] Filters Operations by `entry_conditions` — evaluates each condition against current character state via blackboard
- [x] Skips Operations with status: Completed, Failed, Aborted, Skipped
- [x] Selects next Operation: status=Ready, sorted by priority (highest first), then declaration order
- [x] Tracks current Operation and current Action index within that Operation
- [x] On Action completion: advance to next Action. On Operation completion: mark Completed, select next Operation.
- [x] Per-Operation state machine: `Locked → Ready → Active → Completed / Failed / Aborted / Skipped`
- [x] Entry conditions: `level_below`, `level_above`, `race_is`, `class_is`, `quest_completed`, `quest_active`, `variable_equals`
- [x] Status tracked in Blackboard at `module.runtime.op_status.<op_id>`
- [x] Events published: `operation_status_changed`, `operation_completed`, `operation_failed`, `operation_started`
- [x] 15 unit tests

**Action Executor:**
- [x] New module at `sentinel/runtime/action_executor.lua`
- [x] Receives a `RuntimeAction` and dispatches on `action_type` string:
  - [x] `pickup_quest` → interact NPC, select quest, accept
  - [x] `turn_in_quest` → interact NPC, complete quest, select reward
  - [x] `goto` → invoke NavigationAdapter, poll until arrived
  - [x] `grind_area` → hand off to combat module via blackboard signal
  - [x] `kill_target` → target creature entry, engage combat
  - [x] `vendor` → interact vendor NPC, sell/buy configured items
  - [x] `repair` → interact repair NPC, repair all
  - [x] `train` → interact trainer NPC, learn spells
  - [x] `flight_path` → interact flight master, select destination
  - [x] `hearth` → use hearthstone item from inventory
  - [x] `mailbox` → interact mailbox
  - [x] `bank` → interact banker
  - [x] `use_item` → use item from inventory by name/ID
  - [x] `wait` → sleep for configured duration_ms
  - [x] `set_variable` → write to Variable Store / blackboard
  - [x] `branch` → evaluate condition, set branch_result in blackboard
  - [x] `dungeon_marker` → set flag in blackboard
  - [x] `death_skip` → die via core.player.kill(), wait for spirit healer
  - [x] `talk_to_npc` → interact NPC with optional gossip selection
  - [x] `loot_object` → interact lootable object, wait for loot window
  - [x] `patrol` → follow configured waypoint path (async, polled)
  - [x] `escort` → follow/guard escort target (async, polled)
  - [x] `record_path` → start/stop recording player movement path
- [x] Each action handler returns: `{ status: "running" | "succeeded" | "failed", error?: string }`
- [x] RetryPolicy applied on failure: max_retries, delay_ms, backoff_multiplier
- [x] Action timeout: if action exceeds timeout_ms, force-fail with timeout error
- [x] Async actions pollable via `executor:poll()`
- [x] 26 unit tests

**Runtime Engine:**
- [x] New module at `sentinel/runtime/runtime_engine.lua`
- [x] Main tick loop tying scheduler + executor + profile_manager together
- [x] Per-frame `tick(delta_ms)` called from app loop
- [x] Engine lifecycle: start/stop/pause/resume
- [x] Auto-completes when no more ready operations
- [x] Events published: engine_started, engine_stopped, engine_paused, engine_resumed, engine_completed
- [x] 9 unit tests
