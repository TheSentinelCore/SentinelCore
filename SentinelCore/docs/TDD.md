# SentinelCore TDD (P0 -> P1.5)

## 1. Purpose
Define the technical design for SentinelCore runtime behavior, module boundaries, event contracts, and error handling for P0 through P1.5.

## 2. Runtime Model
## 2.1 Update Loop
Single orchestrated `Client:update()` tick, called every frame.

Tick order:
1. Sensors update player/runtime context.
2. Health checks for dependencies (SentinelNavClient, SentinelQueryServer).
3. Mode controller tick (grind mode only in this phase).
4. Service updates (combat, targeting, loot, inventory, vendor).
5. Recovery supervisor (stuck/death/fail states).
6. Telemetry flush and state snapshot update.

## 2.2 Top-Level States
- `idle`
- `running`
- `paused`
- `failed`

Substate families:
- Grind: `scout`, `acquire`, `pull`, `combat`, `loot`, `vendor`, `recover`
- Failure: `dependency_unavailable`, `context_unresolved`, `path_unreachable`, `action_timeout`

Full-state naming convention (NavClient-style dotted hierarchy):
- `running.grind.scout`
- `running.grind.acquire`
- `running.grind.pull`
- `running.grind.combat`
- `running.grind.loot`
- `running.grind.vendor`
- `running.grind.recover`

## 2.3 Behavior Tree Orchestration Contract
SentinelCore uses behavior trees for mode-level orchestration parity with SentinelNavClient.

Required layout:
- `behaviors/actions`
- `behaviors/conditions`
- `behaviors/trees`

Rules:
- Conditions do not execute side effects.
- Actions own service execution and blackboard writes.
- Trees define mode control flow and branch priorities.

## 3. Core Module Boundaries
## 3.1 Client Facade
Public stable entry:
- `start(mode, opts?)`
- `stop(reason?)`
- `pause(reason?)`
- `resume()`
- `update()`
- `get_state()`
- `get_snapshot()`

## 3.2 Core Systems
- `EventBus`: typed event publish/subscribe with owner cleanup.
- `Blackboard`: centralized state store with snapshots.
- `StateMachine`: validated transitions only.
- `Config`: schema validation and defaults.
- `Telemetry`: counters, rates, and failures.

## 3.3 Service Layer
- `NavigationAdapter` (SentinelNavClient integration)
- `WorldDataAdapter` (Rust SentinelQueryServer HTTP client)
- `TargetingService`
- `RotationEngine`
- `CombatService`
- `LootService`
- `InventoryService`
- `VendorService`
- `RecoveryService`

## 3.4 Mode Extension Contract (Future-Ready)
Mode interface:
- `id() -> string`
- `can_enter(ctx) -> boolean`
- `build_tree(services) -> tree`
- `on_enter(ctx)`
- `tick(ctx)`
- `on_exit(ctx, reason?)`

Planned modes:
- `GrindMode` (in scope now)
- `QuestMode` (future)
- `GatherMode` (future)
- `BgMode` (future)

## 4. Rotation Framework Contract
Each rotation module must implement:
- `id() -> string`
- `spec() -> string`
- `can_run(ctx) -> boolean`
- `precombat(ctx) -> action[]`
- `combat(ctx) -> action[]`
- `aoe(ctx) -> action[]`
- `defensive(ctx) -> action[]`
- `interrupt(ctx) -> action[]`
- `utility(ctx) -> action[]`
- `get_pull_profile(ctx) -> table`

Action execution backend:
- Preferred: `spell_queue` adapter if available.
- Fallback: guarded `core.input.cast_*` with strict throttles and cast checks.

Phase requirement:
- Paladin rotation module must support both single-target and AoE action plans.
- First implemented Paladin spec is Retribution.

## 5. Data/Context Resolution Flow
1. Read runtime values:
  - ui map id
  - player xyz
  - instance metadata
2. Resolve canonical context via SentinelQueryServer.
3. If unresolved or ambiguous -> fail closed.
4. Bind canonical context (`map_id`, `zone_id`, `area_id`) to blackboard.

## 6. Vendoring Algorithm (Same Map Only)
1. Trigger condition: free slots <= 2 (plus policy).
2. Query nearby vendor candidates on same canonical map.
3. Filter by required service capability and faction.
4. Reachability check via SentinelNavClient per candidate.
5. Rank by path cost/time and select best.
6. Interact, sell/repair, verify success.
7. Return to grind cluster anchor.

Failure policy:
- No valid candidate -> fail closed.
- Interaction timeout -> candidate temp blacklist, retry next candidate.

## 7. Event Contracts (Selected)
- `core.state_changed`
- `core.failed`
- `grind.target_acquired`
- `grind.target_lost`
- `combat.pull_started`
- `combat.kill_confirmed`
- `loot.started`
- `loot.completed`
- `inventory.threshold_reached`
- `vendor.started`
- `vendor.completed`
- `vendor.failed`
- `recovery.started`
- `recovery.completed`

Naming rules:
- Dot-separated stable keys.
- Prefix by domain (`core`, `grind`, `combat`, `loot`, `vendor`, `recovery`).
- Event keys are constants in a single source-of-truth module.

Each event includes:
- `timestamp`
- `session_id`
- `map_id`
- `state`
- event-specific payload

## 8. Fail-Closed Policy
Escalation order for critical failures:
1. Transition to `paused`.
2. Attempt bounded self-restart (`N` retries with backoff).
3. If still failing, transition to `failed` and hard-stop.

Failure triggers:
- Context resolution fails.
- Dependency health critical.
- Navigation consistently unreachable past retry budget.
- No valid same-map vendor when required.
- Repeated critical action timeout breaches.

On fail:
- Stop movement.
- Stop cast/input actions.
- Emit structured reason.
- Preserve snapshot for debugging.

Locked defaults:
- `auto_restart_max_attempts = 3`
- `auto_restart_backoff_secs = [2, 5, 10]`

## 9. Performance Considerations
- No full-zone payload loads in Lua.
- Query only needed data windows.
- Cache small hot data with TTL and max-size bounds.
- Avoid expensive recomputation each frame (tick throttles).

## 10. Testability Requirements
- Pure-logic services must support test doubles.
- Deterministic state transitions.
- Replayable event logs.
- Explicit acceptance tests per ticket.
