# AGENTS.md - SentinelCore Workspace

## Domain Constraints

- **Sylvannas API only** — never use WoW Lua APIs. API reference in `Documentation - Project Sylvannas/dev/api/` (see especially `core.md`, `input.md`, `geometry.md`).
- **Lua scripts are NOT built** — loaded at runtime by Sylvannas injector. No compile step.
- **Testing** — run `_G.SentinelCore.run_tests()` from Sylvannas console (in-game only). No `vitest` or external Lua test runners work due to Sylvannas environment.

## Project Structure

```
sentinel/                     # Main grind/combat bot (Lua)
├── modules/
│   ├── grind/              # Grind phases: rest, loot, vendor, pull, acquire
│   │   └── phases/         # BT phase implementations
│   ├── combat/             # Rotation framework, spell dispatcher, target selector
│   ├── battleground/       # PvP battleground strategies
│   ├── quest/              # Quest automation
│   ├── lfg/              # Looking-for-group helpers
│   └── mail/               # Mail automation
├── core/                   # Shared engine (BT, blackboard, event_bus, geometry)
├── integrations/           # Adapters for external systems (nav_client)
├── shared/                 # Cross-cutting libraries
├── runtime/                # Runtime infrastructure (sensors, module registry)
├── tests/                  # Lua tests (run via _G.SentinelCore.run_tests())
├── docs/
│   └── adr/                # Architecture decisions
└── CONTEXT.md              # Domain glossary
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
- `Documentation - Project Sylvannas/dev/api/*` provides Sylvannas SDK reference
- Each sub-project may need its own `shared/` copy of libraries

## Key Anti-Patterns to Avoid

- Don't access `_pending_kill_targets` or `_telemetry._last_refresh_ms` directly — use public interface
- Don't use `GetLootSlotLink`, `GetItemInfo`, or other WoW APIs — use Sylvannas `core.input.*` and `core.object_manager.*`
- Don't implement inline `distance_3d` — use `core/geometry.lua::Geometry.distance()` with nil-safe semantics
- Don't add fallback logic to `queue_position` — spell_queue uses method call convention

## Domain Documentation

- `CONTEXT.md` — domain glossary used by all modules
- `docs/adr/` — architecture decisions for deep modules