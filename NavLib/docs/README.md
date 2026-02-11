# NavLib

Standalone Sylvannas plugin providing navmesh pathfinding and path-following movement via the [NavBuddy](../../NavBuddy/) server.

## Requirements

- **NavBuddy server** running at `http://localhost:47110` (Rust HTTP server with Recast/Detour navmesh)
- **Sylvannas** with plugin loader (NavLib registers as a plugin via `header.lua` + `main.lua`)

## Plugin Structure

```
NavLib/
├── header.lua            Plugin metadata
├── main.lua              Entry point — registers _G.NavLib global
├── NavLibFacade.lua      Single entry-point facade (create + update + events)
├── NavigationClient.lua  HTTP client for NavBuddy (13 endpoints)
├── MovementModule.lua    Path following, stuck recovery, route planning
├── ObstacleModule.lua    Doodad collision detection and avoidance zones
├── JSON.lua              JSON encoder/decoder
├── Helpers.lua           Utility functions
└── docs/
    ├── README.md                 This file
    ├── NavLibFacade.md           NavLibFacade API reference (recommended)
    ├── NavigationClient.md       NavigationClient API reference
    ├── MovementModule.md         MovementModule API reference
    └── ObstacleModule.md         ObstacleModule API reference
```

## Accessing NavLib

NavLib registers itself as `_G.NavLib` when loaded. All modules are available:

```lua
if _G.NavLib then
    local NavigationClient = _G.NavLib.NavigationClient
    local MovementModule   = _G.NavLib.MovementModule
    local JSON             = _G.NavLib.JSON
    local Helpers          = _G.NavLib.Helpers
end
```

## Quick Start (Facade)

The recommended way to use NavLib — one call to create, one call per frame:

```lua
-- Create a fully-wired NavLib instance
local nav = _G.NavLib.create({
    movement = { smoothing = "chaikin", waypoint_tolerance = 3.0 },
})

-- Move to a position
nav:move_to(destination, function(ok, reason)
    if ok then core.log("Arrived!") end
end)

-- Listen for events (optional)
nav:on("arrived", function() core.log("Got there!") end)
nav:on("failed", function() core.log_error("Movement failed") end)

-- Call every frame
core.register_on_update_callback(function()
    nav:update()
end)

-- Update config at runtime (e.g., from UI settings)
nav:update_config({
    movement = { anti_detection = true, max_deviation = 5.0 },
    obstacles = { avoidance_radius = 4.0 },
})

-- Access raw modules when needed (escape hatch)
local raw_nav_client = nav.nav_client
raw_nav_client:raycast(start, dest, function(ok, data) ... end)
```

For advanced usage or direct module access, see the manual setup below.

## Manual Setup (Advanced)

### 1. Create a NavigationClient

```lua
local nav = _G.NavLib.NavigationClient:new({
    base_url = "http://localhost:47110",  -- default
    max_retries = 3,                      -- default
})
```

### 2. Find a Path

```lua
local player = core.object_manager.get_local_player()
local start = player:get_position()
local dest = { x = -8900, y = 560, z = 94 }

nav:find_path(start, dest, function(ok, data, err)
    if ok then
        -- data.waypoints: vec3[] array of path positions
        -- data.distance:  total path distance in yards
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

### 3. Move Along a Path

```lua
local movement = _G.NavLib.MovementModule:new(nav, {
    waypoint_tolerance = 3.0,
    stuck_check_interval = 2.0,
    smoothing = "chaikin",
})

-- Move to a position (async pathfinding + movement)
movement:move_to(dest, function(success, reason)
    if success then
        core.log("Arrived!")
    else
        core.log_error("Movement failed: " .. tostring(reason))
    end
end)

-- IMPORTANT: Call every frame to drive movement
core.register_on_update_callback(function()
    movement:update()
end)
```

### 4. Plan a Multi-Node Route (TSP)

```lua
local herb_nodes = {
    { x = -9100, y = 400, z = 93 },
    { x = -9200, y = 500, z = 91 },
    { x = -8900, y = 600, z = 95 },
    { x = -9000, y = 350, z = 90 },
}

movement:plan_route(herb_nodes, function(success, data)
    if success then
        if data.type == "leg_complete" then
            core.log(string.format("Leg %d/%d complete", data.leg, data.total))
        elseif data.type == "route_complete" then
            core.log("Route finished!")
        end
    else
        core.log_error("Route failed: " .. tostring(data.error))
    end
end, {
    return_to_start = true,
})
```

### 5. Pre-Validate a Destination

```lua
movement:validate_destination_reachable(dest, function(reachable, reason, distance)
    if reachable then
        core.log(string.format("Reachable (%.0f yards)", distance))
        movement:move_to(dest)
    else
        core.log_error("Unreachable: " .. tostring(reason))
    end
end)
```

## Architecture

NavLib provides four layers that can be used independently:

| Layer | Module | Purpose |
|-------|--------|---------|
| **Facade** | `NavLibFacade` | Single entry-point. Creates, wires, and drives all modules. Events. |
| **High-level** | `MovementModule` | Wraps NavigationClient. Handles path following, stuck recovery, route planning. |
| **Detection** | `ObstacleModule` | Doodad collision detection via ray probing. Avoidance zone memory. |
| **Low-level** | `NavigationClient` | Raw HTTP calls to NavBuddy. Returns paths, raycasts, heights. No movement. |

Use **NavLibFacade** (via `_G.NavLib.create()`) for the simplest integration — it handles module wiring, update ordering, and config distribution.

Use **MovementModule** directly when you need full control over module lifecycle.

Use **NavigationClient** directly when you need raw pathfinding data (e.g., checking if a path exists, raycasting for line-of-sight, getting navmesh height).

## API Reference

- [NavLibFacade API](NavLibFacade.md) - **Recommended entry point.** Create, move, events, config — all in one.
- [NavigationClient API](NavigationClient.md) - 14 endpoints, config, options, callbacks
- [MovementModule API](MovementModule.md) - Movement, routes, stuck recovery, state machine
- [ObstacleModule API](ObstacleModule.md) - Doodad collision detection, avoidance zones, ray probing
