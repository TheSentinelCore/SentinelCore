# SentinelCore

SentinelCore is a monorepo for navigation and gathering systems used by Sentinel plugins.

This README is developer-focused: it explains what each module is, who owns which concerns, and where to make changes.

## Repository Map

```text
SentinelCore/
|- SentinelNavServer/      Rust navigation HTTP service
|- SentinelNavClient/      Lua navigation client/plugin facade
|- SentinelGather/         Lua gathering plugin using SentinelNavClient
|- docs/
|  `- plans/               Architecture and migration plans
`- README.md
```

## Component Responsibilities

### `SentinelNavServer` (Rust)

Primary responsibility: navmesh compute engine and API surface.

- Loads and queries navmesh data (Recast/Detour stack).
- Exposes HTTP endpoints for:
  - pathfinding,
  - multi-stop and TSP routes,
  - tactical helpers (flee/kite/LOS),
  - spatial queries (height/raycast/random points).
- Owns request validation, server-side path smoothing, and route computation.
- Contains integration and unit tests for API and path logic.

Where to change things:

- Endpoint behavior: `SentinelNavServer/src/routes/`
- Path algorithms/pipeline: `SentinelNavServer/src/pipeline.rs`
- Validation rules: `SentinelNavServer/src/validation.rs`
- API contracts/docs: `SentinelNavServer/docs/`

### `SentinelNavClient` (Lua)

Primary responsibility: runtime navigation orchestration for Sylvannas.

- Talks to `SentinelNavServer` over HTTP.
- Provides a shared `Facade` consumed by other plugins.
- Manages movement state machine:
  - path requests,
  - path following,
  - repath/stuck handling,
  - obstacle-aware behavior.
- Hosts settings/UI layer (AstroUI-based tabs).

Where to change things:

- HTTP request/response mapping: `SentinelNavClient/core/Navigation.lua`
- Movement orchestration/state: `SentinelNavClient/core/Movement.lua`
- Obstacle logic: `SentinelNavClient/core/Obstacle.lua`
- UI framework/theme/controls: `SentinelNavClient/shared/AstroUI.lua`
- UI composition/tabs: `SentinelNavClient/ui/`
- Public integration surface: `SentinelNavClient/Facade.lua`

### `SentinelGather` (Lua)

Primary responsibility: gathering domain logic.

- Profile-driven gather routes and node handling.
- Safety, inventory, mount, stats, and bot lifecycle logic.
- Uses `SentinelNavClient` facade for all navigation concerns.

Where to change things:

- Core module coordination: `SentinelGather/core/`
- Gathering behavior modules: `SentinelGather/modules/`
- Data/profiles and settings UI: `SentinelGather/data/`, `SentinelGather/ui/`
- Product and design docs: `SentinelGather/docs/`

## How Components Interact

1. `SentinelGather` asks `SentinelNavClient` for movement/navigation actions.
2. `SentinelNavClient` decides runtime movement behavior and calls `SentinelNavServer`.
3. `SentinelNavServer` computes navmesh results and returns JSON responses.
4. `SentinelNavClient` applies results in-game (movement/path progression/state updates).

In short:

- `SentinelNavServer` = compute + API.
- `SentinelNavClient` = orchestration + runtime behavior + UI.
- `SentinelGather` = domain workflow (gathering) on top of nav services.

## Source of Truth

- Navigation API behavior: `SentinelNavServer/src/routes/` and `SentinelNavServer/docs/API_DESIGN.md`
- Client API usage and facade contracts: `SentinelNavClient/docs/API.md`
- Gathering behavior/product intent: `SentinelGather/docs/PRD.md`

## Change Guidelines

- Keep server/client API changes synchronized:
  - update route handlers and request models in `SentinelNavServer`,
  - update request builders/parsers in `SentinelNavClient/core/Navigation.lua`,
  - update docs in both modules.
- Keep movement behavior changes in `SentinelNavClient/core/Movement.lua` scoped and testable.
- Avoid putting gathering domain logic in nav modules.
