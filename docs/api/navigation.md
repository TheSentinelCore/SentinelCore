---
title: Navigation
layout: default
parent: API Reference
nav_order: 2
---

# Navigation API
{: .no_toc }

HTTP client for the SentinelNavServer pathfinding server. Provides async pathfinding, raycasting, height queries, and tactical movement endpoints.
{: .fs-6 .fw-300 }

All methods are **asynchronous** &mdash; they issue an HTTP GET to SentinelNavServer and invoke a callback with the result. Failed requests retry with exponential backoff.

{: .note }
Consumers should access the shared Navigation client via `_G.SentinelNavClient.client.nav_client` rather than creating a new instance. The shared client is already configured by SentinelNavClient.

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## Constructor

### `Navigation:new(config) -> Navigation`

Create a new Navigation client instance.

| Field | Type | Default | Description |
|:------|:-----|:--------|:------------|
| `config.base_url` | string | `"http://78.31.71.163:47110"` | SentinelNavServer server URL |
| `config.max_retries` | number | `3` | Max retry attempts per request |

```lua
local nav = Navigation:new({
    base_url = "http://78.31.71.163:47110",
    max_retries = 3,
})
```

**Instance fields initialized:**
- `_is_connected` = `false`
- `_consecutive_failures` = `0`
- `_last_success_time` = `0`

---

## Pathfinding

### find_path

```lua
nav:find_path(start_pos, dest, callback, opts?)
```

Request a navmesh path between two points.

**Endpoint:** `GET /api/v1/path` (or `GET /api/v1/path-random` if `anti_detection = true`)

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `start_pos` | vec3 | yes | Start position `{x, y, z}` |
| `dest` | vec3 | yes | Destination position `{x, y, z}` |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | Path options (see below) |

#### Path Options

All pathfinding methods accept these options:

| Field | Type | Default | Description |
|:------|:-----|:--------|:------------|
| `map_id` | number | auto | Continent ID (0=Eastern Kingdoms, 1=Kalimdor, 530=Outland, 571=Northrend) |
| `smoothing` | string | &mdash; | Algorithm: `"none"`, `"chaikin"`, `"catmull_rom"`, `"bezier"` |
| `optimize` | boolean | &mdash; | Enable waypoint optimization (reduce redundant waypoints) |
| `anti_detection` | boolean | &mdash; | Use randomized path endpoint |
| `max_deviation` | number | &mdash; | Max yards waypoints can deviate during optimization |
| `smooth_iterations` | number | &mdash; | Number of smoothing passes |
| `smooth_samples` | number | &mdash; | Sample count per smooth pass |
| `smooth_ratio` | number | &mdash; | Smoothing interpolation ratio (0.0&ndash;1.0) |
| `allow_partial` | boolean | &mdash; | Return partial path if full path is impossible |
| `z_extent` | number | &mdash; | Z-axis search extent for start/end snapping |
| `filter_ground` | number | &mdash; | Ground polygon cost filter |
| `filter_water` | number | &mdash; | Water polygon cost filter |
| `filter_lava` | number | &mdash; | Lava polygon cost filter |
| `wall_clearance` | number | &mdash; | Min distance from walls (must be > 0 to take effect) |
| `min_corner_angle` | number | &mdash; | Min angle at corners in degrees |
| `keep_originals` | boolean | &mdash; | Keep original waypoints alongside smoothed |

#### Callback Data (on success)

```lua
{
    waypoints = vec3[],          -- Path positions
    distance = number,           -- Total distance in yards
    partial = boolean,           -- true if path is incomplete
    computation_time_ms = number -- Server computation time
}
```

#### Example

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
|:------|:-----|:--------|:------------|
| `opts.probe_distance` | number | &mdash; | Distance to probe for corridor width measurement |
| `opts.avoid_zones` | table[] | &mdash; | Avoidance zones (see [find_path_avoid](#find_path_avoid)) |

#### Callback Data (on success)

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

Request a navmesh path that routes around avoidance zones. Used by Movement when Obstacle has detected doodad collisions.

**Endpoint:** `GET /api/v1/path-avoid`

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `start_pos` | vec3 | yes | Start position |
| `dest` | vec3 | yes | Destination position |
| `avoid_zones` | table[] | yes | Avoidance zones to route around |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | Same options as [find_path](#find_path) |

#### Avoidance Zone Format

```lua
{
    x = number,      -- Zone center X
    y = number,      -- Zone center Y
    z = number,      -- Zone center Z
    radius = number, -- Avoidance radius in yards
    cost = number,   -- Cost multiplier (higher = more strongly avoided)
}
```

Zones are sent to SentinelNavServer as a semicolon-separated `avoid` query parameter:
```
x,y,z,radius,cost;x,y,z,radius,cost;...
```

#### Fallback Behavior

- If `avoid_zones` is empty or nil &rarr; delegates to `find_path()` directly
- If `/path-avoid` endpoint returns an error &rarr; falls back to `find_path()` without avoidance and logs a warning

---

### find_route_tsp

```lua
nav:find_route_tsp(nodes, callback, opts?)
```

Plan a TSP-optimized (Traveling Salesman Problem) route through multiple nodes. SentinelNavServer computes the optimal visit order to minimize total travel distance.

**Endpoint:** `GET /api/v1/path-tsp`

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `nodes` | vec3[] | yes | At least 2 positions to visit |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | Route options (see below) |

#### Route Options

| Field | Type | Default | Description |
|:------|:-----|:--------|:------------|
| `map_id` | number | auto | Continent ID |
| `start_pos` | vec3 | player pos | Starting position (auto-detected if omitted) |
| `return_to_start` | boolean | &mdash; | Add a final leg returning to start |
| `weights` | table | &mdash; | Custom importance weights per node |
| `avoid_zones` | table[] | &mdash; | Avoidance zones |

#### Callback Data (on success)

```lua
{
    waypoints = vec3[],        -- Flattened waypoints for all legs
    visit_order = number[],    -- 1-indexed order of node visits
    leg_boundaries = number[], -- Waypoint indices marking leg transitions
    leg_distances = number[],  -- Distance of each leg in yards
    total_distance = number,   -- Total route distance in yards
}
```

{: .note }
`visit_order` is automatically converted from SentinelNavServer's 0-indexed format to Lua's 1-indexed format.

---

### find_route_multi

```lua
nav:find_route_multi(stops, callback, opts?)
```

Plan an ordered multi-stop route. Unlike TSP, stops are visited in the **exact order provided**.

**Endpoint:** `GET /api/v1/path-multi`

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `stops` | vec3[] | yes | At least 2 ordered stop positions |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | Same options as [find_path](#find_path) plus `avoid_zones` |

#### Callback Data (on success)

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

Validate that remaining waypoints are still walkable on the navmesh. Used periodically to detect path invalidation without requesting a full repath.

**Endpoint:** `GET /api/v1/path/check`

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `current_pos` | vec3 | yes | Player's current position |
| `waypoints` | vec3[] | yes | Remaining waypoints to validate |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | `{ map_id = auto, max_check = number }` |

#### Callback Data (on success)

```lua
{
    valid = boolean,                    -- Entire path is walkable
    first_invalid_segment = number|nil, -- Index of first bad segment
    player_on_navmesh = boolean,        -- Player position is on navmesh
}
```

{: .note }
Movement automatically downsamples to ~10 evenly-spaced waypoints when more than 12 remain, to reduce the check_path query size.

---

## Spatial Queries

### raycast

```lua
nav:raycast(start_pos, dest, callback, opts?)
```

Cast a ray between two navmesh points to check for obstacles.

**Endpoint:** `GET /api/v1/raycast`

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `start_pos` | vec3 | yes | Ray origin |
| `dest` | vec3 | yes | Ray target |
| `callback` | function | yes | `function(ok, data, err)` |
| `opts` | table | no | `{ map_id = auto }` |

#### Callback Data (on success)

```lua
{
    hit = boolean,             -- true if ray hit an obstacle
    hit_position = vec3|nil,   -- Where the ray hit
    t = number,                -- 0-1 parameter along ray (1.0 = no hit)
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
|:------|:-----|:---------|:------------|
| `pos` | vec3 | yes | World position `{x, y, z}` to query |
| `callback` | function | yes | `function(ok, data, err)` &mdash; `data.height` on success |
| `opts` | table | no | `{ map_id = auto }` |

---

### get_all_heights

```lua
nav:get_all_heights(pos, callback, opts?)
```

Get all navmesh heights (multi-level) at a world position. Useful for multi-story areas like buildings, bridges, and cave systems.

**Endpoint:** `GET /api/v1/heights`

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `pos` | vec3 | yes | World position to query |
| `callback` | function | yes | `function(ok, data, err)` |
| `opts` | table | no | See options below |

#### Options

| Field | Type | Description |
|:------|:-----|:------------|
| `map_id` | number | Continent ID |
| `xy_extent` | number | XY search extent |
| `z_extent` | number | Z search extent |
| `max_polys` | number | Maximum polygons to query |
| `cluster_tolerance` | number | Height clustering tolerance |
| `filter_unreachable` | boolean | Filter out heights not reachable from `from_pos` |
| `from_pos` | vec3 | Reference position for reachability filtering |

---

### random_point

```lua
nav:random_point(callback, opts?)
```

Get a random valid point on the navmesh.

**Endpoint:** `GET /api/v1/random`

| Field | Type | Default | Description |
|:------|:-----|:--------|:------------|
| `map_id` | number | auto | Continent ID |
| `center` | vec3 | &mdash; | Center of search area (requires `radius`) |
| `radius` | number | &mdash; | Search radius in yards (requires `center`) |

{: .note }
Both `center` and `radius` must be provided together. If either is missing, a random point from the entire map is returned.

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
|:------|:-----|:---------|:------------|
| `player_pos` | vec3 | yes | Current position |
| `threats` | vec3[] | yes | Array of threat positions (at least 1) |
| `callback` | function | yes | `function(success, data, error)` |
| `opts` | table | no | See below |

#### Options

| Field | Type | Description |
|:------|:-----|:------------|
| `map_id` | number | Continent ID |
| `flee_distance` | number | Desired flee distance in yards |
| `smoothing` | string | Smoothing algorithm |
| `smooth_*` | number | Smoothing parameters |
| `filter_*` | number | Terrain cost filters |
| `wall_clearance` | number | Min wall distance |
| `avoid_zones` | table[] | Avoidance zones |

#### Callback Data (on success)

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
        core.log(string.format("Flee: %d waypoints, %.0f yards from threats",
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
|:------|:-----|:--------|:------------|
| `map_id` | number | auto | Continent ID |
| `kite_radius` | number | &mdash; | Desired distance from target |
| `arc_degrees` | number | &mdash; | Arc segment angle in degrees |
| `direction` | string | &mdash; | `"cw"` (clockwise) or `"ccw"` (counter-clockwise) |
| `smoothing` | string | &mdash; | Smoothing algorithm |
| `smooth_*` | number | &mdash; | Smoothing parameters |
| `filter_*` | number | &mdash; | Terrain cost filters |
| `wall_clearance` | number | &mdash; | Min wall distance |

{: .note }
Kite does not support `z_extent` &mdash; arc waypoints are snapped to the navmesh directly, not via A* pathfinding.

#### Callback Data (on success)

```lua
{
    waypoints = vec3[],      -- Kite path positions
    waypoint_count = number, -- Number of arc waypoints
}
```

---

## Status

### health_check

```lua
nav:health_check(callback)
```

**Endpoint:** `GET /health`

```lua
nav:health_check(function(ok, data, err)
    if ok then
        core.log(string.format("Server: %s v%s, uptime %ds",
            data.status, data.version, data.uptime_secs))
    end
end)
```

**Callback data:**

```lua
{
    status = string,       -- "ok", "degraded", etc.
    version = string,      -- SentinelNavServer version
    uptime_secs = number,  -- Server uptime
    loaded_maps = table,   -- Map/continent status
}
```

---

### is_available

```lua
nav:is_available() -> boolean
```

Returns `true` after a successful request, `false` after 3+ consecutive failures.

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

Reset connection state (`_is_connected`, `_consecutive_failures`, `_last_success_time`). Call when switching maps or after extended disconnections.

---

### is_indoor

```lua
Navigation.is_indoor() -> boolean
```

**Static method** (no instance needed). Returns `true` if the current UiMapID is a dungeon or raid zone. Used by Movement to decide between normal and corridor pathfinding.

---

## Map ID Auto-Detection

If `opts.map_id` is not provided, Navigation automatically detects the current continent:

1. Calls `core.get_map_id()` to get the current UiMapID
2. Looks up the UiMapID in the `UI_MAP_TO_CONTINENT` table
3. Defaults to `0` (Eastern Kingdoms) if the UiMapID is unmapped

### Continent IDs

| ID | Continent | Example UiMapIDs |
|:---|:----------|:----------------|
| `0` | Eastern Kingdoms | 37, 42, 47, 56, 84, 87, 94, 122, 124, ... |
| `1` | Kalimdor | 57, 62, 63, 64, 65, 69, 70, 76, 77, 80, ... |
| `530` | Outland | 100, 104, 105, 107, 108, 109, 111, ... |
| `571` | Northrend | 113, 114, 115, 116, 117, 118, 119, 120, 121, 123, ... |

See [Constants Reference](/reference/constants) for the full mapping tables.

---

## Error Handling

### Retry Behavior

Failed HTTP requests retry with exponential backoff:

| Attempt | Delay |
|:--------|:------|
| 1 | Immediate |
| 2 | 0.5s |
| 3 | 1.0s |
| 4+ | 2.0s |

Retryable HTTP status codes: `0`, `500`, `502`, `503`, `504`.

### Connection Tracking

| Event | Effect |
|:------|:-------|
| Successful request | `_is_connected = true`, `_consecutive_failures = 0` |
| All retries exhausted | `_consecutive_failures` incremented |
| 3+ consecutive failures | `_is_connected = false` |

### Callback Error Patterns

All callbacks follow the same signature:

```lua
function(success, data, error)
    -- success: boolean
    -- data:    table on success, nil on failure
    -- error:   string on failure, nil on success
end
```

**Common error strings:**

| Error | Cause |
|:------|:------|
| `"Missing start or dest"` | nil position parameters |
| `"Empty path"` | Server returned no waypoints |
| `"Need at least 2 nodes"` | Insufficient nodes for TSP/multi |
| `"HTTP error: <status>"` | Server returned non-200 after all retries |
| `"JSON parse error: <details>"` | Malformed server response |
| `"Server error: <message>"` | Server returned `success: false` with message |

### Callback Safety

All callbacks are wrapped in `pcall`. If your callback throws an error, it is caught and logged but does not crash SentinelNavClient.

---

## HTTP Infrastructure Details

### URL Building

`_build_url(endpoint, params)` constructs query strings with:
- Numbers formatted as `%g` (compact representation)
- Booleans as `"true"` / `"false"`
- Table values iterated for repeated keys
- Parameters with nil values are omitted

### JSON Handling

Responses are parsed via a pure-Lua JSON decoder. Both success and error responses are JSON-decoded (to extract the `.error` field from server error responses). NaN and ±Inf values in responses encode as `null`.
