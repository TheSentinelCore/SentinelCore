---
title: Client
layout: default
parent: API Reference
nav_order: 1
---

# Client API
{: .no_toc }

Single entry-point for SentinelNavClient. Wires and drives all modules, with a built-in event system for state-change notifications.
{: .fs-6 .fw-300 }

**This is the recommended way to use SentinelNavClient.** The Client wraps Navigation, Movement, and Obstacle into a single interface. For advanced use cases, see the [escape hatch](#escape-hatch) or the individual module APIs.

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## Accessing the Client

SentinelNavClient creates a single shared Client at initialization. All consumers share this instance.

### `_G.SentinelNavClient.client` (Recommended)
{: .d-inline-block }
Primary
{: .label .label-green }

Live getter via metatable `__index`. Returns the shared Client, or `nil` if SentinelNavClient hasn't initialized yet.

```lua
local client = _G.SentinelNavClient.client
if client then
    client:move_to(target, callback)
end
```

### `_G.SentinelNavClient.create(config?)` (Backward Compatible)

Returns the same shared Client. The `config` parameter is accepted but **ignored** &mdash; SentinelNavClient's UI owns all settings.

```lua
local client = _G.SentinelNavClient.create()
```

### `Client:new(config)` (Internal Only)
{: .d-inline-block }
Internal
{: .label .label-red }

Called by `SentinelNavClient/init.lua` during plugin initialization. **Consumers should NOT call this directly** &mdash; it would create an isolated Client disconnected from SentinelNavClient's update loop and settings sync.

---

## Update Loop

### update

```lua
client:update()
```

Drives all internal modules in the correct order:

1. `obstacle:update()` &mdash; compatibility hook (probing is timer-driven)
2. `movement:update()` &mdash; advances waypoints, stuck detection, obstacle scanning, deviation checks, path validation
3. Detects state transitions and fires [events](#events)

{: .note }
SentinelNavClient calls `client:update()` from its own `on_update` callback every frame. **Consumers do NOT need to call this.** If called anyway, it is harmless &mdash; Movement rate-limits internally.

---

## Movement Commands

All movement methods delegate to the internal [Movement](/api/movement) module. See that section for detailed behavior (casting deferral, corridor adaptation, stuck recovery, deviation monitoring, etc.).

### move_to

```lua
client:move_to(target, callback?, opts?)
```

Move to a target position using navmesh pathfinding.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `target` | vec3 | yes | Destination `{x, y, z}` |
| `callback` | function | no | `function(success, reason)` |
| `opts` | table | no | `{ use_navmesh = true, map_id = auto }` |

**Behavior:**
1. If the player is casting/channeling, the request is deferred until the cast ends
2. If `use_navmesh = false`, moves directly without pathfinding
3. If indoors and `use_corridor_indoor` is enabled, uses corridor pathfinding
4. If Obstacle has active avoidance zones, uses `find_path_avoid()` for rerouting
5. On path received, starts following waypoints with stuck recovery

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

Move directly to a target without pathfinding. Equivalent to `move_to(target, callback, { use_navmesh = false })`.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `target` | vec3 | yes | Destination `{x, y, z}` |
| `callback` | function | no | `function(success, reason)` |

---

### follow_path

```lua
client:follow_path(waypoints, callback?)
```

Follow a pre-computed waypoint array without requesting a new path from SentinelNavServer. Useful when you already have waypoints (e.g., from a direct `nav_client:find_path()` call or a cached path).

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
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

Plan and execute a TSP-optimized route through multiple nodes. SentinelNavServer computes the optimal visit order, then Movement follows each leg sequentially.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `nodes` | vec3[] | yes | At least 2 positions to visit |
| `callback` | function | no | Route progress callback |
| `opts` | table | no | `{ map_id = auto, return_to_start = false }` |

**Callback:** Called multiple times as route progress is made:

```lua
function(success, data)
    if success then
        if data.type == "leg_complete" then
            core.log(string.format("Leg %d/%d complete", data.leg, data.total))
        elseif data.type == "route_complete" then
            core.log("All nodes visited!")
        end
    else
        core.log_error("Route failed: " .. data.error)
    end
end
```

---

### replan

```lua
client:replan(reason?)
```

Replan the active route from the current leg. Requires an active route from `plan_route()`. Collects remaining unvisited nodes, stops current movement, and calls `plan_route()` with the remaining nodes. Fails if fewer than 2 nodes remain.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `reason` | string | no | Reason for replanning (logged) |

---

### validate_destination

```lua
client:validate_destination(target, callback)
```

Check if a destination is reachable **without starting movement**. Requests a path from SentinelNavServer and evaluates the result.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `target` | vec3 | yes | Target position |
| `callback` | function | yes | `function(reachable, reason, distance)` |

```lua
client:validate_destination(target, function(reachable, reason, distance)
    if reachable then
        core.log(string.format("Reachable! %.0f yards", distance))
    else
        core.log_error("Unreachable: " .. tostring(reason))
    end
end)
```

---

### stop

```lua
client:stop()
```

Stop all movement and reset to idle. Clears:
- Active path and destination
- Pending callbacks
- Stuck counters
- Route data
- Corridor widths
- Waypoint tolerance (reset to config defaults)

---

### destroy

```lua
client:destroy()
```

Stop movement, clear all obstacle avoidance zones, and remove event listeners. Call when permanently done with the SentinelNavClient instance.

{: .note }
Consumers should not call `destroy()` &mdash; SentinelNavClient manages the Client lifecycle. This is called automatically by `on_unload()`.

---

## State Queries

### get_state

```lua
client:get_state() -> string
```

Returns the current movement state:

| State | Description |
|:------|:------------|
| `"idle"` | Not moving |
| `"requesting_path"` | Waiting for path from SentinelNavServer |
| `"moving"` | Actively following waypoints |
| `"stuck"` | Stuck recovery in progress |
| `"arrived"` | Reached destination |
| `"failed"` | Movement failed (max recovery attempts exceeded) |

---

### is_moving

```lua
client:is_moving() -> boolean
```

Returns `true` if the state is `"moving"` or `"requesting_path"`.

---

### get_destination

```lua
client:get_destination() -> vec3|nil
```

Returns the current destination position, or `nil` if not moving.

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
    state = string,              -- Current movement state
    destination = vec3|nil,      -- Target position
    distance_remaining = number, -- Yards to destination (moving only)
    path_index = number,         -- Current waypoint index (moving only)
    path_count = number,         -- Total waypoints (moving only)
    current_leg = number,        -- Current route leg (route mode only)
    total_legs = number,         -- Total route legs (route mode only)
    route_mode = boolean,        -- true if executing a planned route
}
```

---

### get_corridor_widths

```lua
client:get_corridor_widths() -> number[]|nil
```

Returns corridor width data for the current indoor path (one width value per waypoint), or `nil` if outdoors or no corridor data is available.

---

## Server Queries

### is_server_available

```lua
client:is_server_available() -> boolean
```

Returns `true` if SentinelNavServer appears connected (has had a recent successful request, fewer than 3 consecutive failures).

---

### health_check

```lua
client:health_check(callback)
```

Check SentinelNavServer server health.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `callback` | function | yes | `function(ok, data, err)` |

**Callback data (on success):**

```lua
{
    status = string,       -- "ok", "degraded", etc.
    version = string,      -- SentinelNavServer version
    uptime_secs = number,  -- Server uptime in seconds
    loaded_maps = table,   -- Map/continent status
}
```

---

### get_height

```lua
client:get_height(pos, callback)
```

Get the navmesh Z-coordinate at arbitrary world coordinates.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `pos` | vec3 | yes | World position `{x, y, z}` to query |
| `callback` | function | yes | `function(ok, data, err)` &mdash; `data.height` on success |

---

### get_player_height

```lua
client:get_player_height(callback)
```

Convenience wrapper &mdash; gets the navmesh Z-coordinate at the local player's current position.

---

### get_all_heights

```lua
client:get_all_heights(pos, callback, opts?)
```

Get all navmesh heights (multi-level) at a world position. Useful for multi-story areas.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `pos` | vec3 | yes | World position to query |
| `callback` | function | yes | `function(ok, data, err)` |
| `opts` | table | no | See options below |

**Options:**

| Field | Type | Description |
|:------|:-----|:------------|
| `xy_extent` | number | XY search extent |
| `z_extent` | number | Z search extent |
| `max_polys` | number | Maximum polygons to query |
| `cluster_tolerance` | number | Height clustering tolerance |
| `filter_unreachable` | boolean | Filter out heights not reachable from `from_pos` |
| `from_pos` | vec3 | Reference position for reachability filtering |

---

### get_player_all_heights

```lua
client:get_player_all_heights(callback, opts?)
```

Convenience wrapper for `get_all_heights` at the player's current position. Automatically sets `from_pos` to the player position when `filter_unreachable` is enabled.

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

**Included fields:** `smoothing`, `optimize`, `anti_detection`, `max_deviation`, `allow_partial`, `filter_ground`, `filter_water`, `filter_lava`, `wall_clearance`, `smooth_iterations`, `smooth_samples`, `smooth_ratio`.

---

### get_corridor_opts

```lua
client:get_corridor_opts(extra?) -> table
```

Same as `get_path_opts` but also includes `probe_distance` from the corridor config. Use with `find_path_corridor`.

{: .warning }
**Avoidance zones with direct `nav_client` calls:** When using the escape hatch to call `nav_client` methods directly (e.g., `find_path_corridor`, `find_route_multi`), you must pass `avoid_zones` explicitly in the opts table. `client:move_to()` handles this automatically, but direct calls do not.

```lua
local zones = client.obstacle:get_avoidance_zones()
local opts = client:get_path_opts({ avoid_zones = zones })
client.nav_client:find_route_multi(stops, callback, opts)
```

---

## Client Configuration

### How Settings Work

SentinelNavClient owns all navigation settings via its built-in UI:

1. ~40 menu elements (persisted across sessions via `core.menu.*`)
2. `sync_to_client()` reads all elements every render frame
3. Calls `client:update_config()` with the resolved values
4. Movement and Obstacle modules update their internal config

**Consumers should NOT call `update_config()` directly** &mdash; their changes will be overwritten on the next render frame.

See [Configuration](/configuration) for the complete reference of all settings.

### update_config (Internal)
{: .d-inline-block }
Internal
{: .label .label-red }

```lua
client:update_config(overrides)
```

Distribute config updates to underlying modules at runtime. Only provided keys are changed.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `overrides` | table | yes | `{ movement = {...}, obstacles = {...} }` |

{: .note }
`navigation` config (`base_url`, `max_retries`) cannot be updated at runtime &mdash; it is set once during construction.

---

## Events

The Client fires events when the movement state changes. Use `on()` to subscribe and `off()` to unsubscribe.

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

| Event | Fired When | Callback Data |
|:------|:-----------|:-------------|
| `"state_change"` | Any state transition | `{ from = string, to = string }` |
| `"arrived"` | Reached destination | `nil` |
| `"stuck"` | Stuck detected | `nil` |
| `"failed"` | Movement failed (max recovery exceeded) | `nil` |

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

{: .note }
Event callbacks are wrapped in `pcall`. If a handler throws, it is caught and logged but does not affect other handlers or SentinelNavClient operation.

---

## Escape Hatch

For advanced use cases, the underlying module instances are exposed as public fields:

| Field | Type | Description |
|:------|:-----|:------------|
| `client.nav_client` | [Navigation](/api/navigation) | Raw HTTP client &mdash; direct access to all 14 endpoints |
| `client.movement` | [Movement](/api/movement) | Path follower &mdash; full state machine, stuck recovery |
| `client.obstacle` | [Obstacle](/api/obstacle) | Obstacle detector &mdash; zone memory, ray probing |

```lua
local client = _G.SentinelNavClient.client

-- Use the Client for common operations
client:move_to(target, callback)

-- Drop to raw Navigation for specialized queries
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

{: .note }
The Client and its modules share the same instances. Calling `movement:stop()` on the escape hatch has the same effect as `client:stop()`.

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
        core.log("SentinelNavServer v" .. data.version
            .. " (" .. data.uptime_secs .. "s uptime)")
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
