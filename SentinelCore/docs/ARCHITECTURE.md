# SentinelCore Architecture (P0 -> P1.5)

## 1. High-Level Components
1. `SentinelCore` (Lua plugin runtime)
2. `SentinelNavClient` (navigation/movement execution)
3. `SentinelQueryServer` (Rust, cmangos-backed world-data API)

## 2. SentinelCore Runtime Layers
## 2.1 Plugin Layer
- `header.lua`
- `init.lua`
- `main.lua`
- Registers callbacks, creates singleton client, owns lifecycle.
- UI is rendered through shared `lib/AstroUI.lua` with a `ui/window.lua` orchestrator (NavClient-style).

## 2.2 Client Facade Layer
- Single entry point for consumers/UI.
- Wires services and controls update ordering.
- Mirrors SentinelNavClient facade ownership pattern.

## 2.3 Core Systems Layer
- EventBus
- Blackboard
- State machine
- Config manager
- Telemetry/logging

## 2.4 Service Layer
- `NavigationAdapter`
  - wraps `_G.SentinelNavClient.client`
- `WorldDataAdapter`
  - HTTP calls to Rust SentinelQueryServer
- `TargetingService`
- `RotationEngine`
- `CombatService`
- `LootService`
- `InventoryService`
- `VendorService`
- `RecoveryService`

## 2.5 Behavior Layer (NavClient-Style)
BT layout parity:
- `behaviors/actions/`
- `behaviors/conditions/`
- `behaviors/trees/`

Responsibilities:
- mode orchestration decisions
- branch control for combat/loot/vendor/recovery
- state and blackboard-driven control flow

## 2.6 Mode Layer
P0-P1.5 supports one primary mode:
- `GrindMode`

Mode contract:
- `id()`
- `can_enter(ctx)`
- `build_tree(services)`
- `on_enter(ctx)`
- `tick(ctx)`
- `on_exit(ctx)`

Future mode placeholders (not in delivery scope):
- `QuestMode`
- `GatherMode`
- `BgMode`

## 3. Data and Control Flow
1. On start:
  - Resolve canonical context with SentinelQueryServer.
  - Validate dependencies and config.
  - Build/activate mode behavior tree.
2. Grind loop:
  - Acquire/scored target.
  - Move/pull/combat/loot.
  - Update telemetry and local heatmap.
3. Inventory pressure:
  - Trigger vendor flow at threshold.
  - Find nearest reachable same-map vendor.
  - Complete vendor actions and return.
4. Failure:
  - Transition to `failed`.
  - Hard-stop actions and movement.

## 4. SentinelQueryServer Architecture (Rust)
NavServer-like structure:
- `config/`
- `http/handlers/`
- `domain/models/`
- `services/`
- `storage/repositories/`
- `cache/`

Key services:
- `ContextResolveService`
- `VendorQueryService`
- `TrainerQueryService`
- `QuestQueryService`

## 5. Reliability and Safety Model
- Fail-closed policy for uncertainty.
- Explicit retry budgets and timeouts.
- Dependency watchdog:
  - nav availability
  - world-data service availability
- Safe stop path always available.

## 6. Vendor Strategy Architecture
`VendorService` pipeline:
1. Fetch candidates (same map).
2. Filter capability/faction.
3. Check reachability.
4. Rank by path cost.
5. Execute interaction.
6. Return to grind anchor.

Fallback:
- candidate temp blacklist
- next candidate retry
- fail closed if exhausted

## 7. Rotation Architecture
- `RotationRegistry`: maps class/spec to module.
- `RotationEngine`: builds action plan each tick.
- `ActionExecutor`: executes gated actions (queue-first, fallback guarded).
- `CombatService`: orchestrates rotation plan with target/liveness checks.

First implementation target:
- Paladin Retribution module.

## 8. Observability
- Structured event stream.
- Session snapshot API for UI/debug tab.
- Key counters:
  - kills/hr
  - xp/hr
  - gold/hr
  - stuck recoveries
  - vendor failures

## 9. Scalability Assumptions
- Multiple WoW clients can share one SentinelQueryServer instance.
- SentinelCore does small, on-demand API calls only.
- No client-side full dataset load.

## 10. Parity Reference
For explicit architecture parity rules, see:
- `SentinelCore/docs/NAVCLIENT_PARITY.md`
- `SentinelCore/docs/SENTINEL_QUERY_SERVER_ARCHITECTURE.md`
