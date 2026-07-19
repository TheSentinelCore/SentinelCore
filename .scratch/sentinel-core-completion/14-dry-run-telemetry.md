---
id: 14
title: "Dry Run Mode + Telemetry (Lua)"
state: open
labels: ["enhancement", "ready-for-agent", "size:medium"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 14 — Dry Run Mode + Telemetry (Lua)

**What to build:** A simulation mode that exercises the full scheduler + executor pipeline without performing real game actions, and a telemetry system that records execution metrics for analysis.

**Blocked by:** #12 (Operation Scheduler + Action Executor — dry run replaces the executor, telemetry wraps it)

**Acceptance criteria:**

**Dry Run Mode:**
- [ ] New module at `sentinel/runtime/dry_run.lua`
- [ ] Same scheduler + executor pipeline, but action handlers replaced with Simulation Adapters:
  - `GoTo` → check if path exists via QueryServer route endpoint (no actual movement)
  - `GrindArea` / `KillTarget` → check if target creatures exist in the polygon via QueryServer (no combat)
  - `PickupQuest` / `TurnInQuest` → check if NPC exists and quest is available/completable via QueryServer (no interaction)
  - `Vendor` / `Repair` / `Train` / `FlightPath` → check if NPC exists with correct role (no interaction)
  - `Wait` → skip (no actual delay)
  - `SetVariable` → execute normally (no game dependency)
  - `Branch` → evaluate condition normally
- [ ] Step-by-step trace output: for each action, emit `{ action_id, action_type, result: "pass" | "warn" | "fail", message }`
  - `pass` (✓): action would succeed
  - `warn` (⚠): action might succeed but data is uncertain (e.g., NPC exists but quest availability unverified)
  - `fail` (❌): action would fail (NPC not found, no path, etc.)
- [ ] Controls: `start()`, `pause()`, `step()` (advance one action), `reset()` (restart from beginning)
- [ ] Dry run is toggled via blackboard flag `module.runtime.dry_run = true`
- [ ] Unit tests: load a profile → dry run → verify trace output has correct results for known-good and known-bad actions

**Telemetry:**
- [ ] New module at `sentinel/runtime/telemetry.lua`
- [ ] Per-Action metrics: action_id, action_type, duration_ms, success (bool), retry_count, error_message
- [ ] Per-Operation metrics: operation_id, total_duration_ms, actions_completed, actions_failed, XP gained (from combat events), gold spent (from vendor interactions), deaths
- [ ] Per-Profile metrics: profile_id, total_duration_ms, operations_completed, operations_failed, operations_skipped, completion_rate (completed / total)
- [ ] Metrics stored in profile-local analytics file: `scripts_data/sentinel/analytics/<profile_id>.json`
- [ ] `get_summary(profile_id)` returns aggregated metrics
- [ ] `get_operation_timeline(profile_id, operation_id)` returns ordered list of action metrics
- [ ] Metrics feed into UI via blackboard at `module.runtime.telemetry`
- [ ] Unit tests: record actions → verify metrics stored, get_summary returns correct aggregates
