---
title: Architecture
layout: default
nav_order: 3
---

# Architecture
{: .no_toc }

How SentinelNavClient is structured, how it initializes, and how data flows between layers.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## Four-Layer Architecture

SentinelNavClient is organized into four distinct layers. The **Client** is the recommended entry point &mdash; it handles module wiring, update ordering, and config distribution automatically.

| Layer | Module | Purpose |
|:------|:-------|:--------|
| **Plugin** | `init.lua` + `main.lua` | Singleton lifecycle, engine callbacks, `_G.SentinelNavClient` export |
| **Client** | `Client.lua` | Single entry-point. Wires and drives all modules. Event system. Shared across consumers. |
| **High-level** | `Movement.lua` + `Obstacle.lua` | Path following, stuck recovery, route planning, corridor adaptation, doodad collision detection |
| **Low-level** | `Navigation.lua` | Raw HTTP calls to SentinelNavServer. Returns paths, raycasts, heights. No movement logic. |

### Data Flow

```
Consumer Plugin
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│  Client                                                  │
│  ┌────────────────────┐  ┌────────────────────────────┐ │
│  │  Movement           │  │  Obstacle                  │ │
│  │  • Path following   │◄─│  • Ray probing             │ │
│  │  • Stuck recovery   │  │  • Avoidance zone memory   │ │
│  │  • Route planning   │──│  • Zone data → pathfinding │ │
│  │  • Deviation check  │  └────────────────────────────┘ │
│  └────────┬───────────┘                                  │
│           │                                               │
│           ▼                                               │
│  ┌────────────────────────────────────────────────┐      │
│  │  Navigation (HTTP Client)                       │      │
│  │  GET /api/v1/path, /path-avoid, /path-tsp, ... │      │
│  └────────────────────┬───────────────────────────┘      │
└───────────────────────┼──────────────────────────────────┘
                        │ core.http_get
                        ▼
              ┌──────────────────────┐
              │  SentinelNavServer   │
              │  (Rust + Detour)     │
              │  Port 47110          │
              └──────────────────────┘
```

---

## Plugin Lifecycle

SentinelNavClient follows the standard Sylvannas plugin pattern: `header.lua` &rarr; `init.lua` &rarr; `main.lua`.

### header.lua &mdash; Load Gate

Declares plugin metadata and gates loading on a valid local player:

```lua
plugin["name"]    = "Sentinel Navigation Client"
plugin["version"] = "0.0.5"
plugin["author"]  = "Nasrine"
plugin["load"]    = true  -- set to false if no local player
```

If `core.object_manager.get_local_player()` returns nil, `plugin["load"]` is set to `false` and the plugin is not loaded.

### init.lua &mdash; Singleton

The `SentinelNavClient` class manages the singleton instance:

| Method | Description |
|:-------|:------------|
| `get_instance()` | Returns or creates the singleton |
| `initialize()` | Creates `Client:new({})` with empty config (UI syncs real values) |
| `get_client()` | Returns the shared Client or nil |
| `destroy()` | Tears down client, nils singleton |

Fields: `VERSION = "0.0.05"`, `NAME = "Sentinel Navigation Client"`.

### main.lua &mdash; Entry Point

Called by the Sylvannas plugin loader. Performs the following:

1. **Eager initialization** &mdash; calls `on_load()` at module load time (not deferred to `on_update`), so the Client exists before any consumer plugin's first `on_update` fires
2. **Registers three engine callbacks:**
   - `on_update` &mdash; calls `client:update()` (drives Movement, Obstacle, and event detection)
   - `on_render` &mdash; runs `sync_to_client()` (pushes UI settings to modules) and renders the settings window
   - `on_render_menu` &mdash; renders the menu tree with version header and "Open Settings" button
3. **Exports `_G.SentinelNavClient`** &mdash; the global namespace for consumer access

### Initialization Order

```
Sylvannas starts
    │
    ├── 1. header.lua evaluated  →  plugin["load"] = true
    │
    ├── 2. main.lua loaded (module scope)
    │       └── on_load() called eagerly
    │           ├── SentinelNavClient:get_instance()
    │           ├── SentinelNavClient:initialize()
    │           │   └── Client:new({})
    │           │       ├── Navigation:new(server_config)
    │           │       ├── Movement:new(nav_client, {})
    │           │       ├── Obstacle:new({})
    │           │       └── movement:set_obstacle_module(obstacle)
    │           ├── Window.init(client)
    │           └── _G.SentinelNavClient = { ... }
    │
    ├── 3. Consumer plugins loaded
    │       └── _G.SentinelNavClient.client already available ✓
    │
    └── 4. First on_update frame
            ├── SentinelNavClient: client:update()
            └── Consumer: _G.SentinelNavClient.client:move_to(...)
```

---

## _G.SentinelNavClient Export

The global `_G.SentinelNavClient` table exposes:

| Key | Type | Description |
|:----|:-----|:------------|
| `.client` | Client \| nil | **Live getter** via metatable `__index`. Returns the shared Client, or nil before initialization. |
| `.create(config?)` | function | Returns the shared Client. Config parameter is accepted but **ignored** (backward compatibility). |
| `.create_ui(client)` | function | No-op. Returns the UIWindow handle. SentinelNavClient creates its own UI. |
| `.ui` | table | UIWindow module reference |
| `.Navigation` | class | Raw Navigation class (for standalone/advanced use) |
| `.Movement` | class | Raw Movement class (for standalone/advanced use) |
| `.Obstacle` | class | Raw Obstacle class (for standalone/advanced use) |
| `.JSON` | table | JSON encoder/decoder (`decode`, `encode`, `new`) |
| `.Helpers` | table | Utility functions module |
| `.VERSION` | string | `"0.0.05"` |

### Unload

`on_unload()` calls `SentinelNavClient:destroy()` and sets `_G.SentinelNavClient = nil`, cleaning up the global namespace.

---

## Module Wiring

The Client constructor automatically wires all modules together:

```lua
-- Inside Client:new(config):
self.nav_client = Navigation:new(nav_config)
self.movement   = Movement:new(self.nav_client, movement_config)
self.obstacle   = Obstacle:new(obstacle_config)
self.movement:set_obstacle_module(self.obstacle)
```

This wiring enables:

1. **Movement &rarr; Navigation:** Movement calls `nav_client:find_path()`, `find_path_corridor()`, `find_path_avoid()`, etc. when `move_to()` is called
2. **Movement &rarr; Obstacle:** Movement periodically calls `obstacle:probe_path_ahead()` for proactive scanning, and `obstacle:probe_forward()` for reactive stuck-recovery scanning
3. **Obstacle &rarr; Navigation (via Movement):** Detected obstacle zones are passed to `nav_client:find_path_avoid()` for rerouting around obstacles

Consumers interact with the **Client** layer, which delegates to the appropriate module.

---

## Settings Flow

SentinelNavClient's UI owns all navigation settings. The sync flow is:

```
┌────────────────────────────────────────────────────────┐
│  SentinelNavClient Settings UI                          │
│  ~40 menu elements (persisted via core.menu.*)          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │ Movement │  │ Pathfind │  │ Obstacle │  │ Debug  │ │
│  │ Tab      │  │ Tab      │  │ Tab      │  │ Tab    │ │
│  └──────────┘  └──────────┘  └──────────┘  └────────┘ │
└────────────────────────┬───────────────────────────────┘
                         │ every render frame
                         ▼
              sync_to_client()  [window.lua]
                         │
                         ▼
         client:update_config({
             movement  = { ... },
             obstacles = { ... },
         })
                         │
              ┌──────────┼──────────┐
              ▼                     ▼
    Movement:update_config()   Obstacle:update_config()
              │                     │
              ▼                     ▼
    Internal _config updated   Internal _config updated
```

**Key points:**
- Settings sync runs in `on_render` (after `on_update`), introducing a one-frame delay that is imperceptible at 60fps
- Consumer calls to `update_config()` are overwritten on the next render frame
- Navigation config (`base_url`, `max_retries`) is set once during construction and cannot be changed at runtime

---

## Update Loop

Each frame, SentinelNavClient drives the following sequence:

### on_update (every frame)

```
client:update()
    │
    ├── 1. obstacle:update()      ← compatibility hook (probing is timer-driven)
    │
    ├── 2. movement:update()      ← the main work:
    │       ├── Check pending move (casting deferral)
    │       ├── Advance waypoints (distance check)
    │       ├── Check arrival
    │       ├── Stuck detection (every stuck_check_interval)
    │       ├── Proactive obstacle scan (every proactive_obstacle_interval)
    │       ├── Deviation monitoring (every deviation_check_interval)
    │       ├── Path validation (every path_check_interval)
    │       └── Route leg advancement
    │
    └── 3. Detect state transitions → fire events
            ├── "state_change" with { from, to }
            ├── "arrived" on arrival
            ├── "stuck" on stuck detection
            └── "failed" on max stuck exceeded
```

### on_render (every render frame)

```
sync_to_client()   ← push UI settings to modules
Window.on_render() ← draw settings UI (if open)
Visualizer         ← 3D overlay (path, destination, obstacles, corridor, state)
```

---

## Server Configuration

Connection defaults are defined in `config/server.lua`:

```lua
ServerConfig = {
    base_url  = "http://78.31.71.163:47110",
    max_retries = 3,
}
```

If the config file fails to load, Navigation falls back to `http://127.0.0.1:47110` with 3 retries.

Navigation retries failed requests with exponential backoff:

| Attempt | Delay |
|:--------|:------|
| 1 | Immediate |
| 2 | 0.5s |
| 3 | 1.0s |
| 4+ | 2.0s |

Retryable HTTP status codes: `0`, `500`, `502`, `503`, `504`.

After 3 consecutive failures, `is_available()` returns `false`. Any successful request resets the failure counter.

---

## Backward Compatibility

The standalone plugin conversion maintains full backward compatibility:

| API | Status | Notes |
|:----|:-------|:------|
| `_G.SentinelNavClient.create(config)` | Works | Returns shared Client. Config param accepted but **ignored**. |
| `_G.SentinelNavClient.client` | **New** | Live getter via metatable. Primary access method. |
| `_G.SentinelNavClient.Navigation/Movement/Obstacle` | Works | Raw module classes still exposed. |
| `_G.SentinelNavClient.JSON`, `.Helpers` | Works | Utility modules still exposed. |
| `_G.SentinelNavClient.create_ui(client)` | Works | Now a no-op. Returns UIWindow handle. |
| `client:update()` by consumer | Harmless | Movement rate-limits internally. |
| `client:update_config()` by consumer | Overwritten | SentinelNavClient's sync overwrites on next render frame. |
