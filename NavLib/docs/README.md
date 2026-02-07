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
├── NavigationClient.lua  HTTP client for NavBuddy (13 endpoints)
├── MovementModule.lua    Path following, stuck recovery, route planning
├── JSON.lua              JSON encoder/decoder
├── Helpers.lua           Utility functions
└── docs/
    ├── README.md                 This file
    ├── NavigationClient.md       NavigationClient API reference
    └── MovementModule.md         MovementModule API reference
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

## Quick Start

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

## Two-Layer Architecture

NavLib provides two layers that can be used independently:

| Layer | Module | Purpose |
|-------|--------|---------|
| **Low-level** | `NavigationClient` | Raw HTTP calls to NavBuddy. Returns paths, raycasts, heights. No movement. |
| **High-level** | `MovementModule` | Wraps NavigationClient. Handles path following, stuck recovery, route planning. |

Use **NavigationClient** directly when you need raw pathfinding data (e.g., checking if a path exists, raycasting for line-of-sight, getting navmesh height).

Use **MovementModule** when you want full move-to-destination behavior with automatic stuck recovery, path validation, and route planning.

## API Reference

- [NavigationClient API](NavigationClient.md) - 13 endpoints, config, options, callbacks
- [MovementModule API](MovementModule.md) - Movement, routes, stuck recovery, state machine
