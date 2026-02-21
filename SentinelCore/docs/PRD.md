# SentinelCore PRD (P0 -> P1.5)

## 1. Product Summary
SentinelCore is a TBC-only autonomous grinding bot framework for Sylvannas that prioritizes reliability and throughput, with XP/hr as the primary optimization target while remaining easy to operate ("Start Here" and run).

This PRD covers:
- P0 Foundation
- P1 Grind Core
- P1.5 Operations (inventory + vendoring)

This PRD does not include questing, battleground/PvP automation, or gathering mode execution as deliverables for this phase.
Architecture is intentionally designed to add those capabilities as future modes without rewriting the core runtime.

## 2. Scope
### 2.1 In Scope
- TBC-only runtime and data assumptions.
- SentinelNavClient integration for movement/navigation.
- Rotation framework with first-class Paladin implementation path (Retribution first; single-target and AoE behaviors).
- Autonomous local grinding loop:
  - Acquire target
  - Pull/combat
  - Loot
  - Recovery
- Inventory pressure handling and autonomous vendor loop.
- World data lookup through cmangos-derived backend (no startup scraping).
- Fail-closed runtime policy for uncertainty and invalid context.

### 2.2 Out of Scope
- Quest automation.
- PvP/BG automation.
- Multi-expansion support.
- Phase-aware gameplay logic.
- Cross-map vendor routing (same canonical map only in this phase).

### 2.3 Future-Ready By Design
- Core/mode separation allows adding:
  - `QuestMode`
  - `GatherMode`
  - `BgMode`
- Shared systems (EventBus, Blackboard, StateMachine, Behavior layer, Services) are reusable across modes.

## 3. Non-Negotiable Constraints
- TBC only.
- Canonical IDs are cmangos IDs (map_id, zone_id, area_id).
- No phased-content logic.
- Fail-closed behavior on unresolved/low-confidence context.
- Vendor selection restricted to same canonical map_id.
- No startup Wowhead scraping.

## 4. User Personas and Core Flows
### 4.1 Primary User
Operator running one or many WoW clients who wants stable autonomous grinding with minimal interaction.

### 4.2 Core User Flows
1. Start Here Grind:
  - User presses Start.
  - Bot resolves context, scans viable targets, starts grind loop.
2. Autonomous Vendor:
  - Inventory threshold reached (`min_free_slots=2`, blacklist exceptions applied).
  - Bot finds nearest reachable same-map vendor.
  - Sells/repairs according to policy and returns to grind.
3. Failure Handling:
  - Nav/path/data uncertainty encountered.
  - Bot pauses, attempts bounded self-recovery, then hard-stops and fails closed with clear reason if unrecoverable.

## 5. Functional Requirements
### 5.1 P0 Foundation
- Unified `Client` facade with strict lifecycle.
- EventBus + Blackboard + state machine.
- Config manager with schema validation and defaults.
- Profile manager (create/load/save/list/edit).
- Telemetry and diagnostics snapshots.
- World-data adapter client to Rust SentinelQueryServer.

### 5.2 P1 Grind Core
- Start Here mode without preloaded route requirement.
- Primary optimization objective: maximize XP/hr.
- Adaptive target scoring:
  - expected kill speed
  - expected loot value
  - path/travel cost
  - risk weight
- Combat execution through rotation framework (Paladin Retribution ST + AoE support in this phase).
- Loot handling pipeline with retry and timeout guards.
- Stuck/death/repath recovery logic.

### 5.3 P1.5 Operations
- Inventory rule engine:
  - `never_sell` list
  - `always_sell` list
  - quality/stack constraints
- Vendor trigger policy default `min_free_slots=2`.
- Same-map nearest reachable vendor selection.
- Return-to-grind policy after vendor completion.

## 6. UX Requirements
- Minimal operator UX:
  - `Start/Stop` primary action.
  - `Pause/Resume`.
  - Optional profile selector.
- Advanced settings behind expert panel.
- Clear on-screen state and error reason on fail-closed transitions.

## 7. Quality and Reliability Requirements
- Fail-closed over silent degradation.
- Deterministic behavior under missing data or invalid context.
- Retry budgets with capped backoff.
- Idempotent stop/teardown path.
- Human-readable structured logs.
- Failure escalation policy:
  - pause
  - bounded auto-restart attempts
  - hard-stop + failed state

## 8. Success Metrics
- Runtime stability:
  - zero hard-crash tolerance
  - no infinite-loop action spam
- Autonomy:
  - complete unattended cycles (grind -> vendor -> return)
- Productivity:
  - measurable XP/hr and loot/gold/hr improvements over static pull loops
- Recovery:
  - high successful recovery rate for common stuck/path interruptions

## 9. Risks
- Map/context ID mismatch between runtime API and canonical cmangos IDs.
- Bad vendor data quality.
- Action spam risk from raw input misuse.
- Multi-client resource contention if data lookup is inefficient.

## 10. Dependencies
- Sylvannas runtime APIs.
- SentinelNavClient.
- Rust SentinelQueryServer backed by cmangos data extract.
- Rotation modules (Paladin Retribution first).

## 11. Acceptance Criteria (Phase Gate)
- P0: core runtime, config, telemetry, world-data integration complete.
- P1: start-here grind loop runs with combat + loot + recovery.
- P1.5: autonomous same-map vendoring operational with return-to-grind.
- Fail-closed behavior verified on data/nav uncertainty.
