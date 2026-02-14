# NavLib

Standalone Sylvannas plugin providing navmesh pathfinding and path-following movement via the [NavBuddy](../../NavBuddy/) server.

NavLib runs as its own plugin with a built-in settings UI, drives its own update loop, and exposes a shared Facade that any consumer plugin (GatherBuddy, BgBuddy, etc.) can use for navigation — no setup required.

## Requirements

- **NavBuddy server** running (Rust HTTP server with Recast/Detour navmesh)
- **Sylvannas** with plugin loader (NavLib registers as a plugin via `header.lua` + `main.lua`)

## Plugin Structure

```
NavLib/
├── header.lua              Plugin metadata + player load gate
├── init.lua                Singleton lifecycle — owns the shared Facade
├── main.lua                Entry point — callbacks, _G.NavLib export
├── Facade.lua              Single entry-point facade (wires all modules)
├── core/
│   ├── Navigation.lua      HTTP client for NavBuddy (11 endpoints)
│   ├── Movement.lua        Path following, stuck recovery, route planning
│   ├── Obstacle.lua        Doodad collision detection and avoidance zones
│   └── Visualizer.lua      3D path/waypoint overlay rendering
├── ui/
│   ├── window.lua          Settings UI orchestrator (AstroUI-based)
│   └── tabs/
│       ├── movement_tab.lua
│       ├── pathfinding_tab.lua
│       ├── obstacles_tab.lua
│       └── debug_tab.lua
├── lib/
│   ├── JSON.lua            JSON encoder/decoder
│   └── Helpers.lua         Utility functions
├── shared/
│   └── AstroUI.lua         Tab-based UI library
└── docs/
    ├── README.md           This file
    └── API.md              Complete API reference (Facade, Navigation, Movement, Obstacle)
```

## Plugin Lifecycle

NavLib follows the standard Sylvannas plugin pattern: `header.lua` → `init.lua` → `main.lua`.

1. **`header.lua`** — Declares plugin metadata. Gates loading on a valid local player.
2. **`init.lua`** — Singleton class (`NavLibPlugin`) that creates and owns the shared Facade.
3. **`main.lua`** — Initializes eagerly at module load time (not deferred to `on_update`), registers three engine callbacks (`on_update`, `on_render`, `on_render_menu`), and exports `_G.NavLib`.

Because NavLib initializes eagerly, the shared Facade exists before any consumer plugin's `on_update` callback fires.

## Accessing NavLib

NavLib registers itself as `_G.NavLib` when loaded. The primary access method is the `facade` property:

```lua
-- Recommended: live getter (returns shared Facade or nil before init)
local facade = _G.NavLib.facade

-- Backward compatible: returns the same shared Facade (config param ignored)
local facade = _G.NavLib.create()

-- Raw module classes (escape hatch for advanced use)
local Navigation = _G.NavLib.Navigation
local Movement   = _G.NavLib.Movement
local Obstacle   = _G.NavLib.Obstacle

-- Utilities
local JSON    = _G.NavLib.JSON
local Helpers = _G.NavLib.Helpers
```

> **Note:** `_G.NavLib.facade` uses a metatable `__index` getter, so it dynamically resolves to the current Facade instance. It returns `nil` gracefully if NavLib hasn't initialized yet.

## Quick Start (Consumer Plugin)

The simplest way to use NavLib from another plugin — no config, no `update()` call, no settings management:

```lua
-- In your plugin's initialize():
if not (_G.NavLib and _G.NavLib.facade) then
    core.log_error("NavLib not loaded!")
    return
end

local facade = _G.NavLib.facade

-- Move to a position (NavLib handles pathfinding, smoothing, obstacle avoidance)
facade:move_to(destination, function(ok, reason)
    if ok then
        core.log("Arrived!")
    else
        core.log_error("Failed: " .. tostring(reason))
    end
end)

-- Check state
if facade:is_moving() then
    local progress = facade:get_progress()
    core.log(string.format("Waypoint %d/%d", progress.path_index, progress.path_count))
end

-- Listen for events (optional)
facade:on("arrived", function() core.log("Got there!") end)
facade:on("stuck", function() core.log("Stuck — recovering...") end)

-- Stop movement
facade:stop()

-- Direct access to raw modules when needed
local nav_client = facade.nav_client
nav_client:raycast(start, dest, function(ok, data) ... end)
```

**You do NOT need to:**
- Call `facade:update()` — NavLib drives this from its own `on_update` callback
- Call `facade:update_config()` — NavLib's UI syncs settings automatically
- Pass config to `create()` — NavLib's UI owns all navigation settings

## Settings Architecture

NavLib owns all navigation, movement, pathfinding, and obstacle settings via its built-in UI. Settings are synced to the Facade every frame — consumers benefit immediately without any action.

### Settings Flow

```
NavLib UI Menu Elements (~40 elements, persisted via core.menu.*)
       ↓ (every render frame, in on_render callback)
sync_to_facade()  [NavLib/ui/window.lua]
       ↓
facade:update_config({ movement = {...}, obstacles = {...} })
       ↓
Movement:update_config()  →  updates internal _config table
Obstacle:update_config()  →  updates internal _config table
       ↓
All consumers see updated settings immediately
(because they share the same Facade instance)
```

### Settings Ownership

| Owner | Settings | Where Configured |
|-------|----------|-----------------|
| **NavLib** | Waypoint tolerance, final tolerance, dynamic speed | Movement tab |
| **NavLib** | Path anti-detection (jitter), max deviation | Movement tab |
| **NavLib** | Stuck recovery (interval, distance, max attempts) | Movement tab (advanced) |
| **NavLib** | Path validation interval | Movement tab (advanced) |
| **NavLib** | Smoothing algorithm + params (iterations, samples, ratio, corner angle) | Pathfinding tab |
| **NavLib** | Path optimization, allow partial paths | Pathfinding tab |
| **NavLib** | Terrain costs (ground, water, lava) | Pathfinding tab |
| **NavLib** | Indoor corridor pathfinding + probe distance | Pathfinding tab |
| **NavLib** | Wall clearance (enable + distance) | Pathfinding tab |
| **NavLib** | Obstacle avoidance (radius, max zones, TTL, cost) | Obstacles tab |
| **NavLib** | Proactive/reactive probing (distance, spread, height, segments) | Obstacles tab |
| **Consumer** | Domain-specific settings only | Consumer's own UI |

**Example consumer-owned settings (GatherBuddy):** gather types (herbs/ores), mount distance threshold, random pause/jump intervals, enemy scan radius, flee health.

### One-Frame Delay

`sync_to_facade()` runs in `on_render` (after `on_update`). When a user changes a slider in the NavLib UI, the new value takes effect on the next frame. This is imperceptible at 60fps.

## Consumer Integration Guide

### Load Order

NavLib must initialize before consumers. This happens automatically because:
1. NavLib's `main.lua` calls `on_load()` eagerly (at module load time, not deferred to `on_update`)
2. By the time any consumer's `on_update` callback fires, `_G.NavLib.facade` is ready

### Integration Pattern

```lua
-- 1. Check NavLib availability (in your plugin's initialize)
if _G.NavLib and _G.NavLib.facade then
    self._facade = _G.NavLib.facade

    -- 2. Store module references if needed
    self._modules.Navigation = self._facade.nav_client
    self._modules.Movement   = self._facade.movement
    self._modules.Obstacle   = self._facade.obstacle

    -- 3. Issue movement commands
    self._facade:move_to(target, callback)

    -- 4. Query state
    local moving = self._facade:is_moving()
    local state  = self._facade:get_state()
else
    -- NavLib not loaded — handle gracefully
    core.log_error("NavLib not available")
end
```

### What NOT to Do

```lua
-- DON'T: Create your own Facade
local my_facade = Facade:new(config)  -- Wrong! Use the shared one.

-- DON'T: Call update() yourself (NavLib handles it)
facade:update()  -- Harmless but unnecessary.

-- DON'T: Push settings (NavLib UI owns them, your changes get overwritten)
facade:update_config({ movement = { ... } })  -- Overwritten next frame.
```

### GatherBuddy Example

GatherBuddy's `BotManager:initialize()` accesses the shared Facade:

```lua
if _G.NavLib and _G.NavLib.facade then
    self._navlib = _G.NavLib.facade
    self._modules.Navigation = self._navlib.nav_client
    self._modules.Movement   = self._navlib.movement
    self._modules.Obstacle   = self._navlib.obstacle
    self._navlib_available = true
else
    self._navlib_available = false
    self._navlib_error = "NavLib plugin not loaded."
end
```

GatherBuddy's `_update_modules()` only updates its own modules (Safety, NodeScanner, Gather, Mount, etc.). NavLib modules update themselves via NavLib's own `on_update` callback.

### BgBuddy Example

BgBuddy's `QueueManager` uses the backward-compatible `create()` API:

```lua
function QueueManager:_ensure_nav()
    if self._nav then return true end
    if not _G.NavLib or not _G.NavLib.create then
        return false
    end
    self._nav = _G.NavLib.create({})  -- Config ignored, returns shared Facade
    return self._nav ~= nil
end
```

### Events

The Facade fires events on movement state changes. These are optional — consumers can subscribe if they need notifications:

```lua
facade:on("arrived", function() ... end)
facade:on("stuck", function() ... end)
facade:on("failed", function() ... end)
facade:on("state_change", function(data)
    -- data.from, data.to (state strings)
end)
```

## Manual Setup (Advanced)

> **Note:** This bypasses the shared Facade and creates isolated module instances. Use for standalone scripts or testing only — not recommended for plugins.

### Create a Navigation Client

```lua
local nav = _G.NavLib.Navigation:new({
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
local movement = _G.NavLib.Movement:new(nav, {
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

NavLib provides four layers. The **Facade** is the recommended entry point — it handles module wiring, update ordering, and config distribution automatically.

| Layer | Module | Purpose |
|-------|--------|---------|
| **Plugin** | `init.lua` + `main.lua` | Singleton lifecycle, callbacks, `_G.NavLib` export |
| **Facade** | `Facade` | Single entry-point. Wires and drives all modules. Events. Shared across consumers. |
| **High-level** | `Movement` | Path following, stuck recovery, route planning, corridor adaptation |
| **Detection** | `Obstacle` | Doodad collision via ray probing. Avoidance zone memory. |
| **Low-level** | `Navigation` | Raw HTTP calls to NavBuddy. Returns paths, raycasts, heights. No movement. |

## Settings UI

NavLib includes a built-in settings window (powered by AstroUI) with four tabs:

| Tab | Controls |
|-----|----------|
| **Movement** | Waypoint tolerance, stuck recovery, speed scaling, path anti-detection |
| **Pathfinding** | Smoothing algorithm, terrain filters, wall clearance, corridor mode |
| **Obstacles** | Avoidance radius/cost, zone TTL, proactive/reactive probe settings |
| **Debug** | 13 pathfinding test modes, avoid zone management, waypoint tools, visualization toggles |

The window starts hidden and can be toggled via the "NavLib" button in the Sylvannas menu. A "Show Advanced" toggle above the tab bar reveals advanced settings in each tab.

## Backward Compatibility

The standalone conversion maintains full backward compatibility:

| API | Status | Notes |
|-----|--------|-------|
| `_G.NavLib.create(config)` | Works | Returns shared Facade. Config param accepted but **ignored**. |
| `_G.NavLib.facade` | **New** | Live getter via metatable. Primary access method. |
| `_G.NavLib.Navigation/Movement/Obstacle` | Works | Raw module classes still exposed. |
| `_G.NavLib.JSON`, `_G.NavLib.Helpers` | Works | Utility modules still exposed. |
| `_G.NavLib.create_ui(facade)` | Works | Now a no-op. Returns UIWindow handle. NavLib creates its own UI. |
| `facade:update()` by consumer | Harmless | Movement rate-limits internally via `_tick_interval`. |
| `facade:update_config()` by consumer | Overwritten | NavLib's `sync_to_facade()` overwrites on next render frame. |

## API Reference

See [API.md](API.md) for the complete reference covering:
- **Facade** — Recommended entry point. Move, events, state queries — all in one.
- **Navigation** — 11 NavBuddy endpoints, pathfinding options, callbacks
- **Movement** — Path following, routes, stuck recovery, state machine
- **Obstacle** — Doodad collision detection, avoidance zones, ray probing
