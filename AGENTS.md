# AGENTS.md - SentinelCore Workspace

## Domain Constraints

- **Sylvannas API only** — never use WoW Lua APIs. API reference in `Documentation - Project Sylvannas/dev/api/` (see especially `core.md`, `input.md`, `geometry.md`).
- **Lua scripts are NOT built** — loaded at runtime by Sylvannas injector. No compile step.
- **Testing** — run `_G.SentinelCore.run_tests()` from Sylvannas console (in-game only). No `vitest` or external Lua test runners work due to Sylvannas environment.

## Project Structure

```
sentinel/                     # Combat engine + runtime (Lua)
├── modules/
│   └── combat/             # Rotation framework, spell dispatcher, target selector
├── core/                   # Shared engine (BT, blackboard, event_bus, geometry)
├── integrations/           # Adapters for external systems (izi_bridge, nav_client)
├── shared/                 # Cross-cutting libraries
├── runtime/                # Runtime infrastructure (sensors, module registry, app)
├── tests/                  # Lua tests (run via _G.SentinelCore.run_tests())
└── CONTEXT.md              # Domain glossary
```

## Execution Model

- **Behavior Trees** — combat rotation uses BT sequences (see `core/bt/`). Priority selector governs action selection.
- **Blackboard** — shared state keyed by domain (`player.*`, `combat.*`, `module.*`). Use `module.<module_name>.*` for module state.
- **Event Bus** — decoupled communication via `event_bus:subscribe/publish`. Used for engage, disengage, spell cast events.

## Cross-Service Integration

```
SentinelCore → SentinelNavClient     # NavigationAdapter wraps _G.SentinelNavClient.client
SentinelNavClient → SentinelNavServer # path, raycast, random-points endpoints
```

## Require Resolution

- Paths are relative to script folder
- `Documentation - Project Sylvannas/dev/api/*` provides Sylvannas SDK reference
- Each sub-project may need its own `shared/` copy of libraries

## Key Anti-Patterns to Avoid

- Don't use `GetLootSlotLink`, `GetItemInfo`, or other WoW APIs — use Sylvannas `core.input.*` and `core.object_manager.*`
- Don't implement inline `distance_3d` — use `core/geometry.lua::Geometry.distance()` with nil-safe semantics
- Don't add fallback logic to `queue_position` — spell_queue uses method call convention

## Domain Documentation

- `sentinel/CONTEXT.md` — domain glossary used by all modules

## Agent skills

This repository is configured for the Matt Pocock engineering skills suite. The following files define the per-repo configuration:

- `docs/agents/issue-tracker.md` — Local Markdown files under `.scratch/<feature>/`
- `docs/agents/triage-labels.md` — Canonical triage label vocabulary (bug/enhancement + 5 states)
- `docs/agents/domain.md` — Single-context domain doc layout (`sentinel/CONTEXT.md`)

Skills that depend on this setup: `to-prd`, `to-tickets`, `triage`, `grill-with-docs`, `diagnose`, `improve-codebase-architecture`.

Run `setup-matt-pocock-skills` again if the configuration drifts.
