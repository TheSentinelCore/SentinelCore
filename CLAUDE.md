# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

SentinelCore is a monorepo for a World of Warcraft (TBC/retail) automation stack running on the
**Project Sylvannas** injector. It has two halves: Lua that runs inside the game client
(`sentinel/`, `SentinelNavClient/`) and Rust services + tooling that run outside it
(`sentinel-questing/`, `SentinelQueryServer/`, `SentinelNavServer/`). The questing side follows a
**compile-before-execute** architecture — guides are imported, validated, and compiled into a
resolved Runtime Profile JSON, and only that JSON is ever executed in-game.

## Commands

### Lua tests (the primary dev loop)

Lua is **not built** — Sylvannas loads it at runtime. Tests run offline against mocked `core.*`
Sylvannas APIs. Only `luajit` is installed; there is no `lua` binary.

```bash
# Full offline suite — MUST be run from the repo root (package.path is root-relative)
luajit sentinel/tests/run_offline.lua
```

To run a single suite, either trim the `test_modules` list in `sentinel/tests/run_offline.lua`,
or require it directly after the same mock setup:

```bash
luajit -e 'package.path="sentinel/?.lua;sentinel/?/?.lua;sentinel/?/?/?.lua;sentinel/?/?/?/?.lua;"..package.path; require("tests/modules/questing/test_runtime_nav").run()'
```

Each suite exports either a `run()` function or `test*` functions; the runner handles both.

### Rust

Each Rust tree is its own workspace/package — `cargo` commands must be run from inside it.

```bash
cd sentinel-questing && cargo test              # whole questing workspace
cd sentinel-questing && cargo test -p sentinel-importer   # one crate
cd SentinelNavServer  && cargo test             # needs clang + C++14 (bindgen/FFI)
cd SentinelQueryServer && cargo test
```

### Running the services

```bash
# QueryServer — game DB lookups (NPCs, quests, vendors) on 127.0.0.1:3030
cd SentinelQueryServer && SENTINEL_DB=../tbcmangos.sqlite cargo run

# Editor API — project CRUD/compile/validate/undo on 0.0.0.0:3031
cd sentinel-questing && cargo run -p sentinel-editor
#   env: SENTINEL_EDITOR_PORT, SENTINEL_PROJECTS_DIR

# NavServer — pathfinding on 0.0.0.0:47110 (see SentinelNavServer/config.toml)
cd SentinelNavServer && cargo run --release -- --config config.toml
```

### Questing toolchain

```bash
# Batch-import RestedXP guides → Project JSON (offline, no QueryServer needed;
# unresolved NPCs/quests surface as diagnostics to fix in the editor)
cd sentinel-questing && cargo run -p sentinel-editor --bin import-guides -- \
    "../sentinel/docs/adr/restedxp guides" ".questing/projects"

# Compile a Project JSON → Runtime Profile JSON
cd sentinel-questing && cargo run -p sentinel-compiler --bin sentinel-compile -- \
    project.json profile.json
```

## Architecture: the questing pipeline

```
RestedXP guide → sentinel-importer → Project JSON → sentinel-validator
                                                  → sentinel-compiler → Runtime Profile JSON
                                                                      → Lua runtime (sentinel/)
```

The authoritative contracts live in `sentinel/docs/adr/01_ARCHITECTURE.md` and
`05_Runtime_&_Execution Model.md`. Crate ownership (`sentinel-questing/Cargo.toml`):

| Crate (dir) | Package | Owns |
| --- | --- | --- |
| `shared/` | `sentinel-models` | Authoring + runtime data models (`authoring::Project`, `runtime::*`) |
| `importer/` | `sentinel-importer` | RestedXP lexer, guide splitter, step/project builders |
| `validator/` | `sentinel-validator` | Semantic diagnostics over a Project |
| `compiler/` | `sentinel-compiler` | Project → RuntimeProfile lowering + content hash |
| `queryclient/` | `sentinel-queryclient` | HTTP + in-memory clients for QueryServer |
| `editor/` | `sentinel-editor` | HTTP API (`/editor/projects/*`) with undo/redo history |
| `runtime/` | `sentinel-runtime` | Lua FFI / loader spec |
| `tests/` | `sentinel-tests` | Cross-crate validate → compile → serialize E2E |

**The compiler is where references get resolved.** `compiler/src/lib.rs::resolve_action` maps NPC
UUIDs to integer `npc_entry` values before emitting the profile. The Lua runtime consumes only
concrete entry IDs and coordinates — never add reference resolution to the Lua side.

## Architecture: the Lua runtime (`sentinel/`)

Boot chain:

```
sentinel/main.lua        registers Sylvannas callbacks, exposes _G.Sentinel, owns the quest editor UI
  └ runtime/app.lua      SentinelApp:new/initialize — wires EventBus, Blackboard, ErrorBoundary,
                         ModuleRegistry, SensorHub, CallbackBridge, NavAdapter, IziBridge
      └ runtime/module_registry.lua
```

`ModuleRegistry.modules` in `sentinel/runtime/module_registry.lua` is a **declarative table** —
adding a module means adding an entry there with `namespace`, `capabilities`, `configuration`
(including `priority`), and an `init(blackboard, event_bus)` thunk. Currently `combat`
(priority 10) and `questing` (priority 50). Lifecycle states: UNLOADED → LOADED → INITIALIZING →
ACTIVE → SHUTDOWN.

Shared infrastructure:

- **Blackboard** (`core/blackboard.lua`) — typed key-value state, scoped by domain: `player.*`,
  `combat.*`, and `module.<module_name>.*` for module-owned state.
- **EventBus** (`core/event_bus.lua`) — decoupled pub/sub for engage, disengage, spell cast,
  stuck, death events.
- **Behavior trees** (`core/bt/`) — combat rotations are BT sequences under a priority selector.
- **Geometry** (`core/geometry.lua`) — use `Geometry.distance()` (nil-safe, returns infinity)
  rather than inlining `distance_3d`.

Questing execution path: `modules/questing/init.lua` (registry wrapper) → `module.lua` (lifecycle)
→ `runtime_profile.lua` → `runtime_action.lua` (one handler per action type). `runtime_profile.lua`
is a recovery state machine — `running | navigating | ghost | failed | finished` — with retry
budgets, nav/ghost timeouts, and progress persisted alongside the profile as
`<profile>.save.json`.

## Service topology

| Caller | Callee | Port | Via |
| --- | --- | --- | --- |
| `sentinel/shared/query_client.lua` | SentinelQueryServer | 3030 | `core.http_get` |
| `sentinel/modules/questing/editor_ui.lua` | sentinel-editor | 3031 | `core.http_get` / `core.http_post` |
| `sentinel/integrations/nav_client/adapter.lua` | SentinelNavClient (`_G.SentinelNavClient.client`) | — | in-process Lua |
| SentinelNavClient | SentinelNavServer | 47110 | HTTP GET only |

NavServer is GET-only by design: the Lua client can only issue `core.http_get`.

## Sylvannas constraints

These are enforced by the injector, not by convention — violating them fails at runtime.

- **Sylvannas API only.** No WoW Lua APIs (`GetItemInfo`, `GetLootSlotLink`, `GetTime`, …). Use
  `core.object_manager.*`, `core.input.*`, `core.quests.*`, `core.inventory.*`, and `core.time()`.
  Reference: `docs/SylvannasAPI/dev/api/` — especially `core.md`, `input.md`, `geometry.md`,
  `file-io.md`.
- **Windows and menu elements must be created in the tick callback**, never inside a render
  callback. See the `ensure_frames_created()` split in `sentinel/main.lua`.
- **File IO** is `core.read_data_file` / `core.write_data_file`.
- `spell_queue` uses method-call convention — do not add fallback logic to `queue_position`.

## Where to look first

- `sentinel/CONTEXT.md` — domain glossary shared by all modules.
- `sentinel/docs/adr/` — `01_ARCHITECTURE.md` (system boundaries), `02_DATA_MODEL.md` (schemas),
  `03_EDITOR_AND_IMPORTER.md`, `05_Runtime_&_Execution Model.md` (the runtime contract no
  implementation may violate).
- `SentinelNavServer/CLAUDE.md` and `SentinelNavClient/CLAUDE.md` — detailed per-service guides
  (FFI ownership, the `acquire_query!` macro, the pathfinding pipeline). Read those before
  touching navigation.

## Known state

`luajit sentinel/tests/run_offline.lua` currently reports **28 passed, 2 failed** on a clean
checkout of `wave-3-navigation`. The two failures are pre-existing, not regressions:

- `tests/modules/combat/test_module.run` — combat queues a spell for a non-hostile direct target.
- `tests/modules/questing/test_runtime_persistence.run` — `test_restore_state_from_save`.
