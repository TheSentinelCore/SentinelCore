# CLAUDE.md - Scripts Workspace
## SDK Reference (scripts/.api/)

The `.api/` directory contains IntelliSense type stubs -- not runtime code. Key files:

- `core.lua` (~76KB) -- Main engine API: logging, timing, HTTP, object manager, spell book, graphics, menu, input, file I/O
- `game_object.lua` -- All game object methods (position, health, auras, casting, movement, targeting)
- `menu.lua` -- Menu element types and the window 2D drawing API
- `common/izi_sdk.lua` (~92KB) -- Extended game_object methods (health%, buff/debuff helpers, damage prediction, role helpers, time_to_die, position prediction, unit lists)
- `common/enums.lua` -- `class_id`, `power_type`, `group_role`, `collision_flags`, `schools_flag`
- `common/geometry/vec3.lua` -- Vector3 with operators, normalize, lerp, dist_to, rotate
- `common/modules/spell_queue.lua` -- Priority-based spell queue
- `common/modules/buff_manager.lua` -- Cached aura lookups
- `common/modules/spell_prediction.lua` -- Cast position prediction, AoE geometry
- `common/utility/simple_movement.lua` -- Built-in locomotion: `move_to_position`, `navigate(waypoints)`, Catmull-Rom smoothing
- `common/utility/spell_helper.lua` -- `is_spell_castable`, range/LoS checks
- `common/utility/cooldown_tracker.lua` -- Enemy spell tracking

> **Purpose**: High-level context for the multi-project workspace.

## Workspace Overview

Mono-repo containing Lua bot scripts and Rust backend services for World of Warcraft automation, built on the **Sylvannas API** (no WoW Lua APIs).

## Projects

| Directory | Language | Purpose |
|-----------|----------|---------|
| `SentinelNavClient/` | Lua | Navigation client — shared Client for all consumers |
| `SentinelNavServer/` | Rust | Pathfinding HTTP server (Recast/Detour navmesh) |
| `SentinelGather/` | Lua | Gathering bot — herb/ore route following with UI |
| `SentinelHeightQuery/` | Lua | Debug tool — query navmesh heights at player position |
| `SentinelDebugCursor/` | Lua | Debug tool — log world position under map cursor |

### Shared Lua Libraries

| Directory | Purpose |
|-----------|---------|
| `common/` | Shared utilities (izi SDK, geometry/vec3, etc.) |
| `core_lua/` | Core Lua helpers |
| `core_universal_kicks/` | Interrupt/kick logic |
| `core_universal_utility/` | Universal utility functions |

## Key Constraints

- **Sylvannas API only** — never use WoW Lua APIs. API docs are in `.api/` and `documentation/` folders.
- **GET-only HTTP** — SentinelNavServer endpoints must be GET because the Lua client uses `core.http_get` (no POST support).
- **Shared UI library** — `SentinelGather/shared/rotation_settings_ui.lua` provides the tab-based settings window.
- **`require()` resolution** — relative to the script's own folder. Only `.api/common/` paths are global. Each script needs its own copy of shared libraries in its `shared/` folder.

## Cross-Project Integration

```
SentinelNavClient (Lua)              SentinelNavServer (Rust)
┌──────────────────┐                 ┌──────────────────────┐
│ Shared Client    │                 │ GET /api/v1/path     │
│ (singleton)      │──core.http_get──│ GET /api/v1/path-tsp │
│                  │                 │ GET /api/v1/move     │
│ _G.SentinelNav   │                 │ GET /api/v1/raycast  │
│   Client         │                 │ ... (18 endpoints)   │
└──────────────────┘                 └──────────────────────┘
         │
         ▼ consumed by
┌──────────────────┐
│ SentinelGather   │  BotManager accesses _G.SentinelNavClient.client
│ SentinelHeight   │  for Navigation, Movement, and Obstacle modules
│   Query          │
└──────────────────┘
```

- **SentinelNavClient → SentinelNavServer**: The Client's Navigation module sends HTTP GET requests to SentinelNavServer for pathfinding, raycasting, random points, and tactical endpoints.
- **SentinelGather → SentinelNavClient**: `BotManager.lua` accesses `_G.SentinelNavClient.client` for the shared navigation Client.

## Build Commands

```bash
# SentinelNavServer (Rust)
cd SentinelNavServer && cargo build --release
cd SentinelNavServer && cargo test
cd SentinelNavServer && cargo clippy

# Lua scripts don't need building — loaded at runtime by Sylvannas
```

## SentinelGather Structure

```
SentinelGather/
├── main.lua                    # Entry point: menu elements, profile scanning, overlay
├── init.lua                    # Initialization
├── header.lua                  # Script metadata
├── core/
│   ├── BotManager.lua          # Bot lifecycle, module orchestration
│   ├── Constants.lua           # Shared constants and default settings
│   ├── ModuleFactory.lua       # Module registration
│   ├── Settings.lua            # Persistent settings (sentinel_gather/settings.json)
│   └── StateMachine.lua        # Bot state management
├── modules/
│   ├── Gather.lua              # Herb/ore gathering logic
│   ├── ProfileManager.lua      # Profile loading/switching
│   ├── NodeScanner.lua         # Node detection
│   ├── PathVisualizer.lua      # 3D overlay (circle_3d/line_3d)
│   ├── Safety.lua              # Anti-detection, danger avoidance
│   ├── Statistics.lua          # Gathering statistics tracking
│   ├── Inventory.lua           # Bag management
│   └── Mount.lua               # Mount/dismount handling
├── ui/
│   ├── window.lua              # UI orchestrator: creates RotationSettingsUI
│   ├── SettingsSync.lua        # Batch syncs menu element values to Settings
│   └── tabs/                   # One file per tab
│       ├── profile_tab.lua
│       ├── gather_tab.lua
│       ├── safety_tab.lua
│       └── stats_tab.lua
├── shared/
│   └── rotation_settings_ui.lua  # Tab-based settings window library
├── lib/                        # JSON parser, Logger, helpers
├── data/                       # Profile data files
└── docs/                       # Documentation
```

## SentinelGather Key Patterns

- **Menu elements** with string IDs persist across sessions (e.g. `"sg_gather_herbs"`)
- **Custom tab rendering** receives `(ui, y_offset)` and must return new `y_offset`
- **Profile scanning** uses `manifest.json` + known filename probing (no directory listing API)
- **3D overlay** uses `core.graphics.circle_3d`/`line_3d` (separate from window UI)
- **Theme**: "neutral" (blue accents on dark background)
- **Settings sync**: `SettingsSync.lua` reads menu element values once per frame, batches into `Settings` table

## UI Library Features

The shared `rotation_settings_ui.lua` provides:
- Tab-based settings window with `TabBuilder` API
- Standard widgets: checkbox, slider, dropdown, color picker
- `custom_render` tab type for fully custom content
- `_before_tabs_fn` hook for rendering above tabs (e.g. control bars)
- Exported `LAYOUT` and `THEMES` constants for consistent styling
