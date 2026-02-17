# SentinelNavClient API Reference

Complete API reference for SentinelNavClient — covers the consumer-facing Client, the Navigation HTTP client, the Movement path follower, and the Obstacle detection system.

**For consumers:** Start with [Client](#client) — it wraps everything and is the recommended API.
**For internals/advanced use:** See [Navigation](#navigation), [Movement](#movement), and [Obstacle](#obstacle) for the underlying module APIs.

---

## Table of Contents

- [Client](#client)
  - [Accessing the Client](#accessing-the-client)
  - [Update Loop](#update-loop)
  - [Movement Commands](#movement-commands)
  - [State Queries](#state-queries)
  - [Server Queries](#server-queries)
  - [Opts Builders](#opts-builders)
  - [Configuration](#client-configuration)
  - [Events](#events)
  - [Escape Hatch](#escape-hatch)
  - [Complete Consumer Example](#complete-consumer-example)
- [Navigation](#navigation)
  - [Constructor](#navigation-constructor)
  - [Pathfinding](#pathfinding)
  - [Spatial Queries](#spatial-queries)
  - [Tactical](#tactical)
  - [Status](#navigation-status)
  - [Navigation Configuration](#navigation-configuration)
  - [Constants](#constants)
  - [Error Handling](#error-handling)
- [Movement](#movement)
  - [Constructor](#movement-constructor)
  - [Movement Control](#movement-control)
  - [Route Planning](#route-planning)
  - [Validation](#validation)
  - [State & Progress](#state--progress)
  - [Obstacle Integration](#obstacle-integration)
  - [Movement Configuration](#movement-configuration)
  - [State Machine](#state-machine)
  - [Stuck Recovery](#stuck-recovery)
  - [Indoor Corridor Adaptation](#indoor-corridor-adaptation)
  - [Proactive Obstacle Detection](#proactive-obstacle-detection)
  - [Casting Deferral](#casting-deferral)
  - [Path Validation](#path-validation)
- [Obstacle](#obstacle)
  - [Constructor](#obstacle-constructor)
  - [Probing](#probing)
  - [Zone Management](#zone-management)
  - [Obstacle Configuration](#obstacle-configuration)
  - [Obstacle Update Loop](#obstacle-update-loop)
  - [Integration with Movement](#integration-with-movement)
  - [How Ray Probing Works](#how-ray-probing-works)

---

# Client

Single entry-point client for SentinelNavClient. Wires and drives all modules, with a built-in event system for state-change notifications.

**This is the recommended way to use SentinelNavClient.** SentinelNavClient creates and owns a single shared Client instance. Consumers access it via `_G.SentinelNavClient.client`. For advanced use cases requiring direct module access, see the [escape hatch](#escape-hatch) section or the individual module sections below.

---

## Accessing the Client

SentinelNavClient creates a single shared Client at initialization. All consumers share this instance. There are three ways to access it:

### `_G.SentinelNavClient.client` (Recommended)

Live getter via metatable `__index`. Returns the shared Client, or `nil` if SentinelNavClient hasn't initialized yet.

```lua
local client = _G.SentinelNavClient.client
if client then
    client:move_to(target, callback)
end
```

### `_G.SentinelNavClient.create(config?)` (Backward Compatible)

Returns the same shared Client. The `config` parameter is accepted but **ignored** — SentinelNavClient's UI owns all settings.

```lua
local client = _G.SentinelNavClient.create()
```

### `Client:new(config)` (Internal Only)

Called by `SentinelNavClient/init.lua` during plugin initialization. **Consumers should NOT call this directly** — it would create an isolated Client disconnected from SentinelNavClient's update loop and settings sync.

### Consumer Example

```lua
-- In your plugin's initialize():
if _G.SentinelNavClient and _G.SentinelNavClient.client then
    local client = _G.SentinelNavClient.client

    client:move_to(destination, function(ok, reason)
        if ok then core.log("Arrived!") end
    end)
end
```

---

## Update Loop

### update

```lua
client:update()
```

Drives all internal modules in the correct order:

1. `obstacle:update()` — compatibility hook (probing is timer-driven)
2. `movement:update()` — advances waypoints, stuck detection, obstacle scanning, path validation
3. Detects state transitions and fires [events](#events)

> **Note:** SentinelNavClient calls `client:update()` from its own `on_update` callback every frame. **Consumers do NOT need to call this.** If a consumer calls it anyway, it is harmless — Movement rate-limits internally via `_tick_interval`.

---

## Movement Commands

All movement methods delegate to the internal [Movement](#movement) module. See that section for detailed behavior (casting deferral, corridor adaptation, stuck recovery, etc.).

### move_to

```lua
client:move_to(target, callback?, opts?)
```

Move to a target position using navmesh pathfinding.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `target` | vec3 | yes | Destination `{x, y, z}` |
| `callback` | function | no | `function(success, reason)` |
| `opts` | table | no | `{ use_navmesh = true, map_id = auto }` |

```lua
client:move_to(destination, function(ok, reason)
    if ok then
        core.log("Arrived!")
    else
        core.log_error("Failed: " .. tostring(reason))
    end
end)
```

---

### move_direct

```lua
client:move_direct(target, callback?)
```

Move directly without pathfinding. Equivalent to `move_to(target, callback, { use_navmesh = false })`.

---

### follow_path

```lua
client:follow_path(waypoints, callback?)
```

Follow a pre-computed waypoint array without requesting a new path from SentinelNavServer. Useful when you already have waypoints (e.g., from a direct `nav_client:find_path()` call or cached path).

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `waypoints` | vec3[] | yes | Array of positions to follow |
| `callback` | function | no | `function(success, reason)` |

```lua
-- Get a path manually, then follow it
client.nav_client:find_path(start, dest, function(ok, data)
    if ok then
        client:follow_path(data.waypoints, function(success, reason)
            if success then core.log("Arrived!") end
        end)
    end
end, client:get_path_opts())
```

---

### plan_route

```lua
client:plan_route(nodes, callback?, opts?)
```

Plan and execute a TSP-optimized route through multiple nodes.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `nodes` | vec3[] | yes | At least 2 positions to visit |
| `callback` | function | no | Route progress callback |
| `opts` | table | no | `{ map_id = auto, return_to_start = false }` |

**Callback:** Called multiple times:
```lua
function(success, data)
    if success then
        if data.type == "leg_complete" then
            -- data.leg, data.total
        elseif data.type == "route_complete" then
            -- All nodes visited
        end
    else
        -- data.error: error message
    end
end
```

---

### replan

```lua
client:replan(reason?)
```

Replan the active route from the current leg. Requires an active route from `plan_route()`.

---

### validate_destination

```lua
client:validate_destination(target, callback)
```

Check if a destination is reachable **without starting movement**.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `target` | vec3 | yes | Target position |
| `callback` | function | yes | `function(reachable, reason, distance)` |

---

### stop

```lua
client:stop()
```

Stop all movement and reset to idle. Clears active path, destination, callbacks, stuck counters, and route data.

---

### destroy

```lua
client:destroy()
```

Stop movement, clear all obstacle zones, and remove event listeners. Call when permanently done with the SentinelNavClient instance.

---

## State Queries

### get_state

```lua
client:get_state() -> string
```

Returns the current movement state:

| State | Description |
|-------|-------------|
| `"idle"` | Not moving |
| `"requesting_path"` | Waiting for path from SentinelNavServer |
| `"moving"` | Actively following waypoints |
| `"stuck"` | Stuck recovery in progress |
| `"arrived"` | Reached destination |
| `"failed"` | Movement failed |

---

### is_moving

```lua
client:is_moving() -> boolean
```

Returns `true` if state is `"moving"` or `"requesting_path"`.

---

### get_destination

```lua
client:get_destination() -> vec3|nil
```

Returns the current destination, or `nil` if not moving.

---

### get_current_path

```lua
client:get_current_path() -> vec3[]|nil
```

Returns the current waypoint array, or `nil` if no active path.

---

### get_path_index

```lua
client:get_path_index() -> number
```

Returns the current waypoint index in the active path. Returns `1` if no path is active.

---

### get_progress

```lua
client:get_progress() -> table
```

Detailed progress snapshot:

```lua
{
    state = string,              -- Current state
    destination = vec3|nil,      -- Target position
    distance_remaining = number, -- Yards to destination (moving only)
    path_index = number,         -- Current waypoint index (moving only)
    path_count = number,         -- Total waypoints (moving only)
    current_leg = number,        -- Current route leg (route mode only)
    total_legs = number,         -- Total route legs (route mode only)
    route_mode = boolean,        -- true if executing a route
}
```

---

### get_corridor_widths

```lua
client:get_corridor_widths() -> number[]|nil
```

Returns corridor width data for the current indoor path, or `nil` if outdoors or no data.

---

## Server Queries

### is_server_available

```lua
client:is_server_available() -> boolean
```

Returns `true` if SentinelNavServer server appears connected (has had a recent successful request, fewer than 3 consecutive failures).

---

### health_check

```lua
client:health_check(callback)
```

Check SentinelNavServer server health.

```lua
function(ok, data, err)
    -- data.status, data.version, data.uptime_secs, data.loaded_maps
end
```

---

### get_height

```lua
client:get_height(pos, callback)
```

Get the navmesh Z-coordinate at arbitrary world coordinates.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `pos` | vec3 | yes | World position `{x, y, z}` to query |
| `callback` | function | yes | `function(ok, data, err)` — `data.height` on success |

---

### get_player_height

```lua
client:get_player_height(callback)
```

Convenience wrapper — gets the navmesh Z-coordinate at the local player's current position.

---

## Opts Builders

### get_path_opts

```lua
client:get_path_opts(extra?) -> table
```

Build a path options table from the current Movement config. Merges all configured smoothing, filter, and wall clearance values into a table suitable for passing to Navigation methods. Optionally merge extra key-value overrides on top.

```lua
local opts = client:get_path_opts({ allow_partial = true })
client.nav_client:find_path(start, dest, callback, opts)
```

---

### get_corridor_opts

```lua
client:get_corridor_opts(extra?) -> table
```

Same as `get_path_opts` but also includes `probe_distance` from the corridor config. Use with `find_path_corridor`.

> **Avoidance zones with direct `nav_client` calls:** When using the escape hatch to call `nav_client` methods directly (e.g., `find_path_corridor`, `find_route_multi`), you must pass `avoid_zones` explicitly in the opts table. `client:move_to()` handles this automatically, but direct calls do not.
>
> ```lua
> local zones = client.obstacle:get_avoidance_zones()
> local opts = client:get_path_opts({ avoid_zones = zones })
> client.nav_client:find_route_multi(stops, callback, opts)
> ```

---

## Client Configuration

### How Settings Work

SentinelNavClient owns all navigation settings via its built-in UI. The settings flow is:

1. ~40 menu elements in `SentinelNavClient/ui/window.lua` (persisted across sessions via `core.menu.*`)
2. `sync_to_client()` reads all elements every render frame
3. Calls `client:update_config()` with the resolved values
4. Movement and Obstacle modules update their internal config

**Consumers should NOT call `update_config()` directly** — their changes will be overwritten on the next render frame by SentinelNavClient's sync.

To change navigation settings, use the SentinelNavClient Settings UI (toggled via the "SentinelNavClient" button in the Sylvannas menu).

### Constructor Config (Internal)

The Client constructor accepts sectioned config, but this is only used internally by `SentinelNavClient/init.lua`:

| Section | Module | Description |
|---------|--------|-------------|
| `navigation` | Navigation | `base_url`, `max_retries` |
| `movement` | Movement | All movement/pathfinding settings (see [Movement Configuration](#movement-configuration)) |
| `obstacles` | Obstacle | All obstacle settings (see [Obstacle Configuration](#obstacle-configuration)) |

---

### update_config (Internal)

```lua
client:update_config(overrides)
```

Distribute config updates to underlying modules at runtime. Only provided keys are changed.

> **Internal:** This is called by SentinelNavClient's `sync_to_client()` every render frame. Consumer calls will be overwritten. Use SentinelNavClient's Settings UI instead.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `overrides` | table | yes | `{ movement = {...}, obstacles = {...} }` |

> **Note:** `navigation` config (base_url, max_retries) cannot be updated at runtime — it is set once during construction.

---

## Events

The client fires events when the movement state changes. Use `on()` to subscribe and `off()` to unsubscribe.

### on

```lua
client:on(event, callback)
```

Register a listener for an event. Multiple listeners can be registered for the same event. Listeners are called in registration order.

### off

```lua
client:off(event, callback)
```

Remove a previously registered listener. Pass the **same function reference** used in `on()`.

### Event Types

| Event | Fired when | Callback data |
|-------|-----------|---------------|
| `"state_change"` | Any state transition | `{ from = string, to = string }` |
| `"arrived"` | Reached destination | `nil` |
| `"stuck"` | Stuck detected | `nil` |
| `"failed"` | Movement failed | `nil` |

```lua
client:on("state_change", function(data)
    core.log(string.format("SentinelNavClient: %s -> %s", data.from, data.to))
end)

client:on("arrived", function()
    core.log("Destination reached!")
end)

client:on("failed", function()
    core.log_error("Movement failed — check path or obstacles")
end)
```

**Error handling:** Event callbacks are wrapped in `pcall`. If a handler throws, it is caught and logged but does not affect other handlers or SentinelNavClient operation.

---

## Escape Hatch

For advanced use cases, the underlying module instances are exposed as public fields:

| Field | Type | Description |
|-------|------|-------------|
| `client.nav_client` | Navigation | Raw HTTP client — direct access to all 11 endpoints |
| `client.movement` | Movement | Path follower — full state machine, stuck recovery |
| `client.obstacle` | Obstacle | Obstacle detector — zone memory, ray probing |

```lua
local client = _G.SentinelNavClient.client

-- Use the client for common operations
client:move_to(target, callback)

-- Drop to raw client for specialized queries
client.nav_client:raycast(start, dest, function(ok, data)
    if ok and not data.hit then
        core.log("Clear line of sight!")
    end
end)

-- Access obstacle zones directly
local zones = client.obstacle:get_avoidance_zones()

-- Read movement internals
local widths = client.movement:get_corridor_widths()
```

> **Note:** The client and its modules share the same instances. Calling `movement:stop()` on the escape hatch has the same effect as `client:stop()`.

---

## Complete Consumer Example

```lua
-- Example: Using SentinelNavClient from a consumer plugin (e.g., a gathering bot)

-- 1. Get the shared Client (in your plugin's initialize)
if not (_G.SentinelNavClient and _G.SentinelNavClient.client) then
    core.log_error("SentinelNavClient not loaded — navigation unavailable")
    return
end

local client = _G.SentinelNavClient.client

-- 2. Register event listeners (optional)
client:on("arrived", function()
    core.log("Arrived at destination!")
end)

client:on("failed", function()
    core.log_error("Movement failed")
end)

client:on("state_change", function(data)
    core.log("[Nav] " .. data.from .. " -> " .. data.to)
end)

-- 3. Check server health
client:health_check(function(ok, data)
    if ok then
        core.log("SentinelNavServer v" .. data.version .. " (" .. data.uptime_secs .. "s uptime)")
    else
        core.log_error("SentinelNavServer server not reachable")
    end
end)

-- 4. Validate and move to a destination
local dest = { x = -8900, y = 560, z = 94 }

client:validate_destination(dest, function(reachable, reason, distance)
    if reachable then
        core.log(string.format("Target reachable, %.0f yards", distance))
        client:move_to(dest)
    else
        core.log_error("Unreachable: " .. tostring(reason))
    end
end)

-- 5. Plan a multi-node route
local herb_spots = {
    { x = -9100, y = 400, z = 93 },
    { x = -9200, y = 500, z = 91 },
    { x = -8900, y = 600, z = 95 },
}

client:plan_route(herb_spots, function(ok, data)
    if ok and data.type == "route_complete" then
        core.log("Route finished!")
    end
end, { return_to_start = true })

-- 6. Use raw modules when needed (escape hatch)
client.nav_client:raycast(start, dest, function(ok, data)
    if ok and not data.hit then
        core.log("Clear line of sight!")
    end
end)

-- 7. Stop when needed
-- client:stop()

-- Note: No update() call needed (SentinelNavClient drives it)
-- Note: No update_config() needed (SentinelNavClient UI syncs settings)
-- Note: No destroy() needed (SentinelNavClient manages Client lifecycle)
```

---
---

# Navigation

HTTP client for the SentinelNavServer pathfinding server. Provides async pathfinding, raycasting, height queries, and tactical movement endpoints.

All pathfinding methods are **asynchronous** — they issue an HTTP GET to SentinelNavServer and invoke a callback with the result. Failed requests retry with exponential backoff.

> **Note:** Consumers should access the shared Navigation client via `_G.SentinelNavClient.client.nav_client` rather than creating a new instance. The shared client is already configured by SentinelNavClient.

---

## Navigation Constructor

### `Navigation:new(config) -> Navigation`

Create a new client instance.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `config.base_url` | string | `"http://78.31.71.163:47110"` | SentinelNavServer server URL |
| `config.max_retries` | number | `3` | Max retry attempts per request |

```lua
local nav = Navigation:new({
    base_url = "http://78.31.71.163:47110",
    max_retries = 3,
})
```

**Instance fields initialized:**
- `_is_connected` = false
- `_consecutive_failures` = 0
- `_last_success_time` = 0

---

## Pathfinding

### find_path

```lua
nav:find_path(start_pos, dest, callback, opts?)
```

Request a navmesh path between two points.

**Endpoint:** `GET /api/v1/path` (or `/api/v1/path-random` if `anti_detection = true`)

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `start_pos` | vec3 | yes | Start position `{x, y, z}` |
| `dest` | vec3 | yes | Destination position `{x, y, z}` |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | Path options (see below) |

**Options (opts):**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `map_id` | number | auto | Continent ID (0=EK, 1=Kalimdor, 530=Outland, 571=Northrend) |
| `smoothing` | string | — | Algorithm: `"none"`, `"chaikin"`, `"catmull_rom"`, `"bezier"` |
| `optimize` | boolean | — | Enable waypoint optimization |
| `anti_detection` | boolean | — | Use randomized path endpoint |
| `max_deviation` | number | — | Max yards waypoints can deviate during optimization |
| `smooth_iterations` | number | — | Number of smoothing passes |
| `smooth_samples` | number | — | Sample count per smooth pass |
| `smooth_ratio` | number | — | Smoothing interpolation ratio (0.0-1.0) |
| `allow_partial` | boolean | — | Return partial path if full path impossible |
| `z_extent` | number | — | Z-axis search extent for start/end snapping |
| `filter_ground` | number | — | Ground polygon cost filter |
| `filter_water` | number | — | Water polygon cost filter |
| `filter_lava` | number | — | Lava polygon cost filter |
| `wall_clearance` | number | — | Min distance from walls (must be > 0 to take effect) |
| `min_corner_angle` | number | — | Min angle at corners in degrees |
| `keep_originals` | boolean | — | Keep original waypoints alongside smoothed |

**Callback data (on success):**
```lua
{
    waypoints = vec3[],          -- Path positions
    distance = number,           -- Total distance in yards
    partial = boolean,           -- true if path is incomplete
    computation_time_ms = number -- Server computation time
}
```

```lua
nav:find_path(player_pos, target, function(ok, data, err)
    if ok then
        core.log(string.format("Path: %d waypoints, %.0f yards",
            #data.waypoints, data.distance))
    else
        core.log_error("Pathfinding failed: " .. tostring(err))
    end
end, {
    smoothing = "chaikin",
    optimize = true,
    allow_partial = true,
})
```

---

### find_path_corridor

```lua
nav:find_path_corridor(start_pos, dest, callback, opts?)
```

Request a path with corridor width measurements at each waypoint. Useful for indoor navigation where knowing passage width helps avoid walls.

**Endpoint:** `GET /api/v1/path/corridor`

**Parameters:** Same as [find_path](#find_path) plus:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `opts.probe_distance` | number | — | Distance to probe for corridor width measurement |
| `opts.avoid_zones` | table[] | — | Avoidance zones (see [find_path_avoid](#find_path_avoid)) |

**Callback data (on success):**
```lua
{
    waypoints = vec3[],          -- Path positions
    corridor_widths = number[],  -- Width in yards at each waypoint
    distance = number,           -- Total distance
    partial = boolean,           -- true if incomplete
    computation_time_ms = number -- Server time
}
```

---

### find_path_avoid

```lua
nav:find_path_avoid(start_pos, dest, avoid_zones, callback, opts?)
```

Request a navmesh path that routes around avoidance zones. Used by Movement when Obstacle has detected doodad collisions. Falls back to `find_path()` if no zones are provided or if the avoid endpoint fails.

**Endpoint:** `GET /api/v1/path-avoid`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `start_pos` | vec3 | yes | Start position |
| `dest` | vec3 | yes | Destination position |
| `avoid_zones` | table[] | yes | Avoidance zones to route around |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | Same options as [find_path](#find_path) |

**Avoidance zone format:**
```lua
{
    x = number,      -- Zone center X
    y = number,      -- Zone center Y
    z = number,      -- Zone center Z
    radius = number, -- Avoidance radius in yards
    cost = number,   -- Cost multiplier (higher = more strongly avoided)
}
```

Zones are sent to SentinelNavServer as a semicolon-separated `avoid` query parameter: `x,y,z,radius,cost;x,y,z,radius,cost;...`

**Fallback behavior:**
- If `avoid_zones` is empty or nil, delegates to `find_path()` directly
- If the `/path-avoid` endpoint returns an error, automatically falls back to `find_path()` without avoidance and logs a warning

---

### find_route_tsp

```lua
nav:find_route_tsp(nodes, callback, opts?)
```

Plan a TSP-optimized (Traveling Salesman Problem) route through multiple nodes. SentinelNavServer computes the optimal visit order to minimize total travel distance.

**Endpoint:** `GET /api/v1/path-tsp`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `nodes` | vec3[] | yes | At least 2 positions to visit |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | Route options |

**Options:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `map_id` | number | auto | Continent ID |
| `start_pos` | vec3 | player pos | Starting position (auto-detected if omitted) |
| `return_to_start` | boolean | — | Add a final leg returning to start |
| `weights` | table | — | Custom importance weights per node |
| `avoid_zones` | table[] | — | Avoidance zones |

**Callback data (on success):**
```lua
{
    waypoints = vec3[],        -- Flattened waypoints for all legs
    visit_order = number[],    -- 1-indexed order of node visits
    leg_boundaries = number[], -- Waypoint indices marking leg transitions
    leg_distances = number[],  -- Distance of each leg
    total_distance = number,   -- Total route distance
}
```

> **Note:** `visit_order` is automatically converted from SentinelNavServer's 0-indexed format to Lua's 1-indexed format.

---

### find_route_multi

```lua
nav:find_route_multi(stops, callback, opts?)
```

Plan an ordered multi-stop route. Unlike TSP, stops are visited in the exact order provided.

**Endpoint:** `GET /api/v1/path-multi`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `stops` | vec3[] | yes | At least 2 ordered stop positions |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | Same options as [find_path](#find_path) plus `avoid_zones` |

**Callback data (on success):**
```lua
{
    waypoints = vec3[],        -- Flattened waypoints
    leg_boundaries = number[], -- Leg transition indices
    leg_distances = number[],  -- Per-leg distances
    total_distance = number,   -- Total distance
}
```

---

### check_path

```lua
nav:check_path(current_pos, waypoints, callback, opts?)
```

Validate that remaining waypoints are still walkable on the navmesh. Use periodically to detect path invalidation without requesting a full repath.

**Endpoint:** `GET /api/v1/path/check`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `current_pos` | vec3 | yes | Player's current position |
| `waypoints` | vec3[] | yes | Remaining waypoints to validate |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | `{ map_id = auto, max_check = number }` |

**Callback data (on success):**
```lua
{
    valid = boolean,                    -- Entire path is walkable
    first_invalid_segment = number|nil, -- Index of first bad segment
    player_on_navmesh = boolean,        -- Player position is on navmesh
}
```

---

## Spatial Queries

### raycast

```lua
nav:raycast(start_pos, dest, callback, opts?)
```

Cast a ray between two navmesh points to check for obstacles.

**Endpoint:** `GET /api/v1/raycast`

**Callback data (on success):**
```lua
{
    hit = boolean,             -- true if ray hit an obstacle
    hit_position = vec3|nil,   -- Where the ray hit
    t = number,                -- 0-1 parameter along ray
    normal = vec3,             -- Surface normal at hit point
}
```

```lua
nav:raycast(player_pos, target_pos, function(ok, data, err)
    if ok then
        if data.hit then
            core.log(string.format("Obstacle at %.0f%% of path", data.t * 100))
        else
            core.log("Clear line of sight")
        end
    end
end)
```

---

### get_height

```lua
nav:get_height(pos, callback, opts?)
```

Get the navmesh Z-coordinate at a position.

**Endpoint:** `GET /api/v1/height`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `pos` | vec3 | yes | World position `{x, y, z}` to query |
| `callback` | function | yes | `function(ok, data, err)` — `data.height` on success |
| `opts` | table | no | `{ map_id = auto }` |

---

### random_point

```lua
nav:random_point(callback, opts?)
```

Get a random valid point on the navmesh.

**Endpoint:** `GET /api/v1/random`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `map_id` | number | auto | Continent ID |
| `center` | vec3 | — | Center of search area (requires `radius`) |
| `radius` | number | — | Search radius in yards (requires `center`) |

> Both `center` and `radius` must be provided together. If either is missing, a random point from the entire map is returned.

**Callback data:** `{ point = vec3 }`

---

## Tactical

### flee

```lua
nav:flee(player_pos, threats, callback, opts?)
```

Calculate an escape path away from one or more threats.

**Endpoint:** `GET /api/v1/tactical/flee`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `player_pos` | vec3 | yes | Current position |
| `threats` | vec3[] | yes | Array of threat positions (at least 1) |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | `{ map_id, flee_distance, smoothing, smooth_*, filter_*, wall_clearance, avoid_zones }` |

**Callback data (on success):**
```lua
{
    waypoints = vec3[],          -- Flee path
    distance = number,           -- Total path distance in yards
    min_threat_distance = number,-- Min distance from threats at flee endpoint
}
```

```lua
nav:flee(player_pos, enemies, function(ok, data, err)
    if ok then
        core.log(string.format("Flee path: %d waypoints, %.0f yards from threats",
            #data.waypoints, data.min_threat_distance))
    end
end, {
    flee_distance = 40,
    smoothing = "chaikin",
})
```

---

### kite

```lua
nav:kite(player_pos, target_pos, callback, opts?)
```

Calculate a circular path around a target for kiting.

**Endpoint:** `GET /api/v1/tactical/kite`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `map_id` | number | auto | Continent ID |
| `kite_radius` | number | — | Desired distance from target |
| `arc_degrees` | number | — | Arc segment angle in degrees |
| `direction` | string | — | `"cw"` (clockwise) or `"ccw"` (counter-clockwise) |
| `smoothing` | string | — | Algorithm: `"none"`, `"chaikin"`, `"catmull_rom"`, `"bezier"` |
| `smooth_*` | number | — | Smoothing params (iterations, samples, ratio) |
| `filter_*` | number | — | Terrain cost filters (ground, water, lava) |
| `wall_clearance` | number | — | Min distance from walls |

> **Note:** Kite does not support `z_extent` — arc waypoints are snapped to the navmesh directly, not via A* pathfinding.

**Callback data (on success):**
```lua
{
    waypoints = vec3[],      -- Kite path positions
    waypoint_count = number, -- Number of arc waypoints
}
```

---

## Navigation Status

### health_check

```lua
nav:health_check(callback)
```

**Endpoint:** `GET /health`

```lua
{
    status = string,       -- "ok", "degraded", etc.
    version = string,      -- SentinelNavServer version
    uptime_secs = number,  -- Server uptime
    loaded_maps = table,   -- Map/continent status
}
```

### is_available

```lua
nav:is_available() -> boolean
```

Returns `true` after a successful request, `false` after 3+ consecutive failures.

### get_consecutive_failures

```lua
nav:get_consecutive_failures() -> number
```

Number of consecutive failed requests. Resets to 0 on any successful request.

### reset

```lua
nav:reset()
```

Reset connection state. Call when switching maps or after extended disconnections.

### is_indoor

```lua
Navigation.is_indoor() -> boolean
```

**Static method** (no instance needed). Returns `true` if the current UiMapID is a dungeon or raid zone.

---

## Navigation Configuration

### Constructor Config

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `base_url` | string | `"http://78.31.71.163:47110"` | SentinelNavServer server URL |
| `max_retries` | number | `3` | Max retry attempts with exponential backoff |

### Map ID Auto-Detection

If `opts.map_id` is not provided, Navigation automatically detects the current continent by:
1. Calling `core.get_map_id()` to get the current UiMapID
2. Looking up the UiMapID in `UI_MAP_TO_CONTINENT`
3. Defaulting to `0` (Eastern Kingdoms) if the UiMapID is unmapped

---

## Constants

### UI_MAP_TO_CONTINENT

Table mapping WoW UiMapIDs to SentinelNavServer continent IDs:

| Continent ID | Continent | Example UiMapIDs |
|-------------|-----------|------------------|
| `0` | Eastern Kingdoms | 37, 42, 47, 56, 84, 87, 94, 122, 124, ... |
| `1` | Kalimdor | 57, 62, 63, 64, 65, 69, 70, 76, 77, 80, ... |
| `530` | Outland | 100, 104, 105, 107, 108, 109, 111, ... |
| `571` | Northrend | 113, 114, 115, 116, 117, 118, 119, 120, 121, 123, 125, 127, ... |

### INDOOR_UI_MAPS

Boolean set of UiMapIDs for dungeon and raid zones. Used by `is_indoor()` and corridor pathfinding decisions. Contains all WotLK dungeons, raids, and indoor instances.

---

## Error Handling

### Retry Behavior

Failed HTTP requests retry with exponential backoff:
- Attempt 1: immediate
- Attempt 2: 0.5s delay
- Attempt 3: 1.0s delay
- Attempt 4: 2.0s delay (if max_retries > 3)

Retryable HTTP status codes: `0`, `500`, `502`, `503`, `504`

### Connection Tracking

- After a successful request: `_is_connected = true`, `_consecutive_failures = 0`
- After all retries exhausted: `_consecutive_failures` incremented
- After 3+ consecutive failures: `_is_connected = false`

### Callback Error Patterns

All callbacks follow the same signature:
```lua
function(success, data, error)
    -- success: boolean
    -- data:    table on success, nil on failure
    -- error:   string on failure, nil on success
end
```

Common error strings:
- `"Missing start or dest"` — nil position parameters
- `"Empty path"` — server returned no waypoints
- `"Need at least 2 nodes"` — insufficient nodes for TSP/multi
- `"HTTP error: <status>"` — server returned non-200 after retries
- `"JSON parse error: <details>"` — malformed response
- `"Server error: <message>"` — server returned `success: false`

### Callback Safety

All callbacks are wrapped in `pcall`. If your callback throws an error, it is caught and logged but does not crash SentinelNavClient.

---
---

# Movement

High-level path-following module that wraps [Navigation](#navigation). Handles waypoint traversal, stuck detection and recovery, route planning, indoor corridor adaptation, obstacle avoidance, and casting deferral.

> **Note:** Consumers should access the shared Movement module via `_G.SentinelNavClient.client.movement`. The shared instance is created and configured by SentinelNavClient. `movement:update()` is called by SentinelNavClient's `on_update` callback every frame — consumers do not need to call it. `update_config()` is called by SentinelNavClient's UI sync system every render frame — consumer calls would be overwritten.

---

## Movement Constructor

### `Movement:new(nav_client, config) -> Movement`

Create a new movement module instance.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `nav_client` | Navigation | yes | Navigation instance for pathfinding |
| `config` | table | no | Configuration overrides (see [Movement Configuration](#movement-configuration)) |

```lua
local nav = _G.SentinelNavClient.Navigation:new()
local movement = _G.SentinelNavClient.Movement:new(nav, {
    waypoint_tolerance = 3.0,
    smoothing = "chaikin",
    optimize = true,
})
```

---

## Movement Control

### move_to

```lua
movement:move_to(target, callback?, opts?)
```

Move to a target position using navmesh pathfinding. Requests a path from Navigation, then follows it with stuck recovery.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `target` | vec3 | yes | Destination `{x, y, z}` |
| `callback` | function | no | `function(success, reason)` |
| `opts` | table | no | `{ use_navmesh = true, map_id = auto }` |

**Behavior:**
1. If player is casting/channeling, defers until cast ends
2. If `use_navmesh = false`, moves directly without pathfinding
3. Otherwise requests path from SentinelNavServer (corridor path if indoors, normal path outdoors)
4. If an Obstacle is attached and has avoidance zones, uses `find_path_avoid()` instead of `find_path()`
5. On path received, starts following waypoints
6. Adjusts waypoint tolerance for narrow indoor corridors (40% of min corridor width, minimum 1.0)

---

### move_direct

```lua
movement:move_direct(target, callback?)
```

Move directly to a target without pathfinding. Equivalent to `move_to(target, callback, { use_navmesh = false })`.

---

### stop

```lua
movement:stop()
```

Stop all movement and reset to idle state. Clears active path, destination, pending callbacks, stuck counters, route data, and corridor widths. Resets waypoint tolerance to config defaults.

---

### follow_path

```lua
movement:follow_path(waypoints, callback?)
```

Follow a pre-computed waypoint array without requesting a new path from SentinelNavServer. Sets state to `"moving"` and begins waypoint traversal with stuck detection.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `waypoints` | vec3[] | yes | Array of positions to follow |
| `callback` | function | no | `function(success, reason)` |

---

## Route Planning

### plan_route

```lua
movement:plan_route(nodes, callback?, opts?)
```

Plan and execute a TSP-optimized route through multiple nodes. SentinelNavServer calculates the optimal visit order, then Movement follows each leg sequentially.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `nodes` | vec3[] | yes | At least 2 positions to visit |
| `callback` | function | no | Route progress callback |
| `opts` | table | no | `{ map_id = auto, return_to_start = false }` |

**Callback:** Called multiple times:
```lua
function(success, data)
    if success then
        if data.type == "leg_complete" then
            -- data.leg, data.total
        elseif data.type == "route_complete" then
            -- All nodes visited
        end
    else
        -- data.error: error message
    end
end
```

---

### replan

```lua
movement:replan(reason?)
```

Replan the active route starting from the current leg. Requires an active route. Collects remaining unvisited nodes, stops current movement, and calls `plan_route` with remaining nodes. Fails if fewer than 2 nodes remain.

---

## Validation

### validate_destination_reachable

```lua
movement:validate_destination_reachable(target, callback)
```

Check if a destination is reachable via navmesh **without starting movement**.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `target` | vec3 | yes | Target position |
| `callback` | function | yes | `function(reachable, reason, distance)` |

---

## State & Progress

### update

```lua
movement:update()
```

**Must be called every frame.** Drives the movement state machine: advances waypoints, checks for arrival, runs stuck detection, processes recovery actions, validates paths, scans for obstacles, and tracks route progress.

> **Note:** SentinelNavClient calls this automatically from its `on_update` callback. Consumers do not need to call it.

---

### get_state

```lua
movement:get_state() -> string
```

Returns the current state: `"idle"`, `"requesting_path"`, `"moving"`, `"stuck"`, `"arrived"`, or `"failed"`.

### is_moving

```lua
movement:is_moving() -> boolean
```

Returns `true` if state is `"moving"` or `"requesting_path"`.

### get_current_path

```lua
movement:get_current_path() -> vec3[]|nil
```

### get_destination

```lua
movement:get_destination() -> vec3|nil
```

### get_path_index

```lua
movement:get_path_index() -> number
```

### get_progress

```lua
movement:get_progress() -> table
```

```lua
{
    state = string,
    destination = vec3|nil,
    distance_remaining = number,
    path_index = number,
    path_count = number,
    current_leg = number,     -- route mode only
    total_legs = number,      -- route mode only
    route_mode = boolean,
}
```

### get_corridor_widths

```lua
movement:get_corridor_widths() -> number[]|nil
```

Returns corridor width data for the current path (indoor corridor paths only), or `nil`.

---

## Obstacle Integration

### set_obstacle_module

```lua
movement:set_obstacle_module(obstacle_module)
```

Attach an Obstacle instance for avoidance-aware pathfinding. When set:

- Proactive obstacle scanning runs every `proactive_obstacle_interval` seconds during movement
- Detected obstacle zones are passed to `find_path_avoid()` for rerouting
- Reactive probing triggers on the 2nd stuck recovery attempt

> **Note:** When using the Client, this is called automatically during construction. You only need to call this if you're wiring modules manually.

---

## Movement Configuration

### Constructor Config

All config fields with their defaults:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `dynamic_speed` | boolean | `true` | Scale look-ahead, tolerance, turn speed based on player movement speed |
| `waypoint_tolerance` | number | `3.0` | Yards to reach a waypoint before advancing |
| `final_tolerance` | number | `1.5` | Yards to reach final destination |
| `stuck_check_interval` | number | `2.0` | Seconds between stuck checks |
| `stuck_distance_min` | number | `1.0` | Min yards moved to not be "stuck" |
| `max_stuck_attempts` | number | `5` | Max recovery attempts before failing |
| `path_check_interval` | number | `8.0` | Seconds between path validity checks |
| `smoothing` | string | `"chaikin"` | Path smoothing algorithm (`"none"`, `"chaikin"`, `"catmull_rom"`, `"bezier"`) |
| `optimize` | boolean | `true` | Enable waypoint optimization |
| `anti_detection` | boolean | `false` | Use randomized path endpoint |
| `max_deviation` | number | `3.0` | Max yards for anti-detection deviation |
| `allow_partial` | boolean | `true` | Accept partial paths |
| `smooth_iterations` | number | `3` | Smoothing iterations |
| `smooth_samples` | number | `10` | Smoothing sample count |
| `smooth_ratio` | number | `0.50` | Smoothing interpolation ratio (0.0-1.0) |
| `min_corner_angle` | number | `90` | Min corner angle in degrees |
| `keep_originals` | boolean | `false` | Keep original waypoints alongside smoothed |
| `filter_ground` | number | `1.0` | Ground polygon cost |
| `filter_water` | number | `10.0` | Water polygon cost |
| `filter_lava` | number | `100.0` | Lava polygon cost |
| `use_corridor_indoor` | boolean | `true` | Use corridor pathfinding indoors |
| `corridor_probe_dist` | number | `15.0` | Corridor probe distance in yards |
| `wall_clearance` | number | `1.0` | Min distance from walls in yards (must be > 0 to take effect) |
| `proactive_obstacle_check` | boolean | `true` | Enable proactive obstacle scanning on upcoming path segments |
| `proactive_obstacle_interval` | number | `1.5` | Seconds between proactive obstacle scans |

---

### update_config

```lua
movement:update_config(overrides)
```

Update configuration at runtime. Only provided keys are changed; others keep their current values.

> **Note:** This is called by SentinelNavClient's UI sync system every render frame. Consumer calls would be overwritten. Use SentinelNavClient's Settings UI to change movement settings.

---

## State Machine

```
                    move_to() / plan_route()
     [IDLE] ─────────────────────────────> [REQUESTING_PATH]
       ^                                         │
       │                                    path received
       │                                         │
       │                                         v
       │                                    [MOVING]
       │                                     │     │
       │         arrival                     │     │ stuck detected
       │         ┌───────────────────────────┘     │
       │         v                                 v
       │    [ARRIVED]                          [STUCK]
       │         │                               │ recovery action
       │         │ auto-reset                    v
       │<────────┘                          [MOVING] (retry)
       │
       │         max stuck attempts
       │<────── [FAILED]

     Any state ──stop()──> [IDLE]
```

**Transitions:**
- `idle` -> `requesting_path`: `move_to()` or `plan_route()` called
- `requesting_path` -> `moving`: Path received from SentinelNavServer
- `requesting_path` -> `failed`: Path request failed
- `moving` -> `arrived`: Reached destination
- `arrived` -> `idle`: Automatic reset after callback fires
- `moving` -> `stuck`: Stuck detected (not enough movement)
- `stuck` -> `moving`: Recovery action taken
- `moving` -> `failed`: Max stuck attempts exceeded
- Any -> `idle`: `stop()` called

---

## Stuck Recovery

When the player hasn't moved far enough during a check interval, stuck recovery escalates through these strategies:

| Stuck Count | Strategy | Action | Duration |
|-------------|----------|--------|----------|
| 1 | Jump | `core.input.jump()` | Instant |
| 2 | Strafe + Jump | Random left/right strafe, also probes for obstacles if Obstacle attached | 0.5s then jump |
| 3 | Backward + Jump | Move backward | 1.0s then jump |
| 4+ | Repath | Request fresh path from current position | Async |
| max (5) | Fail | Movement fails, callback called with error | — |

**Stuck detection:**
- Checked every `stuck_check_interval` seconds (default: 2.0s)
- Compares distance moved since last check against `stuck_distance_min` (default: 1.0 yards)
- **Skipped** while player is casting or channeling
- Counter resets to 0 when sufficient movement detected

**Repath behavior:**
- Stops current path
- Requests new path from current position to original destination
- Uses corridor pathfinding if indoors
- Includes avoidance zones if Obstacle has detected obstacles
- Resets stuck counter on successful repath

---

## Indoor Corridor Adaptation

When `use_corridor_indoor = true` and the player is in a dungeon/raid zone:

1. `move_to()` uses `find_path_corridor` instead of `find_path`
2. Corridor width data is stored and accessible via `get_corridor_widths()`
3. Waypoint tolerance is automatically reduced for narrow passages:
   - Set to 40% of the minimum corridor width
   - Minimum of 1.0 yards
   - Prevents overshooting in tight corridors

**Detection:** Uses `Navigation.is_indoor()` which checks the current UiMapID against a built-in table of dungeon/raid zones.

---

## Proactive Obstacle Detection

When an Obstacle is attached via `set_obstacle_module()` and `proactive_obstacle_check = true`:

1. Every `proactive_obstacle_interval` seconds (default: 1.5s) during movement, scans upcoming waypoint segments for doodad collisions
2. Uses `Obstacle:probe_path_ahead()` with `core.graphics.trace_line` to check for blocked segments
3. If an obstacle is detected: adds an avoidance zone to the Obstacle, then triggers a repath via `find_path_avoid()` to route around it
4. **Reactive fallback:** On the 2nd stuck recovery attempt, probes forward from the player's position. If an obstacle is found, adds a zone and repaths immediately

This is fully automatic when using the Client — the Client wires the Obstacle into Movement during construction.

---

## Casting Deferral

If the player is casting or channeling a spell when `move_to()` is called:

1. Movement request is stored as pending
2. On each `update()`, checks if cast/channel ended
3. When cast ends, automatically retries the `move_to()` call
4. Original callback and options are preserved

This prevents interrupting spell casts with movement commands.

---

## Path Validation

During movement, paths are periodically validated:

- Checked every `path_check_interval` seconds (default: 8.0s)
- Only validates if 3+ waypoints remain
- Uses `Navigation:check_path()` to verify navmesh walkability
- If invalid segment detected: triggers repath from current position
- Logs the invalid segment index for debugging

---
---

# Obstacle

Doodad collision detection via `core.graphics.trace_line` ray probing, with avoidance zone memory. Detected obstacles are stored as zones and fed to [Navigation:find_path_avoid()](#find_path_avoid) for rerouting.

> **Note:** Consumers should access the shared Obstacle module via `_G.SentinelNavClient.client.obstacle`. The shared instance is created and configured by SentinelNavClient. `update_config()` is called by SentinelNavClient's UI sync system every render frame — consumer calls would be overwritten.

Obstacle has two probing modes, both driven by [Movement](#movement):

- **Proactive:** Scans upcoming waypoint segments on a timer during movement (default every 1.5s)
- **Reactive:** Probes forward from the player's position when stuck recovery triggers (2nd attempt)

---

## Obstacle Constructor

### `Obstacle:new(config?) -> Obstacle`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `config` | table | no | Configuration overrides (see [Obstacle Configuration](#obstacle-configuration)) |

```lua
local obstacle = _G.SentinelNavClient.Obstacle:new({
    avoidance_radius = 4.0,
    max_zones = 8,
})
```

---

## Probing

### probe_forward

```lua
obstacle:probe_forward(player_pos, target_pos) -> vec3|nil
```

Probe forward from the player toward a target using `core.graphics.trace_line`. Casts 3 rays (center + left/right at `probe_spread_deg`) to detect doodad collisions.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `player_pos` | vec3 | yes | Current player position |
| `target_pos` | vec3 | yes | Direction to probe toward (typically the next waypoint) |

**Returns:** Approximate hit position `{x, y, z}` if any ray hits an obstacle, or `nil` if clear.

**Behavior:**
1. Computes a 2D heading from player to target (Z ignored for direction)
2. Raises the ray origin by `probe_height_offset` yards above ground to avoid false hits
3. Casts 3 rays of length `probe_distance`: center, left (-spread), right (+spread)
4. If any ray is blocked, returns the midpoint along that ray as the approximate obstacle center

**Used by:** Movement's reactive stuck handler (2nd stuck attempt)

---

### probe_segment

```lua
obstacle:probe_segment(pos_a, pos_b) -> table|nil
```

Probe along a single waypoint segment A->B for doodad collisions. Casts a center ray plus two spread rays at `+/-lookahead_spread_deg`.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `pos_a` | vec3 | yes | Start of segment |
| `pos_b` | vec3 | yes | End of segment |

**Returns:** Approximate obstacle center `{x, y, z}` (midpoint of segment) if any ray is blocked, or `nil` if clear.

---

### probe_path_ahead

```lua
obstacle:probe_path_ahead(waypoints, max_segments?) -> hit_pos, segment_index
```

Probe upcoming waypoint segments for obstacles. Iterates through the first N segments and returns the first collision found.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `waypoints` | vec3[] | yes | Remaining waypoints (at least 2) |
| `max_segments` | number | no | Max segments to check (default: `lookahead_segments` config) |

**Returns:**

| Return | Type | Description |
|--------|------|-------------|
| `hit_pos` | table\|nil | First obstacle found `{x, y, z}`, or nil if clear |
| `segment_index` | number\|nil | 1-based index of the segment with the hit |

**Used by:** Movement's proactive obstacle check (every 1.5s during movement)

---

## Zone Management

### add_zone

```lua
obstacle:add_zone(pos, radius?)
```

Add an avoidance zone at the given position. Zones are remembered and passed to SentinelNavServer's `/path-avoid` endpoint for rerouting.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `pos` | table | yes | Hit position `{x, y, z}` from a probe |
| `radius` | number | no | Override avoidance radius (default: `avoidance_radius` config) |

**Behavior:**
- **Deduplication:** Won't add a zone if one already exists within `avoidance_radius` of the position
- **Cap enforcement:** If adding exceeds `max_zones`, evicts the oldest zone first (FIFO)
- Stores the zone with: position, radius, cost multiplier (`avoidance_cost`), and creation timestamp

---

### remove_zone

```lua
obstacle:remove_zone(index)
```

Remove a specific avoidance zone by its 1-based index.

---

### prune

```lua
obstacle:prune(player_pos?)
```

Remove expired or distant zones. Should be called periodically (e.g., on repath).

**Removal criteria (either triggers removal):**
- Zone age exceeds `zone_ttl` seconds (default: 120s)
- Zone is farther than `zone_prune_dist` yards from `player_pos` (default: 100 yards)

---

### clear

```lua
obstacle:clear()
```

Remove all remembered avoidance zones immediately.

---

### get_avoidance_zones

```lua
obstacle:get_avoidance_zones() -> table[]
```

Returns the current avoidance zones for passing to `find_path_avoid()`.

```lua
{
    x = number,       -- Zone center X
    y = number,       -- Zone center Y
    z = number,       -- Zone center Z
    radius = number,  -- Avoidance radius in yards
    cost = number,    -- Cost multiplier
    created = number, -- Timestamp (core.time())
}
```

---

### get_zone_count

```lua
obstacle:get_zone_count() -> number
```

Returns the number of active avoidance zones.

---

## Obstacle Configuration

### Constructor Config

All config fields with their defaults:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `avoidance_cost` | number | `5.0` | Cost multiplier for avoidance zones (higher = more strongly avoided) |
| `avoidance_radius` | number | `5.0` | Radius in yards around each detected obstacle |
| `zone_ttl` | number | `120.0` | Seconds before zones auto-expire |
| `zone_prune_dist` | number | `100.0` | Yards — remove zones farther than this from player |
| `max_zones` | number | `5` | Maximum remembered zones (SentinelNavServer supports up to 20) |
| `collision_flags` | number | `0x00000001` | Trace line flags (`DoodadCollision`) |
| `probe_distance` | number | `8.0` | Reactive probe distance in yards (from player position) |
| `probe_spread_deg` | number | `20` | Reactive probe spread angle in degrees |
| `probe_height_offset` | number | `1.0` | Yards to raise reactive probe origin above ground |
| `lookahead_height_offset` | number | `1.5` | Yards to raise proactive look-ahead rays above waypoint Z |
| `lookahead_spread_deg` | number | `15` | Proactive look-ahead spread angle in degrees |
| `lookahead_segments` | number | `3` | Default number of upcoming segments to scan |

---

### update_config

```lua
obstacle:update_config(overrides)
```

Update configuration at runtime. Only provided keys are changed.

> **Note:** This is called by SentinelNavClient's UI sync system every render frame. Consumer calls would be overwritten. Use SentinelNavClient's Settings UI to change obstacle settings.

---

## Obstacle Update Loop

```lua
obstacle:update()
```

No-op method for compatibility with module update loops. Probing is not driven by `update()` — it is triggered by Movement:

- **Proactive probing** is called by `Movement:_check_proactive_obstacles()` on a timer
- **Reactive probing** is called by `Movement:_unstuck_probe_and_repath()` during stuck recovery

When using the Client, `obstacle:update()` is called automatically by `client:update()`.

---

## Integration with Movement

Obstacle is designed to work with Movement. The wiring is:

```lua
-- Manual wiring
local obstacle = Obstacle:new()
movement:set_obstacle_module(obstacle)

-- Or automatic via Client
local client = _G.SentinelNavClient.client  -- wires everything internally
```

Once wired:

1. **Proactive scanning** (every 1.5s during movement):
   - Movement calls `obstacle:probe_path_ahead(remaining_waypoints)`
   - If hit found: calls `obstacle:add_zone(hit_pos)`, then repaths with `find_path_avoid()`

2. **Reactive scanning** (on 2nd stuck attempt):
   - Movement calls `obstacle:probe_forward(player_pos, next_waypoint)`
   - If hit found: calls `obstacle:add_zone(hit_pos)`, then repaths with `find_path_avoid()`

3. **Zone data flows to pathfinding:**
   - `obstacle:get_avoidance_zones()` returns zones for `Navigation:find_path_avoid()`
   - SentinelNavServer computes paths that avoid the zones with the specified cost multiplier

---

## How Ray Probing Works

Both probing methods use `core.graphics.trace_line(origin, target, flags)`:

- Returns `true` if the ray is **clear** (no collision)
- Returns `false` if the ray is **blocked** (doodad hit)

**Reactive probing** (`probe_forward`):
```
        [Left Ray]
       /
Player ──── [Center Ray] ────> (probe_distance yards)
       \
        [Right Ray]

Spread: +/-probe_spread_deg (default: 20 deg)
Height: origin raised by probe_height_offset (default: 1.0 yd)
```

**Proactive probing** (`probe_segment`):
```
        [Left Ray]
       /
  WP_A ──── [Center Ray] ────> WP_B
       \
        [Right Ray]

Spread: +/-lookahead_spread_deg (default: 15 deg)
Height: both endpoints raised by lookahead_height_offset (default: 1.5 yd)
```

The narrower spread on proactive rays (15 deg vs 20 deg) reduces false positives on straight segments while still catching obstacles slightly off the direct path.
