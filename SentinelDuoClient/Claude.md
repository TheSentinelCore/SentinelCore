# SentinelDuo — Duo Frost Mage TBC Dungeon Farm Bot

## Project Overview
This is a multi-component system implementing a duo Frost Mage dungeon farming bot for WoW TBC Classic, built on the Project Sylvanas (PS) scripting API. The authoritative specification is `sentinel-duo-design.md` in the project root — treat it as the single source of truth for all architecture, API contracts, state machines, and data structures.

## Repository Structure
SentinelDuo/
├── CLAUDE.md                          # This file
├── sentinel-duo-design.md             # Design document (READ-ONLY spec)
├── server/                            # Rust coordination server
│   └── sentinel-duo-coord-server/
└── client/                            # Lua PS scripts
└── SentinelDuoFarm/

## Component Build Order
Build in this exact order. Each phase must compile/lint clean before moving to the next.

### Phase 1: Rust Coordination Server (server/)
### Phase 2: Lua Spell Data Layer (client/SentinelDuoFarm/spells/)
### Phase 3: Lua Core Infrastructure (client/SentinelDuoFarm/core/, coordination/, lib/)
### Phase 4: Lua Farm States (client/SentinelDuoFarm/states/, combat/)
### Phase 5: Lua Travel & Vendor (client/SentinelDuoFarm/travel/, loot/)
### Phase 6: Lua Profiles (client/SentinelDuoFarm/profiles/)
### Phase 7: Lua UI (client/SentinelDuoFarm/ui/)
### Phase 8: Integration Wiring (main.lua, header.lua)

## Tech Stack
- **Rust server:** Axum 0.7, Tokio, Serde, tracing. Target: stable Rust.
- **Lua client:** Lua 5.1 compatible (PS runtime). No external Lua packages — only PS API + bundled libs.
- **No WoW Lua API.** Only the Project Sylvanas custom API (see design doc §PS API Summary).

## Key Constraints
- The PS API is NOT standard WoW Lua. Functions like `core.input.cast_target_spell()`, `core.object_manager.get_local_player()`, etc. are PS-specific. Do not use any WoW addon API functions.
- `core.http_get` is ASYNC with a callback — it does not block. All HTTP communication must use callback-based patterns.
- `core.game_ui.reset_instances()` is undocumented but exists. No arguments. Use it as-is.
- The NavAdapter is pre-built (see design doc §nav_adapter). Copy it into `client/SentinelDuoFarm/navigation/NavAdapter.lua` exactly as specified.
- Spell data is pre-extracted into a static Lua table. Do NOT attempt to connect to MySQL at runtime.
- All Lua files follow PS conventions: `header.lua` and `main.lua` are the only files PS core reads directly. Everything else is `require()`'d.

## Testing Strategy
- **Rust server:** Write integration tests using `axum::test` / `tower::ServiceExt`. Test every endpoint, barrier logic, lockout math, heartbeat timeout detection.
- **Lua client:** No runtime test harness available (PS doesn't support it). Instead: ensure every module is syntactically valid Lua 5.1 (`luac -p` or `luacheck`). Write the code defensively with guard clauses and `pcall` wrappers on all PS API calls.

## Code Style
- **Rust:** Standard `rustfmt` formatting. Use `thiserror` for error types. Prefer `Arc<Mutex<>>` for shared state (design doc specifies this). Keep it simple — this is a localhost-only coordination layer, not a production web service.
- **Lua:** 4-space indentation. Local everything. Prefix all log messages with `[DuoFarm]`. Use the `---@type` and `---@class` annotations for LuaLS/sumneko intellisense. Follow PS conventions from the design doc examples.

## When Stuck
- Re-read the relevant section of `sentinel-duo-design.md`. The design doc has complete state transition tables, JSON schemas, and function signatures for every component.
- If the design doc is ambiguous on a point, make the simplest choice that satisfies the stated constraints and add a `-- TODO: Design doc ambiguous on X, assumed Y` comment.
- For PS API details beyond what's in the design doc summary, reference: https://docs.project-sylvanas.net/dev/api/core (and sibling pages listed in the design doc §reference_material).