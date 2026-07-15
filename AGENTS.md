# AGENTS.md - SentinelCore Workspace

## Domain Constraints

- **Sylvannas API only** — never use WoW Lua APIs. API reference in `.api/` as IntelliSense stubs.
- **Lua scripts are NOT built** — loaded at runtime by Sylvannas injector. No compile step.
- **Testing** — run `_G.SentinelCore.run_tests()` from Sylvannas console (in-game only). No `vitest` or external Lua test runners work due to Sylvannas environment.

## Project Structure

```
sentinel/               # Main grind/combat bot (Lua)
├── modules/
│   ├── grind/          # Grind phases: rest, loot, vendor, pull, acquire, combat
│   └── combat/         # Rotation framework, spell dispatcher, target selector
core/                   # Shared engine: behavior trees, blackboard, event bus
integrations/           # Adapters for external systems (nav_client)
```

## Execution Model

- **Behavior Trees** — phases are BT sequences (see `core/bt/`). Priority selector governs: safety > corpse_run > pvp > rest > loot > vendor > combat > pull > acquire.
- **Blackboard** — shared state keyed by domain (`player.*`, `combat.*`, `module.*`). Use `module.<module_name>.*` for module state.
- **Event Bus** — decoupled communication via `event_bus:subscribe/publish`. Used for death, kill, loot, stuck, engage events.

## Cross-Service Integration

```
SentinelCore → SentinelQueryServer   # core.http_get (GET endpoints only)
SentinelCore → SentinelNavClient     # NavigationAdapter wraps _G.SentinelNavClient.client
SentinelNavClient → SentinelNavServer # path, raycast, random-points endpoints
```

## Require Resolution

- Paths are relative to script folder
- `.api/common/*` is global (shared SDK access)
- Each sub-project may need its own `shared/` copy of libraries

## Key Anti-Patterns to Avoid

- Don't access `_pending_kill_targets` or `_telemetry._last_refresh_ms` directly — use public interface
- Don't use `GetLootSlotLink`, `GetItemInfo`, or other WoW APIs — use Sylvannas `core.input.*` and `core.object_manager.*`
- Don't skip nil checks before `distance_3d` — stale userdata causes runtime errors
- Don't add fallback logic to `queue_position` — spell_queue uses method call convention