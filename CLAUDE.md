# CLAUDE.md - Scripts Workspace

> **Purpose**: High-level context for the multi-project workspace.

## Workspace Overview

Mono-repo containing Lua bot scripts and Rust backend services for World of Warcraft automation, built on the **Sylvannas API** (no WoW Lua APIs).

## Projects

| Directory | Language | Purpose |
|-----------|----------|---------|
| `GatherBuddy/` | Lua | Gathering bot — herb/ore route following with UI |
| `NavBuddy/` | Rust | Pathfinding HTTP server (Recast/Detour navmesh) |
| `ProfileBuddy/` | Rust | TUI app for generating gathering profiles from GatherMate2 data |
| `UIExample/` | Lua | Reference implementation of the shared UI library |

### Shared Lua Libraries

| Directory | Purpose |
|-----------|---------|
| `common/` | Shared utilities (izi SDK, geometry/vec3, etc.) |
| `core_lua/` | Core Lua helpers |
| `core_universal_kicks/` | Interrupt/kick logic |
| `core_universal_utility/` | Universal utility functions |

## Key Constraints

- **Sylvannas API only** — never use WoW Lua APIs. API docs are in `.api/` and `documentation/` folders.
- **GET-only HTTP** — NavBuddy endpoints must be GET because the Lua client uses `core.http_get` (no POST support).
- **Shared UI library** — `UIExample/rotation_settings_ui.lua` is the canonical copy; `GatherBuddy/shared/rotation_settings_ui.lua` must stay in sync.
- **`require()` resolution** — relative to the script's own folder. Only `.api/common/` paths are global. Each script needs its own copy of shared libraries in its `shared/` folder.

## Cross-Project Integration

```
GatherBuddy (Lua)                    NavBuddy (Rust)
┌──────────────────┐                 ┌──────────────────────┐
│ NavigationClient │──core.http_get──│ GET /api/v1/path     │
│   .lua           │                 │ GET /api/v1/path-tsp │
│                  │                 │ GET /api/v1/move     │
│ MovementModule   │                 │ GET /api/v1/raycast  │
│   .lua           │                 │ ... (18 endpoints)   │
└──────────────────┘                 └──────────────────────┘
         │
         ▼
ProfileBuddy (Rust TUI)
┌──────────────────┐
│ Generates JSON   │──writes──→ GatherBuddy profile files
│ gathering routes │
└──────────────────┘
```

- **GatherBuddy → NavBuddy**: `NavigationClient.lua` sends HTTP GET requests to NavBuddy for pathfinding, raycasting, random points, and the intelligence/tactical endpoints.
- **ProfileBuddy → GatherBuddy**: ProfileBuddy generates JSON profile files that GatherBuddy loads via `ProfileManager.lua`.

## Build Commands

```bash
# NavBuddy (Rust)
cd NavBuddy && cargo build --release
cd NavBuddy && cargo test
cd NavBuddy && cargo clippy

# ProfileBuddy (Rust)
cd ProfileBuddy && cargo build --release
cd ProfileBuddy && cargo test

# Lua scripts don't need building — loaded at runtime by Sylvannas
```

## GatherBuddy Structure

```
GatherBuddy/
├── main.lua                    # Entry point: menu elements, profile scanning, overlay
├── init.lua                    # Initialization
├── header.lua                  # Script metadata
├── core/Constants.lua          # Shared constants and default settings
├── modules/
│   ├── NavigationClient.lua    # HTTP client for NavBuddy API
│   ├── MovementModule.lua      # Waypoint following via simple_movement
│   ├── GatherModule.lua        # Herb/ore gathering logic
│   ├── ProfileManager.lua      # Profile loading/switching
│   ├── NodeScanner.lua         # Node detection
│   ├── PathVisualizer.lua      # 3D overlay (circle_3d/line_3d)
│   ├── SafetyModule.lua        # Anti-detection, danger avoidance
│   ├── StatisticsModule.lua    # Gathering statistics tracking
│   ├── InventoryModule.lua     # Bag management
│   └── MountModule.lua         # Mount/dismount handling
├── ui/
│   ├── window.lua              # UI orchestrator: creates RotationSettingsUI
│   ├── settings_sync.lua       # Batch syncs menu element values to Settings
│   └── tabs/                   # One file per tab
│       ├── profile_tab.lua
│       ├── gather_tab.lua
│       ├── nav_tab.lua
│       ├── safety_tab.lua
│       └── stats_tab.lua
├── shared/
│   └── rotation_settings_ui.lua  # Copy of UIExample — must keep in sync
├── data/                       # Profile data files
├── docs/                       # Documentation
└── utils/                      # JSON parser, Logger, helpers
```

## GatherBuddy Key Patterns

- **Menu elements** with string IDs persist across sessions (e.g. `"gb_gather_herbs"`)
- **Custom tab rendering** receives `(ui, y_offset)` and must return new `y_offset`
- **Profile scanning** uses `manifest.json` + known filename probing (no directory listing API)
- **3D overlay** uses `core.graphics.circle_3d`/`line_3d` (separate from window UI)
- **Theme**: "neutral" (blue accents on dark background)
- **Settings sync**: `settings_sync.lua` reads menu element values once per frame, batches into `Settings` table

## UI Library Features

The shared `rotation_settings_ui.lua` provides:
- Tab-based settings window with `TabBuilder` API
- Standard widgets: checkbox, slider, dropdown, color picker
- `custom_render` tab type for fully custom content
- `_before_tabs_fn` hook for rendering above tabs (e.g. control bars)
- Exported `LAYOUT` and `THEMES` constants for consistent styling
