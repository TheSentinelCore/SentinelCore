# SentinelCore 🧭

SentinelCore is a monorepo for navigation and gathering systems used by Sentinel plugins.

This README is a **developer reference**: who owns what, where logic lives, and where to implement changes.

## Repo Layout 📂

```text
SentinelCore/
|- SentinelNavServer/      Rust navigation HTTP service
|- SentinelNavClient/      Lua navigation client/plugin facade
|- SentinelGather/         Lua gathering plugin built on SentinelNavClient
|- docs/
|  `- plans/               Architecture and migration plans
`- README.md
```

## Ownership Matrix 👥

| Component | Main Role | Owns |
| --- | --- | --- |
| `SentinelNavServer` | Compute + API | Navmesh compute, routing endpoints, validation, path post-processing |
| `SentinelNavClient` | Runtime orchestration | Movement state machine, HTTP integration, UI framework/tabs, plugin facade |
| `SentinelGather` | Domain workflow | Gathering behavior, profiles, safety/inventory flow, bot lifecycle |

## Component Responsibilities ⚙️

### `SentinelNavServer` (Rust) 🦀

**Primary responsibility:** navmesh compute engine and API surface.

- Loads and queries navmesh data (Recast/Detour stack).
- Exposes endpoints for pathfinding, multi-stop routes, TSP, tactical helpers (flee/kite/LOS), and spatial queries.
- Owns request validation and server-side route/path processing.
- Holds integration and unit tests for API and path logic.

**Edit here:**
- Endpoint behavior: `SentinelNavServer/src/routes/`
- Routing/path pipeline: `SentinelNavServer/src/pipeline.rs`
- Validation rules: `SentinelNavServer/src/validation.rs`
- API docs/contracts: `SentinelNavServer/docs/`

### `SentinelNavClient` (Lua) 🌐

**Primary responsibility:** runtime navigation orchestration for Sylvannas.

- Calls `SentinelNavServer` over HTTP.
- Provides shared facade APIs consumed by plugins.
- Manages path requests, follow logic, repath/stuck recovery, and obstacle-aware movement.
- Hosts settings/UI layer (AstroUI tabs + window composition).

**Edit here:**
- HTTP request/response mapping: `SentinelNavClient/core/Navigation.lua`
- Movement orchestration/state logic: `SentinelNavClient/core/Movement.lua`
- Obstacle handling: `SentinelNavClient/core/Obstacle.lua`
- UI framework/theme/controls: `SentinelNavClient/shared/AstroUI.lua`
- UI composition/tabs: `SentinelNavClient/ui/`
- Public plugin-facing surface: `SentinelNavClient/Facade.lua`

### `SentinelGather` (Lua) 🌿

**Primary responsibility:** gathering domain behavior.

- Profile-driven routes and node processing.
- Safety/inventory/mount/stats workflows.
- Bot lifecycle and gather execution flow.
- Uses `SentinelNavClient` for navigation concerns.

**Edit here:**
- Core orchestration: `SentinelGather/core/`
- Gathering modules: `SentinelGather/modules/`
- Data/profiles and settings UI: `SentinelGather/data/`, `SentinelGather/ui/`
- Product and design docs: `SentinelGather/docs/`

## Interaction Flow 🔄

1. `SentinelGather` requests movement/navigation actions from `SentinelNavClient`.
2. `SentinelNavClient` decides runtime behavior and sends compute requests to `SentinelNavServer`.
3. `SentinelNavServer` computes results and returns JSON responses.
4. `SentinelNavClient` applies those results in-game (movement execution + state transitions).

## Source of Truth 📌

- Server API behavior: `SentinelNavServer/src/routes/` and `SentinelNavServer/docs/API_DESIGN.md`
- Client API usage/contracts: `SentinelNavClient/docs/API.md`
- Gathering product behavior: `SentinelGather/docs/PRD.md`

## Change Discipline ✅

- Keep server/client API changes synchronized.
- Update route/request models on server side and request parsing/builders on client side in the same change set.
- Update docs when contracts change.
- Keep gathering domain logic out of nav layers.
