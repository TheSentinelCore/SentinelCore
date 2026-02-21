# SentinelCore NavClient Parity Conventions

## 1. Goal
SentinelCore follows the SentinelNavClient architectural pattern for consistency:
- single `Client` facade
- EventBus + Blackboard + hierarchical state machine
- behavior tree orchestration layer
- service modules with strict update ownership

This is architecture parity, not a source-code clone.

## 2. Folder and Layer Parity
Recommended Lua layout:
```text
SentinelCore/
  core/
    Client.lua
    Blackboard.lua
    StateMachine.lua
    Sensors.lua
    Defaults.lua
    ConsoleLogger.lua
  events/
    EventBus.lua
    Events.lua
  services/
    NavigationAdapter.lua
    WorldDataAdapter.lua
    TargetingService.lua
    RotationEngine.lua
    CombatService.lua
    LootService.lua
    InventoryService.lua
    VendorService.lua
    RecoveryService.lua
  behaviors/
    actions/
    conditions/
    trees/
  modes/
    GrindMode.lua
    QuestMode.lua      (placeholder)
    GatherMode.lua     (placeholder)
    BgMode.lua         (placeholder)
```

## 3. Hierarchical State Convention
Top-level:
- `idle`
- `running`
- `paused`
- `failed`

Mode-level substates (grind):
- `running.grind.scout`
- `running.grind.acquire`
- `running.grind.pull`
- `running.grind.combat`
- `running.grind.loot`
- `running.grind.vendor`
- `running.grind.recover`

Failure detail is represented by reason codes, not ad-hoc state strings.

## 4. Event Naming Convention
Use dot-scoped event keys mirroring NavClient style:
- `core.state_changed`
- `core.failed`
- `grind.target_acquired`
- `grind.kill_confirmed`
- `vendor.started`
- `vendor.completed`
- `vendor.failed`
- `recovery.started`
- `recovery.completed`

Rules:
- stable dotted keys
- typed payloads
- documented in one source-of-truth file

## 5. Behavior Tree Contract
SentinelCore mode logic must be BT-driven at orchestration level.

BT responsibilities in this phase:
- target acquisition gating
- combat/loot/vendor branch selection
- failure and recovery branching
- delegation to services for execution

BT node categories:
- `conditions`: reads blackboard/state only
- `actions`: invokes services and writes blackboard
- `trees`: compose high-level mode trees

## 6. Update Ownership
Single owner of orchestration:
- `Client:update()` drives sensors, BT tick, service updates, state sync.

No consumer plugin should directly tick internal services.

## 7. Future Mode Extension Contract
All modes must implement:
- `id() -> string`
- `can_enter(ctx) -> boolean`
- `build_tree(services) -> BehaviorTree`
- `on_enter(ctx)`
- `on_exit(ctx, reason?)`
- `get_capability_flags() -> table`

Future modes:
- `QuestMode`: objective/task execution.
- `GatherMode`: node-centric resource farming.
- `BgMode`: battleground queue/combat behavior.

Implementation scope for now:
- `GrindMode` only.

## 8. Compatibility Boundary with SentinelNavClient
SentinelCore must treat SentinelNavClient as navigation execution authority:
- pathfinding/movement/repath/recovery primitives remain in NavClient.
- SentinelCore chooses intent and timing.
- NavClient performs movement mechanics.
