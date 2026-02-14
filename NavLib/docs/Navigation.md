# Navigation API Reference

HTTP client for the NavBuddy pathfinding server. Provides async pathfinding, raycasting, height queries, and tactical movement endpoints.

All pathfinding methods are **asynchronous** -- they issue an HTTP GET to NavBuddy and invoke a callback with the result. Failed requests retry with exponential backoff.

## Table of Contents

- [Constructor](#constructor)
- [Pathfinding](#pathfinding)
  - [find_path](#find_path)
  - [find_path_corridor](#find_path_corridor)
  - [find_path_avoid](#find_path_avoid)
  - [find_route_tsp](#find_route_tsp)
  - [find_route_multi](#find_route_multi)
  - [check_path](#check_path)
- [Spatial Queries](#spatial-queries)
  - [raycast](#raycast)
  - [get_height](#get_height)
  - [random_point](#random_point)
- [Tactical](#tactical)
  - [flee](#flee)
  - [kite](#kite)
- [Status](#status)
  - [health_check](#health_check)
  - [is_available](#is_available)
  - [get_consecutive_failures](#get_consecutive_failures)
  - [reset](#reset)
  - [is_indoor](#is_indoor)
- [Configuration](#configuration)
- [Constants](#constants)
- [Error Handling](#error-handling)

---

## Constructor

### `Navigation:new(config) -> Navigation`

Create a new client instance.

**Parameters:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `config.base_url` | string | `"http://localhost:47110"` | NavBuddy server URL |
| `config.max_retries` | number | `3` | Max retry attempts per request |

**Example:**
```lua
local nav = Navigation:new({
    base_url = "http://localhost:47110",
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

**Parameters:**

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
| `smoothing` | string | — | Algorithm: `"none"`, `"straight"`, `"catmull_rom"`, `"chaikin"` |
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

**Example:**
```lua
nav:find_path(player_pos, target, function(ok, data, err)
    if ok then
        core.log(string.format("Path: %d waypoints, %.0f yards",
            #data.waypoints, data.distance))
        if data.partial then
            core.log("Warning: partial path returned")
        end
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

**Example:**
```lua
nav:find_path_corridor(start, dest, function(ok, data, err)
    if ok then
        for i, wp in ipairs(data.waypoints) do
            core.log(string.format("WP %d: width=%.1f yards", i, data.corridor_widths[i]))
        end
    end
end, {
    probe_distance = 15.0,
    smoothing = "chaikin",
})
```

---

### find_path_avoid

```lua
nav:find_path_avoid(start_pos, dest, avoid_zones, callback, opts?)
```

Request a navmesh path that routes around avoidance zones. Used by [Movement](Movement.md) when an [Obstacle](Obstacle.md) has detected doodad collisions. Falls back to `find_path()` if no zones are provided or if the avoid endpoint fails.

**Endpoint:** `GET /api/v1/path-avoid`

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `start_pos` | vec3 | yes | Start position `{x, y, z}` |
| `dest` | vec3 | yes | Destination position `{x, y, z}` |
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

Zones are sent to NavBuddy as a pipe-separated `avoid` query parameter: `x,y,z,radius,cost|x,y,z,radius,cost|...`

**Callback data (on success):** Same as [find_path](#find_path).

**Fallback behavior:**
- If `avoid_zones` is empty or nil, delegates to `find_path()` directly
- If the `/path-avoid` endpoint returns an error, automatically falls back to `find_path()` without avoidance and logs a warning

**Example:**
```lua
local zones = obstacle:get_avoidance_zones()
nav:find_path_avoid(player_pos, dest, zones, function(ok, data, err)
    if ok then
        -- data.waypoints routes around the obstacle zones
        core.log(string.format("Avoid path: %d waypoints, %.0f yards",
            #data.waypoints, data.distance))
    end
end, {
    smoothing = "chaikin",
    optimize = true,
})
```

---

### find_route_tsp

```lua
nav:find_route_tsp(nodes, callback, opts?)
```

Plan a TSP-optimized (Traveling Salesman Problem) route through multiple nodes. NavBuddy computes the optimal visit order to minimize total travel distance.

**Endpoint:** `GET /api/v1/path-tsp`

**Parameters:**

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

**Example:**
```lua
local nodes = {
    { x = -9100, y = 400, z = 93 },
    { x = -9200, y = 500, z = 91 },
    { x = -8900, y = 600, z = 95 },
}

nav:find_route_tsp(nodes, function(ok, data, err)
    if ok then
        core.log(string.format("Route: %d legs, %.0f total yards",
            #data.leg_distances, data.total_distance))
        core.log("Visit order: " .. table.concat(data.visit_order, " -> "))
    end
end, {
    return_to_start = true,
})
```

> **Note:** `visit_order` is automatically converted from NavBuddy's 0-indexed format to Lua's 1-indexed format.

---

### find_route_multi

```lua
nav:find_route_multi(stops, callback, opts?)
```

Plan an ordered multi-stop route. Unlike TSP, stops are visited in the exact order provided.

**Endpoint:** `GET /api/v1/path-multi`

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `stops` | vec3[] | yes | At least 2 ordered stop positions |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | `{ map_id = number }` |

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

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `current_pos` | vec3 | yes | Player's current position |
| `waypoints` | vec3[] | yes | Remaining waypoints to validate |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | Options |

**Options:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `map_id` | number | auto | Continent ID |
| `max_check` | number | — | Max waypoints to validate |

**Callback data (on success):**
```lua
{
    valid = boolean,                    -- Entire path is walkable
    first_invalid_segment = number|nil, -- Index of first bad segment
    player_on_navmesh = boolean,        -- Player position is on navmesh
}
```

**Example:**
```lua
nav:check_path(player_pos, remaining_waypoints, function(ok, data, err)
    if ok and not data.valid then
        core.log(string.format("Path invalid at segment %d, repathing",
            data.first_invalid_segment))
        -- Request new path
    end
end)
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

**Example:**
```lua
nav:raycast(player_pos, target_pos, function(ok, data, err)
    if ok then
        if data.hit then
            core.log(string.format("Obstacle at %.0f%% of path",
                data.t * 100))
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

Get the navmesh Z-coordinate at a position. Useful for ground-level verification, terrain probing, or checking if a position is on valid navmesh.

**Endpoint:** `GET /api/v1/height`

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `pos` | vec3 | yes | World position `{x, y, z}` to query |
| `callback` | function | yes | `function(ok, data, err)` |
| `opts` | table | no | `{ map_id = auto }` |

**Callback data (on success):**
```lua
{
    height = number,  -- Z-coordinate on navmesh
}
```

**Example:**
```lua
-- Query height at arbitrary coordinates
local pos = { x = -8900, y = 560, z = 100 }
nav:get_height(pos, function(ok, data, err)
    if ok then
        core.log(string.format("Navmesh height: %.2f", data.height))
    else
        core.log_error("Height query failed: " .. tostring(err))
    end
end)

-- Query height at player's position
local me = core.object_manager.get_local_player()
nav:get_height(me:get_position(), function(ok, data, err)
    if ok then
        core.log(string.format("Navmesh: %.2f | Player Z: %.2f",
            data.height, me:get_position().z))
    end
end)
```

---

### random_point

```lua
nav:random_point(callback, opts?)
```

Get a random valid point on the navmesh.

**Endpoint:** `GET /api/v1/random`

**Options:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `map_id` | number | auto | Continent ID |
| `center` | vec3 | — | Center of search area (requires `radius`) |
| `radius` | number | — | Search radius in yards (requires `center`) |

> Both `center` and `radius` must be provided together. If either is missing, a random point from the entire map is returned.

**Callback data (on success):**
```lua
{
    point = vec3,  -- Random navmesh position
}
```

---

## Tactical

### flee

```lua
nav:flee(player_pos, threats, callback, opts?)
```

Calculate an escape path away from one or more threats.

**Endpoint:** `GET /api/v1/tactical/flee`

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `player_pos` | vec3 | yes | Current position |
| `threats` | vec3[] | yes | Array of threat positions (at least 1) |
| `callback` | function | yes | `function(success, data, error)` |
| `opts.flee_distance` | number | — | Target distance from threats |

**Callback data (on success):**
```lua
{
    waypoints = vec3[],              -- Flee path
    flee_direction = string,         -- Direction fled
    distance_from_threats = number,  -- Distance achieved from closest threat
}
```

**Example:**
```lua
local enemies = {
    enemy1:get_position(),
    enemy2:get_position(),
}

nav:flee(player_pos, enemies, function(ok, data, err)
    if ok then
        -- Follow data.waypoints to escape
        core.log(string.format("Fleeing %s, %.0f yards from threats",
            data.flee_direction, data.distance_from_threats))
    end
end, {
    flee_distance = 40,
})
```

---

### kite

```lua
nav:kite(player_pos, target_pos, callback, opts?)
```

Calculate a circular path around a target for kiting.

**Endpoint:** `GET /api/v1/tactical/kite`

**Options:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `kite_radius` | number | — | Desired distance from target |
| `arc_degrees` | number | — | Arc segment angle in degrees |
| `direction` | string | — | `"cw"` (clockwise) or `"ccw"` (counter-clockwise) |

**Callback data (on success):**
```lua
{
    waypoints = vec3[],   -- Kite path positions
    arc_length = number,  -- Total arc distance
}
```

---

## Status

### health_check

```lua
nav:health_check(callback)
```

Check NavBuddy server health.

**Endpoint:** `GET /health`

**Callback data (on success):**
```lua
{
    status = string,       -- "ok", "degraded", etc.
    version = string,      -- NavBuddy version
    uptime_secs = number,  -- Server uptime
    loaded_maps = table,   -- Map/continent status
}
```

---

### is_available

```lua
nav:is_available() -> boolean
```

Check if the server appears connected. Returns `true` after a successful request, `false` after 3+ consecutive failures.

---

### get_consecutive_failures

```lua
nav:get_consecutive_failures() -> number
```

Number of consecutive failed requests. Resets to 0 on any successful request.

---

### reset

```lua
nav:reset()
```

Reset connection state (`_is_connected = false`, `_consecutive_failures = 0`, `_last_success_time = 0`). Call when switching maps or after extended disconnections.

---

### is_indoor

```lua
Navigation.is_indoor() -> boolean
```

**Static method** (no instance needed). Returns `true` if the current UiMapID is a dungeon or raid zone.

```lua
if Navigation.is_indoor() then
    -- Use corridor pathfinding for tighter navigation
end
```

---

## Configuration

### Constructor Config

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `base_url` | string | `"http://localhost:47110"` | NavBuddy server URL |
| `max_retries` | number | `3` | Max retry attempts with exponential backoff |

### Map ID Auto-Detection

If `opts.map_id` is not provided, Navigation automatically detects the current continent by:
1. Calling `core.get_map_id()` to get the current UiMapID
2. Looking up the UiMapID in `UI_MAP_TO_CONTINENT`
3. Defaulting to `0` (Eastern Kingdoms) if the UiMapID is unmapped

---

## Constants

### UI_MAP_TO_CONTINENT

Table mapping WoW UiMapIDs to NavBuddy continent IDs:

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
- `"Missing start or dest"` - nil position parameters
- `"Empty path"` - server returned no waypoints
- `"Need at least 2 nodes"` - insufficient nodes for TSP/multi
- `"HTTP error: <status>"` - server returned non-200 after retries
- `"JSON parse error: <details>"` - malformed response
- `"Server error: <message>"` - server returned `success: false`

### Callback Safety

All callbacks are wrapped in `pcall`. If your callback throws an error, it is caught and logged but does not crash NavLib.
