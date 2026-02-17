# SentinelNavClient

Standalone Sylvannas plugin providing navmesh pathfinding and path-following movement via the [SentinelNavServer](../../SentinelNavServer/) server.

SentinelNavClient runs as its own plugin with a built-in settings UI, drives its own update loop, and exposes a shared Client that any consumer plugin (SentinelGather, BgBuddy, etc.) can use for navigation — no setup required.

## Requirements

- **SentinelNavServer server** running (Rust HTTP server with Recast/Detour navmesh)
- **Sylvannas** with plugin loader (SentinelNavClient registers as a plugin via `header.lua` + `main.lua`)

## Plugin Structure

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
│   ├── Navigation.lua          HTTP client for SentinelNavServer
│   ├── Movement.lua            Path following, stuck recovery, routes
│   └── Obstacle.lua            Collision detection, avoidance zones
├── lib/
│   ├── AstroUI.lua             Tab-based UI library
│   ├── Helpers.lua             Utility functions
│   └── JSON.lua                JSON encoder/decoder
├── ui/
│   ├── Visualizer.lua          3D overlay visualization
│   ├── window.lua              Settings UI orchestrator
│   └── tabs/
│       ├── movement_tab.lua
│       ├── pathfinding_tab.lua
│       ├── obstacles_tab.lua
│       └── debug_tab.lua
└── docs/
    ├── README.md
    └── API.md
```

## Plugin Lifecycle

SentinelNavClient follows the standard Sylvannas plugin pattern: `header.lua` → `init.lua` → `main.lua`.

1. **`header.lua`** — Declares plugin metadata. Gates loading on a valid local player.
2. **`init.lua`** — Singleton class (`SentinelNavClientPlugin`) that creates and owns the shared Client.
3. **`main.lua`** — Initializes eagerly at module load time (not deferred to `on_update`), registers three engine callbacks (`on_update`, `on_render`, `on_render_menu`), and exports `_G.SentinelNavClient`.

Because SentinelNavClient initializes eagerly, the shared Client exists before any consumer plugin's `on_update` callback fires.

## Accessing SentinelNavClient

SentinelNavClient registers itself as `_G.SentinelNavClient` when loaded. The primary access method is the `client` property:

```lua
-- Recommended: live getter (returns shared Client or nil before init)
local client = _G.SentinelNavClient.client

-- Backward compatible: returns the same shared Client (config param ignored)
local client = _G.SentinelNavClient.create()

-- Raw module classes (escape hatch for advanced use)
local Navigation = _G.SentinelNavClient.Navigation
local Movement   = _G.SentinelNavClient.Movement
local Obstacle   = _G.SentinelNavClient.Obstacle

-- Utilities
local JSON    = _G.SentinelNavClient.JSON
local Helpers = _G.SentinelNavClient.Helpers
```

> **Note:** `_G.SentinelNavClient.client` uses a metatable `__index` getter, so it dynamically resolves to the current Client instance. It returns `nil` gracefully if SentinelNavClient hasn't initialized yet.

## Quick Start (Consumer Plugin)

The simplest way to use SentinelNavClient from another plugin — no config, no `update()` call, no settings management:

```lua
-- In your plugin's initialize():
if not (_G.SentinelNavClient and _G.SentinelNavClient.client) then
    core.log_error("SentinelNavClient not loaded!")
    return
end

local client = _G.SentinelNavClient.client

-- Move to a position (SentinelNavClient handles pathfinding, smoothing, obstacle avoidance)
client:move_to(destination, function(ok, reason)
    if ok then
        core.log("Arrived!")
    else
        core.log_error("Failed: " .. tostring(reason))
    end
end)

-- Check state
if client:is_moving() then
    local progress = client:get_progress()
    core.log(string.format("Waypoint %d/%d", progress.path_index, progress.path_count))
end

-- Listen for events (optional)
client:on("arrived", function() core.log("Got there!") end)
client:on("stuck", function() core.log("Stuck — recovering...") end)

-- Stop movement
client:stop()

-- Direct access to raw modules when needed
local nav_client = client.nav_client
nav_client:raycast(start, dest, function(ok, data) ... end)
```

**You do NOT need to:**
- Call `client:update()` — SentinelNavClient drives this from its own `on_update` callback
- Call `client:update_config()` — SentinelNavClient's UI syncs settings automatically
- Pass config to `create()` — SentinelNavClient's UI owns all navigation settings

## Settings Architecture

SentinelNavClient owns all navigation, movement, pathfinding, and obstacle settings via its built-in UI. Settings are synced to the Client every frame — consumers benefit immediately without any action.

### Settings Flow

```
SentinelNavClient UI Menu Elements (~40 elements, persisted via core.menu.*)
       ↓ (every render frame, in on_render callback)
sync_to_client()  [SentinelNavClient/ui/window.lua]
       ↓
client:update_config({ movement = {...}, obstacles = {...} })
       ↓
Movement:update_config()  →  updates internal _config table
Obstacle:update_config()  →  updates internal _config table
       ↓
All consumers see updated settings immediately
(because they share the same Client instance)
```

### Settings Ownership

| Owner | Settings | Where Configured |
|-------|----------|-----------------|
| **SentinelNavClient** | Waypoint tolerance, final tolerance, dynamic speed | Movement tab |
| **SentinelNavClient** | Path anti-detection (jitter), max deviation | Movement tab |
| **SentinelNavClient** | Stuck recovery (interval, distance, max attempts) | Movement tab (advanced) |
| **SentinelNavClient** | Path validation interval | Movement tab (advanced) |
| **SentinelNavClient** | Smoothing algorithm + params (iterations, samples, ratio, corner angle) | Pathfinding tab |
| **SentinelNavClient** | Path optimization, allow partial paths | Pathfinding tab |
| **SentinelNavClient** | Terrain costs (ground, water, lava) | Pathfinding tab |
| **SentinelNavClient** | Indoor corridor pathfinding + probe distance | Pathfinding tab |
| **SentinelNavClient** | Wall clearance (enable + distance) | Pathfinding tab |
| **SentinelNavClient** | Obstacle avoidance (radius, max zones, TTL, cost) | Obstacles tab |
| **SentinelNavClient** | Proactive/reactive probing (distance, spread, height, segments) | Obstacles tab |
| **Consumer** | Domain-specific settings only | Consumer's own UI |

**Example consumer-owned settings (SentinelGather):** gather types (herbs/ores), mount distance threshold, random pause/jump intervals, enemy scan radius, flee health.

### One-Frame Delay

`sync_to_client()` runs in `on_render` (after `on_update`). When a user changes a slider in the SentinelNavClient UI, the new value takes effect on the next frame. This is imperceptible at 60fps.

## Consumer Integration Guide

### Load Order

SentinelNavClient must initialize before consumers. This happens automatically because:
1. SentinelNavClient's `main.lua` calls `on_load()` eagerly (at module load time, not deferred to `on_update`)
2. By the time any consumer's `on_update` callback fires, `_G.SentinelNavClient.client` is ready

### Integration Pattern

```lua
-- 1. Check SentinelNavClient availability (in your plugin's initialize)
if _G.SentinelNavClient and _G.SentinelNavClient.client then
    self._client = _G.SentinelNavClient.client

    -- 2. Store module references if needed
    self._modules.Navigation = self._client.nav_client
    self._modules.Movement   = self._client.movement
    self._modules.Obstacle   = self._client.obstacle

    -- 3. Issue movement commands
    self._client:move_to(target, callback)

    -- 4. Query state
    local moving = self._client:is_moving()
    local state  = self._client:get_state()
else
    -- SentinelNavClient not loaded — handle gracefully
    core.log_error("SentinelNavClient not available")
end
```

### What NOT to Do

```lua
-- DON'T: Create your own Client
local my_client = Client:new(config)  -- Wrong! Use the shared one.

-- DON'T: Call update() yourself (SentinelNavClient handles it)
client:update()  -- Harmless but unnecessary.

-- DON'T: Push settings (SentinelNavClient UI owns them, your changes get overwritten)
client:update_config({ movement = { ... } })  -- Overwritten next frame.
```

### SentinelGather Example

SentinelGather's `BotManager:initialize()` accesses the shared Client:

```lua
if _G.SentinelNavClient and _G.SentinelNavClient.client then
    self._nav_client = _G.SentinelNavClient.client
    self._modules.Navigation = self._nav_client.nav_client
    self._modules.Movement   = self._nav_client.movement
    self._modules.Obstacle   = self._nav_client.obstacle
    self._nav_client_available = true
else
    self._nav_client_available = false
    self._nav_client_error = "SentinelNavClient plugin not loaded."
end
```

SentinelGather's `_update_modules()` only updates its own modules (Safety, NodeScanner, Gather, Mount, etc.). SentinelNavClient modules update themselves via SentinelNavClient's own `on_update` callback.

### BgBuddy Example

BgBuddy's `QueueManager` uses the backward-compatible `create()` API:

```lua
function QueueManager:_ensure_nav()
    if self._nav then return true end
    if not _G.SentinelNavClient or not _G.SentinelNavClient.create then
        return false
    end
    self._nav = _G.SentinelNavClient.create({})  -- Config ignored, returns shared Client
    return self._nav ~= nil
end
```

### Events

The Client fires events on movement state changes. These are optional — consumers can subscribe if they need notifications:

```lua
client:on("arrived", function() ... end)
client:on("stuck", function() ... end)
client:on("failed", function() ... end)
client:on("state_change", function(data)
    -- data.from, data.to (state strings)
end)
```

## Manual Setup (Advanced)

> **Note:** This bypasses the shared Client and creates isolated module instances. Use for standalone scripts or testing only — not recommended for plugins.

### Create a Navigation Client

```lua
local nav = _G.SentinelNavClient.Navigation:new({
    base_url = "http://localhost:47110",
    max_retries = 3,
})
```

### Find a Path

```lua
local player = core.object_manager.get_local_player()
local start = player:get_position()
local dest = { x = -8900, y = 560, z = 94 }

nav:find_path(start, dest, function(ok, data, err)
    if ok then
        for i, wp in ipairs(data.waypoints) do
            core.log(string.format("  WP %d: %.1f, %.1f, %.1f", i, wp.x, wp.y, wp.z))
        end
    else
        core.log_error("Path failed: " .. tostring(err))
    end
end, {
    smoothing = "chaikin",
    optimize = true,
})
```

### Create Movement + Follow Path

```lua
local movement = _G.SentinelNavClient.Movement:new(nav, {
    waypoint_tolerance = 3.0,
    smoothing = "chaikin",
})

movement:move_to(dest, function(success, reason)
    if success then core.log("Arrived!") end
end)

-- You must call update() yourself when using manual setup
core.register_on_update_callback(function()
    movement:update()
end)
```

## Architecture

SentinelNavClient provides four layers. The **Client** is the recommended entry point — it handles module wiring, update ordering, and config distribution automatically.

| Layer | Module | Purpose |
|-------|--------|---------|
| **Plugin** | `init.lua` + `main.lua` | Singleton lifecycle, callbacks, `_G.SentinelNavClient` export |
| **Client** | `Client` | Single entry-point. Wires and drives all modules. Events. Shared across consumers. |
| **High-level** | `Movement` | Path following, stuck recovery, route planning, corridor adaptation |
| **Detection** | `Obstacle` | Doodad collision via ray probing. Avoidance zone memory. |
| **Low-level** | `Navigation` | Raw HTTP calls to SentinelNavServer. Returns paths, raycasts, heights. No movement. |

## Settings UI

SentinelNavClient includes a built-in settings window (powered by AstroUI) with four tabs:

| Tab | Controls |
|-----|----------|
| **Movement** | Waypoint tolerance, stuck recovery, speed scaling, path anti-detection |
| **Pathfinding** | Smoothing algorithm, terrain filters, wall clearance, corridor mode |
| **Obstacles** | Avoidance radius/cost, zone TTL, proactive/reactive probe settings |
| **Debug** | 13 pathfinding test modes, avoid zone management, waypoint tools, visualization toggles |

The window starts hidden and can be toggled via the "SentinelNavClient" button in the Sylvannas menu. A "Show Advanced" toggle above the tab bar reveals advanced settings in each tab.

## Backward Compatibility

The standalone conversion maintains full backward compatibility:

| API | Status | Notes |
|-----|--------|-------|
| `_G.SentinelNavClient.create(config)` | Works | Returns shared Client. Config param accepted but **ignored**. |
| `_G.SentinelNavClient.client` | **New** | Live getter via metatable. Primary access method. |
| `_G.SentinelNavClient.Navigation/Movement/Obstacle` | Works | Raw module classes still exposed. |
| `_G.SentinelNavClient.JSON`, `_G.SentinelNavClient.Helpers` | Works | Utility modules still exposed. |
| `_G.SentinelNavClient.create_ui(client)` | Works | Now a no-op. Returns UIWindow handle. SentinelNavClient creates its own UI. |
| `client:update()` by consumer | Harmless | Movement rate-limits internally via `_tick_interval`. |
| `client:update_config()` by consumer | Overwritten | SentinelNavClient's `sync_to_client()` overwrites on next render frame. |

## API Reference

See [API.md](API.md) for the complete reference covering:
- **Client** — Recommended entry point. Move, events, state queries — all in one.
- **Navigation** — 11 SentinelNavServer endpoints, pathfinding options, callbacks
- **Movement** — Path following, routes, stuck recovery, state machine
- **Obstacle** — Doodad collision detection, avoidance zones, ray probing
