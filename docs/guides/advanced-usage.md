---
title: Advanced Usage
layout: default
parent: Guides
nav_order: 2
---

# Advanced Usage
{: .no_toc }

Escape hatches, direct module access, manual setup, and advanced patterns.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## Escape Hatch

The Client exposes its underlying module instances as public fields for advanced use cases:

| Field | Type | Description |
|:------|:-----|:------------|
| `client.nav_client` | [Navigation](/api/navigation) | Raw HTTP client &mdash; direct access to all 14 endpoints |
| `client.movement` | [Movement](/api/movement) | Path follower &mdash; full state machine, stuck recovery |
| `client.obstacle` | [Obstacle](/api/obstacle) | Obstacle detector &mdash; zone memory, ray probing |

```lua
local client = _G.SentinelNavClient.client

-- Standard: use Client for movement
client:move_to(target, callback)

-- Advanced: raycast for line-of-sight checks
client.nav_client:raycast(start, dest, function(ok, data)
    if ok and not data.hit then
        core.log("Clear line of sight!")
    end
end)

-- Advanced: read corridor widths
local widths = client.movement:get_corridor_widths()

-- Advanced: manually manage obstacle zones
client.obstacle:add_zone(pos, 5.0)
local zones = client.obstacle:get_avoidance_zones()
```

{: .note }
The Client and its modules share the same instances. Calling `movement:stop()` on the escape hatch has the same effect as `client:stop()`.

---

## Direct Navigation Queries

Use `nav_client` directly for queries that don't involve movement:

### Raycast (Line of Sight)

```lua
client.nav_client:raycast(player_pos, target_pos, function(ok, data, err)
    if ok then
        if data.hit then
            core.log(string.format("Blocked at %.0f%% of path", data.t * 100))
            core.log(string.format("Hit at: %.1f, %.1f, %.1f",
                data.hit_position.x, data.hit_position.y, data.hit_position.z))
        else
            core.log("Clear line of sight")
        end
    end
end)
```

### Height Query

```lua
-- Single height
client.nav_client:get_height(pos, function(ok, data, err)
    if ok then
        core.log(string.format("Navmesh Z: %.2f", data.height))
    end
end)

-- Multi-level heights (bridges, buildings, caves)
client.nav_client:get_all_heights(pos, function(ok, data, err)
    if ok then
        for _, h in ipairs(data.heights) do
            core.log(string.format("Level: %.2f", h))
        end
    end
end, {
    filter_unreachable = true,
    from_pos = player_pos,
})
```

### Random Point

```lua
-- Random point anywhere on the map
client.nav_client:random_point(function(ok, data)
    if ok then
        core.log(string.format("Random: %.1f, %.1f, %.1f",
            data.point.x, data.point.y, data.point.z))
    end
end)

-- Random point within 50 yards
client.nav_client:random_point(function(ok, data)
    if ok then
        client:move_to(data.point)
    end
end, {
    center = player_pos,
    radius = 50,
})
```

### Tactical: Flee

```lua
local enemies = { enemy1_pos, enemy2_pos }

client.nav_client:flee(player_pos, enemies, function(ok, data)
    if ok then
        client:follow_path(data.waypoints, function(arrived)
            if arrived then core.log("Escaped!") end
        end)
    end
end, {
    flee_distance = 40,
    smoothing = "chaikin",
})
```

### Tactical: Kite

```lua
client.nav_client:kite(player_pos, target_pos, function(ok, data)
    if ok then
        client:follow_path(data.waypoints)
    end
end, {
    kite_radius = 15,
    arc_degrees = 90,
    direction = "cw",
})
```

---

## Avoidance Zones with Direct Calls

{: .warning }
When using the escape hatch to call `nav_client` methods directly, you must pass `avoid_zones` explicitly. `client:move_to()` handles this automatically, but direct calls do **not**.

```lua
-- Get current avoidance zones
local zones = client.obstacle:get_avoidance_zones()

-- Pass them to pathfinding
local opts = client:get_path_opts({ avoid_zones = zones })

-- Direct corridor path with avoidance
client.nav_client:find_path_corridor(start, dest, function(ok, data)
    if ok then
        client:follow_path(data.waypoints)
    end
end, client:get_corridor_opts({ avoid_zones = zones }))

-- Direct multi-stop route with avoidance
client.nav_client:find_route_multi(stops, function(ok, data)
    if ok then
        -- Process waypoints and leg_boundaries...
    end
end, client:get_path_opts({ avoid_zones = zones }))
```

---

## Manual Obstacle Zone Management

Add custom avoidance zones based on your plugin's knowledge:

```lua
local obstacle = client.obstacle

-- Add a zone at a known obstacle position
obstacle:add_zone({ x = -8900, y = 560, z = 94 }, 5.0)

-- Remove expired/distant zones
obstacle:prune(player_pos)

-- Clear all zones
obstacle:clear()

-- Read current zones
local zones = obstacle:get_avoidance_zones()
for i, zone in ipairs(zones) do
    core.log(string.format("Zone %d: (%.0f, %.0f, %.0f) r=%.1f cost=%.1f age=%.0fs",
        i, zone.x, zone.y, zone.z, zone.radius, zone.cost,
        core.time() - zone.created))
end
```

---

## Using Opts Builders

The Client provides `get_path_opts()` and `get_corridor_opts()` to build server query options from the current Movement config:

```lua
-- Basic path opts (inherits all movement config)
local opts = client:get_path_opts()

-- Merge extra overrides
local opts = client:get_path_opts({
    allow_partial = true,
    z_extent = 10,
})

-- Corridor opts (path opts + probe_distance)
local opts = client:get_corridor_opts()

-- Use with direct Navigation calls
client.nav_client:find_path(start, dest, callback, opts)
client.nav_client:find_path_corridor(start, dest, callback, client:get_corridor_opts())
```

This ensures your direct calls use the same smoothing, filtering, wall clearance, and other settings that `client:move_to()` would use.

---

## Pre-Computing and Caching Paths

For scenarios where you want to pre-compute paths without immediately following them:

```lua
-- Pre-compute a path
client.nav_client:find_path(start, dest, function(ok, data)
    if ok then
        -- Cache the path
        self._cached_path = data.waypoints
        self._cached_distance = data.distance

        -- Follow later when ready
        -- client:follow_path(self._cached_path, callback)
    end
end, client:get_path_opts())
```

---

## Path Validation Without Movement

Check if a path is still valid without starting movement:

```lua
-- Validate a cached path
client.nav_client:check_path(player_pos, cached_waypoints, function(ok, data)
    if ok then
        if data.valid then
            core.log("Path is still walkable")
        else
            core.log(string.format("Invalid at segment %d", data.first_invalid_segment))
        end

        if not data.player_on_navmesh then
            core.log_warning("Player is off the navmesh!")
        end
    end
end)
```

---

## Manual Module Setup

{: .warning }
This bypasses the shared Client and creates isolated module instances. Use for **standalone scripts or testing only** &mdash; not recommended for plugins running alongside SentinelNavClient.

### Create Navigation Client

```lua
local Navigation = _G.SentinelNavClient.Navigation

local nav = Navigation:new({
    base_url = "http://localhost:47110",
    max_retries = 3,
})
```

### Create Movement + Follow Path

```lua
local Movement = _G.SentinelNavClient.Movement

local movement = Movement:new(nav, {
    waypoint_tolerance = 3.0,
    smoothing = true,
    optimize = true,
})

movement:move_to(dest, function(success, reason)
    if success then core.log("Arrived!") end
end)

-- You MUST call update() yourself when using manual setup
core.register_on_update_callback(function()
    movement:update()
end)
```

### Add Obstacle Detection

```lua
local Obstacle = _G.SentinelNavClient.Obstacle

local obstacle = Obstacle:new({
    avoidance_radius = 3.0,
    max_zones = 5,
})

-- Wire obstacle into movement
movement:set_obstacle_module(obstacle)

-- Update both in your loop
core.register_on_update_callback(function()
    obstacle:update()   -- no-op but good practice
    movement:update()   -- drives everything
end)
```

---

## Utility Modules

SentinelNavClient exposes utility modules for convenience:

### JSON

```lua
local JSON = _G.SentinelNavClient.JSON

local str = JSON.encode({ x = 1, y = 2, z = 3 })
local tbl = JSON.decode('{"x":1,"y":2,"z":3}')
```

### Helpers

```lua
local Helpers = _G.SentinelNavClient.Helpers

-- Distance calculations
local d = Helpers.distance_3d(pos_a, pos_b)
local d2 = Helpers.distance_2d(pos_a, pos_b)

-- Point-to-segment distance (used by deviation monitoring)
local dist, t = Helpers.point_to_segment_distance(
    px, py, pz,   -- point
    ax, ay, az,   -- segment start
    bx, by, bz    -- segment end
)

-- Table utilities
local copy = Helpers.deep_copy(original)
local merged = Helpers.table_merge(base, overrides)
local found = Helpers.table_contains(list, value)

-- Math
local val = Helpers.clamp(min, max, value)
local mid = Helpers.lerp(a, b, t)
local pos = Helpers.lerp_vec3(v1, v2, t)

-- Formatting
local time_str = Helpers.format_time(3661)   -- "1h 1m 1s"
local num_str = Helpers.format_number(12345)  -- "12,345"

-- Randomization
local val = Helpers.gaussian_random(min, max)      -- Box-Muller
local val = Helpers.add_variance(base, percent)    -- gaussian ±%

-- Angles
local angle = Helpers.angle_to(pos_a, pos_b)
local norm = Helpers.normalize_angle(radians)
```

See [Helpers Reference](/reference/helpers) for the complete function list.
