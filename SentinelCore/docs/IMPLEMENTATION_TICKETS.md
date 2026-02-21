# SentinelCore Implementation Tickets (P0 -> P1.5)

## 1. Ticket Conventions
- ID format: `SC-###`
- Each ticket includes acceptance criteria.
- Dependencies must be satisfied before implementation.

## 2. Dependency Graph
`SC-001 -> SC-002 -> SC-003 -> SC-004 -> SC-005 -> SC-006 -> SC-007 -> SC-008 -> SC-009 -> SC-010 -> SC-011 -> SC-012 -> SC-013 -> SC-014`

## 3. Tickets
## SC-001: Repo Skeleton + Module Layout
Deliverables:
- Core folders/files for SentinelCore runtime.
- Stub modules with LuaDoc contracts.
- NavClient-style behavior folders:
  - `behaviors/actions`
  - `behaviors/conditions`
  - `behaviors/trees`
- Mode stubs:
  - `GrindMode`
  - `QuestMode` (placeholder)
  - `GatherMode` (placeholder)
  - `BgMode` (placeholder)
Acceptance:
- Loads without runtime errors.
- Public entrypoints are present.

## SC-002: EventBus + Blackboard + StateMachine
Deliverables:
- Event system.
- Shared blackboard.
- Validated state transitions.
Acceptance:
- Unit tests for event publish/subscribe and state transition guards.

## SC-003: Config + Defaults + Validation
Deliverables:
- Typed config schema.
- Defaults for P0-P1.5.
- Validation errors with fail-closed behavior.
- `scripts_data/SentinelCore` persistence schema support:
  - `vendor_inventory_policy.v1.json`
  - `runtime_state.v1.json`
  - `vendor_runtime_cache.v1.json`
Acceptance:
- Invalid configs rejected with explicit reason.
- Policy/state/cache file IO is atomic and schema-version validated.

## SC-004: Client Facade + Tick Orchestration
Deliverables:
- `start/stop/pause/resume/update/get_snapshot`.
- Deterministic service update order.
- Behavior tree orchestration ownership in `Client:update()`.
Acceptance:
- Lifecycle idempotency tests pass.

## SC-005: NavigationAdapter (SentinelNavClient)
Deliverables:
- Adapter over `_G.SentinelNavClient.client`.
- Reachability/path-cost helpers for vendor ranking.
Acceptance:
- Movement commands and callbacks handled safely.

## SC-006: WorldDataAdapter + Context Resolve
Deliverables:
- HTTP client to SentinelQueryServer.
- Context resolution step (`ui_map_id+xyz -> canonical ids`).
- Fail-closed on unresolved/low confidence.
Acceptance:
- Fails with `CTX_UNRESOLVED` / `CTX_LOW_CONFIDENCE` as required.

## SC-007: TargetingService + Scoring Engine
Deliverables:
- Candidate target collection.
- Scoring function and configurable weights.
- Adaptive radius baseline implementation.
Acceptance:
- Deterministic score outputs in test fixtures.

## SC-008: RotationEngine Contracts + Paladin Retribution Skeleton
Deliverables:
- Rotation module interface.
- Paladin Retribution module scaffold (ST + AoE).
- Queue-first cast adapter with safe fallback.
Acceptance:
- Rotation plan generation works in mocked combat contexts.

## SC-009: CombatService (Pull -> Kill Confirm)
Deliverables:
- Pull policy.
- Combat loop orchestration.
- Target-loss and timeout guards.
Acceptance:
- Combat loop exits correctly on kill/loss/failure.

## SC-010: LootService
Deliverables:
- Loot object/window workflow.
- Retry and timeout safeguards.
Acceptance:
- Loot pipeline emits completed/failed events correctly.

## SC-011: InventoryService + Policy Rules
Deliverables:
- Free-slot accounting.
- Sell policy rules:
  - `never_sell`
  - `always_sell`
  - quality filters
- Vendor trigger `min_free_slots=2`.
Acceptance:
- Trigger and policy behavior verified in tests.

## SC-012: VendorService (Same Map Only)
Deliverables:
- Nearby vendor fetch.
- Capability/faction filters.
- Reachability ranking via nav.
- Interaction and retry chain.
Acceptance:
- Same-map enforcement validated.
- No valid vendor -> fail closed.

## SC-013: GrindMode + RecoveryService
Deliverables:
- End-to-end grind mode orchestration.
- Grind behavior tree implementation in `behaviors/trees`.
- Stuck/death/path/data recovery flows.
- Failure escalation flow:
  - pause
  - bounded auto-restart attempts
  - hard-stop + failed state
Acceptance:
- Full loop: grind -> vendor -> return.
- Critical unrecoverable cases fail closed.

## SC-014: Telemetry + Docs Sync + Smoke Suite
Deliverables:
- Session metrics and snapshot UI data.
- Smoke scenarios and deterministic scripted checks.
- Docs sync update pass.
Acceptance:
- Telemetry populated and readable.
- Smoke tests pass for locked scope.

## 4. Test Categories Per Ticket
- Unit tests (pure logic).
- Integration tests (adapter + service interactions).
- Smoke tests (runtime loop sanity).

Required smoke scenarios (minimum):
1. Start Here grind loop runs for N minutes without hard failure.
2. Kill -> loot cycle completes repeatedly.
3. Inventory threshold triggers vendor flow.
4. Nearest same-map reachable vendor selected and interacted with.
5. Vendor unavailable path exhausts and fails closed.
6. Dependency outage triggers pause -> auto-restart -> hard-stop escalation.
7. Stop/pause/resume idempotency under active movement/combat.
8. Restart after failure restores persisted runtime state safely.

## 5. Done Definition
- Acceptance criteria met.
- No known fail-open critical path.
- Logs include actionable reason codes.
- Documentation references updated.
