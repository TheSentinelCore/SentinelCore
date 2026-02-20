---
title: Home
layout: home
nav_order: 1
---

# SentinelNavClient

**Navmesh pathfinding and path-following navigation for Sylvannas.**
{: .fs-6 .fw-300 }

SentinelNavClient is a standalone Sylvannas plugin that provides navmesh-based pathfinding, intelligent path following, stuck recovery, obstacle avoidance, and multi-node route planning &mdash; all driven by the [SentinelNavServer](../SentinelNavServer/) Rust backend (Recast/Detour).

It runs as its own plugin with a built-in settings UI, drives its own update loop, and exposes a shared **Client** that any consumer plugin (SentinelGather, BgBuddy, etc.) can use for navigation &mdash; zero configuration required.

[Get Started](/getting-started){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[API Reference](/api/){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## Key Features

| Feature | Description |
|:--------|:------------|
| **Navmesh Pathfinding** | A* pathfinding via SentinelNavServer with Chaikin/Catmull-Rom/Bezier smoothing, waypoint optimization, and wall clearance |
| **Intelligent Path Following** | Automatic waypoint traversal with dynamic speed scaling, casting deferral, and indoor corridor adaptation |
| **Stuck Recovery** | 6-level escalating recovery: jump &rarr; probe & repath &rarr; strafe &rarr; backward &rarr; zone & repath &rarr; fail |
| **Obstacle Avoidance** | Proactive ray-based doodad detection with avoidance zone memory and automatic rerouting |
| **Multi-Node Routes** | TSP-optimized and ordered multi-stop route planning with per-leg progress callbacks |
| **Path Validation** | Periodic navmesh walkability checks with automatic repath on deviation or invalidation |
| **Tactical Movement** | Flee from threats and kite around targets with configurable parameters |
| **Built-in Settings UI** | 40+ configurable parameters across Movement, Pathfinding, Obstacles, and Debug tabs |
| **Event System** | Subscribe to `state_change`, `arrived`, `stuck`, and `failed` events |
| **Zero-Config for Consumers** | Shared singleton Client &mdash; no update loop, no config management, just `move_to()` |

---

## Quick Example

```lua
-- Get the shared Client (in your plugin's initialize)
local client = _G.SentinelNavClient.client
if not client then return end

-- Move to a position
client:move_to({ x = -8900, y = 560, z = 94 }, function(ok, reason)
    if ok then
        core.log("Arrived!")
    else
        core.log_error("Failed: " .. tostring(reason))
    end
end)

-- Listen for events
client:on("arrived", function() core.log("Got there!") end)
client:on("stuck",   function() core.log("Stuck — recovering...") end)

-- Check state
if client:is_moving() then
    local p = client:get_progress()
    core.log(string.format("Waypoint %d/%d", p.path_index, p.path_count))
end

-- Stop when needed
client:stop()
```

**You do NOT need to:**
- Call `client:update()` &mdash; SentinelNavClient drives it automatically
- Call `client:update_config()` &mdash; the built-in UI syncs settings every frame
- Pass config to `create()` &mdash; the UI owns all navigation settings

---

## Architecture Overview

SentinelNavClient is organized in four layers:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Plugin Layer   │  init.lua + main.lua                              │
│                 │  Singleton lifecycle, _G export, engine callbacks  │
├─────────────────┼───────────────────────────────────────────────────┤
│  Client Layer   │  Client.lua                                       │
│                 │  Single entry-point. Wires modules. Events.       │
├─────────────────┼───────────────────────────────────────────────────┤
│  High-level     │  Movement.lua          │  Obstacle.lua            │
│                 │  Path following, stuck  │  Ray probing, zones     │
│                 │  recovery, routes       │                          │
├─────────────────┼───────────────────────────────────────────────────┤
│  Low-level      │  Navigation.lua                                   │
│                 │  HTTP client → SentinelNavServer (14 endpoints)   │
└─────────────────┴───────────────────────────────────────────────────┘
```

```
Consumer Plugin (SentinelGather, BgBuddy, ...)
       │
       ▼
_G.SentinelNavClient.client   ◄── Shared singleton
       │
       ├── client:move_to()   → Movement → Navigation → SentinelNavServer
       ├── client:plan_route() → Movement → Navigation → SentinelNavServer
       ├── client:on("arrived") → Event callbacks
       └── client.nav_client   → Direct Navigation access (escape hatch)
```

[Read more about the architecture &rarr;](/architecture)

---

## Project Structure

```
SentinelNavClient/
├── header.lua                  Plugin metadata & load gate
├── init.lua                    Singleton lifecycle — owns the shared Client
├── main.lua                    Entry point, callbacks, _G export
├── config/
│   └── server.lua              Server connection defaults
├── core/
│   ├── Client.lua              Single entry-point client (wires all modules)
│   ├── Defaults.lua            Configuration defaults (single source of truth)
│   ├── Navigation.lua          HTTP client for SentinelNavServer (14 endpoints)
│   ├── Movement.lua            Path following, stuck recovery, routes
│   └── Obstacle.lua            Collision detection, avoidance zones
├── lib/
│   ├── AstroUI.lua             Tab-based UI library (apple theme)
│   ├── Helpers.lua             Utility functions (geometry, tables, formatting)
│   └── JSON.lua                Pure-Lua JSON encoder/decoder
├── ui/
│   ├── Visualizer.lua          3D overlay visualization
│   ├── window.lua              Settings UI orchestrator & sync
│   └── tabs/
│       ├── movement_tab.lua    Movement & stuck recovery settings
│       ├── pathfinding_tab.lua Smoothing, terrain, corridor, wall clearance
│       ├── obstacles_tab.lua   Avoidance & probing settings
│       └── debug_tab.lua       13 test modes, zone management, visualization
└── docs/
    ├── README.md
    └── API.md
```
