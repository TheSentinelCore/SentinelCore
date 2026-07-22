---
title: "Sentinel Navigation"
source: "https://docs.project-sylvanas.net/dev/api/sentinel-navigation"
crawled: "2026-07-14"
---

# Sentinel Navigation

## Overview

The `SentinelNavClient` is a third-party navigation library that provides shared pathfinding and movement for consumer plugins through a single global client instance (`_G.SentinelNavClient.client`).

It handles pathfinding integration with SentinelNavServer, runtime movement behavior (HSM + Behavior Tree), obstacle probing and avoidance-zone memory, and in-game settings UI and visualization.

> **Third-Party Library**: The original developer of the navigation system is **not part of the internal PS team**. This is a third-party plugin, so the API can change between versions. This page reflects the API as of **July 2026** (`v0.0.8`).

> **note**: Requires **SentinelNavServer** running and reachable. Use `client:is_server_available()` to check before issuing navigation commands.

Recent reliability improvements (v0.0.6 to v0.0.8):
- **Off-mesh targets auto-snap (v0.0.8).** If a `move_to` target is slightly off the walkable navmesh (a common cause is a wrong or unknown `z`), the client resolves the nearest reachable point and paths there instead of failing with "Position not on navmesh". It is on by default and can be turned off in the Pathfinding settings tab ("Snap Off-Mesh Targets").
- **Transient server errors are retried (v0.0.7).** A brief network hiccup (for example a dropped keep-alive connection) no longer surfaces as a hard error or trips a false disconnect; it is retried with backoff.
- **Version is visible (v0.0.7).** The running version prints to the console on load, shows in the in-game menu and the settings window title, and is appended to every error log line as `[vX.Y.Z]`, so a user bug report tells you which build they run.

---

## Quick Start

```lua
if not (_G.SentinelNavClient and _G.SentinelNavClient.client) then
    core.log_error("SentinelNavClient not loaded")
    return
end

local client = _G.SentinelNavClient.client

client:move_to(vec3.new(-8900, 560, 94), function(ok, reason)
    if ok then
        core.log("Arrived")
    else
        core.log_error("Navigation failed: " .. tostring(reason))
    end
end)
```

> **Consumer Rules**:
> - **Do not** call `client:update()` from consumer plugins — SentinelNavClient drives updates internally.
> - **Do not** own navigation tuning in consumer plugins — SentinelNavClient UI owns config.

> **Positions accept vec3 or a table**: Every position argument accepts a **`vec3`** (`vec3.new(x, y, z)`) **or** a plain `{ x = , y = , z = }` table. Both work, so existing table-based code keeps running unchanged. Methods that return positions (`get_destination`, `get_current_path`, `plan_route` waypoints, `random_point`, ...) return a **`vec3`**. The examples below use `vec3`.

---

## Global Table

### `_G.SentinelNavClient`

| Field | Type | Description |
|-------|------|-------------|
| `client` | `sentinel_nav_client\|nil` | Live getter for the shared singleton Client |
| `create(config?)` | `function` | Returns the shared Client. `config` is accepted but ignored |
| `ui` | `table` | UI orchestrator module |
| `JSON` | `table` | JSON utility module |
| `Helpers` | `table` | General helper utility module |
| `VERSION` | `string` | Current plugin version |

---

## Movement Commands

### `client:move_to(target, callback?, opts?)`

```
client:move_to(target, callback?, opts?)
```

**Parameters**
- **`target`** (*table*) — `{ x, y, z }` destination position.
- **`callback`** (*function?*) — `function(success: boolean, reason: string?)` called on completion.
- **`opts`** (*table?*) — Optional overrides copied to blackboard as `opts.*`.

Description: Pathfinds to the target and starts navigation. Defers the move while casting (enters `navigating.deferred`). Otherwise transitions into `navigating.awaiting_path` and the Behavior Tree requests a path.

As of `v0.0.8`, if the exact target is slightly off the navmesh the client snaps to the nearest reachable point instead of failing, so you do not need pixel-perfect coordinates. If the whole area is genuinely unreachable it still fails with `unreachable`.

**Example Usage**

```lua
client:move_to(vec3.new(-8900, 560, 94), function(ok, reason)
    if ok then
        core.log("Arrived at destination")
    else
        core.log_error("Move failed: " .. tostring(reason))
    end
end)
```

---

### `client:move_direct(target, callback?)`

```
client:move_direct(target, callback?)
```

**Parameters**
- **`target`** (*table*) — `{ x, y, z }` destination position.
- **`callback`** (*function?*) — `function(success: boolean, reason: string?)` called on completion.

Description: Follows a direct single-waypoint path to the target without pathfinding. Useful when the path is known to be clear.

---

### `client:follow_path(waypoints, callback?)`

```
client:follow_path(waypoints, callback?)
```

**Parameters**
- **`waypoints`** (*table[]*) — Array of `{ x, y, z }` positions to follow in order.
- **`callback`** (*function?*) — `function(success: boolean, reason: string?)` called on completion.

Description: Follows a precomputed list of waypoints. Commonly used to execute a route returned by `plan_route`.

---

### `client:plan_route(nodes, callback?, opts?)`

```
client:plan_route(nodes, callback?, opts?)
```

**Parameters**
- **`nodes`** (*table[]*) — Array of `{ x, y, z }` positions to visit.
- **`callback`** (*function?*) — `function(success: boolean, data: table?)` called with route data.
- **`opts`** (*table?*) — Optional route options (e.g. `{ return_to_start = false }`).

Returns (via callback): On success, `data` contains:

| Field | Type | Description |
|-------|------|-------------|
| `waypoints` | `vec3[]` | Ordered waypoints for the full route |
| `visit_order` | `integer[]` | 1-based visitation order |
| `leg_boundaries` | `integer[]` | Waypoint indices where legs start |
| `leg_distances` | `number[]` | Distance of each leg |
| `total_distance` | `number` | Total route distance |

On failure, `data` may be `nil` or `{ error = string }`.

Description: Plans a TSP (Traveling Salesman Problem) route through the given nodes. This is a **planning-only** call — it does not execute the route. To execute the route, call `client:follow_path(data.waypoints, ...)` with the returned waypoints.

**Example Usage**

```lua
local nodes = {
    vec3.new(-9100, 400, 93),
    vec3.new(-9200, 500, 91),
    vec3.new(-8900, 600, 95),
}

client:plan_route(nodes, function(ok, data)
    if not ok then
        core.log_error("Route plan failed: " .. tostring(data and data.error))
        return
    end
    client:follow_path(data.waypoints, function(success, reason)
        if success then
            core.log("Route execution complete")
        else
            core.log_error("Route execution failed: " .. tostring(reason))
        end
    end)
end, {
    return_to_start = false,
})
```

---

### `client:start_route(nodes, callback?, opts?)`

```
client:start_route(nodes, callback?, opts?)
```

**Parameters**
- **`nodes`** (*table[]*) Array of `{ x, y, z }` positions to visit.
- **`callback`** (*function?*) `function(success: boolean, reason: string?)` called when the route finishes.
- **`opts`** (*table?*) Optional route options (for example `{ return_to_start = false }`).

Description: Plans a TSP route through the nodes and starts following it in a single call. This is the execute version of `plan_route`: use `plan_route` when you only want the route data back, and `start_route` when you want the client to plan the order and then walk it for you.

**Example Usage**

```lua
local nodes = {
    vec3.new(-9100, 400, 93),
    vec3.new(-9200, 500, 91),
    vec3.new(-8900, 600, 95),
}

client:start_route(nodes, function(ok, reason)
    if ok then
        core.log("Route complete")
    else
        core.log_error("Route failed: " .. tostring(reason))
    end
end)
```

---

### `client:validate_destination(target, callback)`

```
client:validate_destination(target, callback)
```

**Parameters**
- **`target`** (*table*) — `{ x, y, z }` destination position.
- **`callback`** (*function*) — `function(reachable: boolean, reason: string?, distance: number?)`.

Description: Reachability probe without starting movement. Use this to check if a destination is reachable before committing to navigation.

**Example Usage**

```lua
client:validate_destination(target, function(reachable, reason, distance)
    if not reachable then
        core.log_warning("Target unreachable: " .. tostring(reason))
        return
    end
    client:move_to(target, function(ok, fail_reason)
        if ok then
            core.log("Arrived (" .. string.format("%.1f", distance or 0) .. " yd)")
        else
            core.log_error("Move failed: " .. tostring(fail_reason))
        end
    end)
end)
```

---

### `client:replan(reason?)`

```
client:replan(reason?)
```

**Parameters**
- **`reason`** (*string?*) — Optional reason for the replan (for logging).

Description: Re-requests the current path to the current destination by clearing path state and returning to `awaiting_path`.

---

### `client:stop()`

```
client:stop()
```

Description: Stops all movement and resets the active navigation state.

---

## State and Progress

### `client:get_state()`

```
client:get_state() -> string
```

Returns:
- `string` — One of: `"idle"`, `"navigating"`, `"arrived"`, `"failed"`.

---

### `client:get_full_state()`

```
client:get_full_state() -> string
```

Returns:
- `string` — Dot-joined hierarchical state (e.g. `"navigating.recovering.strafing"`).

---

### `client:is_moving()`

```
client:is_moving() -> boolean
```

Returns:
- `boolean` — `true` only while the top-level state is `navigating`.

---

### `client:get_destination()`

```
client:get_destination() -> vec3|nil
```

Returns:
- `vec3|nil` — The current navigation destination, or `nil` if idle.

---

### `client:get_current_path()`

```
client:get_current_path() -> vec3[]|nil
```

Returns:
- `vec3[]|nil` — The current list of waypoints being followed, or `nil`.

---

### `client:get_path_index()`

```
client:get_path_index() -> number
```

Returns:
- `number` — The index of the waypoint currently being approached.

---

### `client:get_progress()`

```
client:get_progress() -> sentinel_nav_progress
```

Returns:

| Field | Type | Description |
|-------|------|-------------|
| `percent` | `number` | Progress from 0 to 1 |
| `waypoints_remaining` | `number` | Waypoints left |
| `total_waypoints` | `number` | Total waypoints in path |
| `current_index` | `number` | Current waypoint index |

**Example Usage**

```lua
if client:is_moving() then
    local full = client:get_full_state()
    local p = client:get_progress()
    core.log(string.format(
        "[%s] %.0f%% (%d/%d)",
        full,
        (p.percent or 0) * 100,
        p.current_index or 1,
        p.total_waypoints or 0
    ))
end
```

---

### `client:get_corridor_widths()`

```
client:get_corridor_widths() -> number[]|nil
```

Returns:
- `number[]|nil` — Corridor widths per waypoint, or `nil` if not available.

---

## Server Queries

### `client:is_server_available()`

```
client:is_server_available() -> boolean
```

Returns:
- `boolean` — `true` when the server connection flag is up.

Description: Reflects the blackboard connection flag maintained by NavigationService. Set `true` after successful responses, marked disconnected after repeated failures.

---

### `client:health_check(callback)`

```
client:health_check(callback)
```

**Parameters**
- **`callback`** (*function*) — `function(ok: boolean)` called with server health result.

**Example Usage**

```lua
if not client:is_server_available() then
    client:health_check(function(ok)
        if ok then
            core.log("SentinelNavServer reachable")
        else
            core.log_warning("SentinelNavServer unavailable")
        end
    end)
end
```

---

### `client:get_height(pos, callback)`

```
client:get_height(pos, callback)
```

**Parameters**
- **`pos`** (*table*) — `{ x, y, z }` position.
- **`callback`** (*function*) — Callback with navmesh height at position.

---

### `client:get_player_height(callback)`

```
client:get_player_height(callback)
```

**Parameters**
- **`callback`** (*function*) — Callback with navmesh height at current player position.

---

### `client:get_all_heights(pos, callback, opts?)`

```
client:get_all_heights(pos, callback, opts?)
```

**Parameters**
- **`pos`** (*table*) — `{ x, y, z }` position.
- **`callback`** (*function*) — Callback with multi-layer heights at the XY position.
- **`opts`** (*table?*) — Optional options.

---

### `client:get_player_all_heights(callback, opts?)`

```
client:get_player_all_heights(callback, opts?)
```

**Parameters**
- **`callback`** (*function*) — Callback with multi-layer heights at the player position.
- **`opts`** (*table?*) — Optional options.

---

## Events

### Legacy Events (`client:on` / `client:off`)

```lua
client:on("arrived", function()
    core.log("Arrived at destination")
end)

client:on("failed", function()
    core.log_error("Navigation failed")
end)

client:on("state_change", function(data)
    core.log("State: " .. tostring(data.from) .. " -> " .. tostring(data.to))
end)

client:on("stuck", function()
    core.log_warning("Stuck detected")
end)
```

| Event | Payload |
|-------|---------|
| `"state_change"` | `{ from: string, to: string }` |
| `"arrived"` | — |
| `"stuck"` | — (mapped from `navigating.recovering`) |
| `"failed"` | — |

---

### EventBus Events

For more granular control, use the EventBus:

```lua
local bus = client:get_event_bus()

bus:on("nav.state_changed", function(data, event_name)
    core.log(event_name .. ": " .. tostring(data.from) .. " -> " .. tostring(data.to))
end, { owner = self, priority = 50 })

bus:on_pattern("nav.server_*", function(data, event_name)
    core.log("Server event: " .. event_name)
end, { owner = self })

-- Cleanup:
bus:off_owner(self)
```

**Available Events:**

| Event | Description |
|-------|-------------|
| `nav.state_changed` | State machine transition |
| `nav.arrived` | Destination reached |
| `nav.failed` | Navigation failed |
| `nav.stuck_detected` | Stuck condition detected |
| `nav.stuck_recovered` | Recovered from stuck |
| `nav.deviation_detected` | Path deviation detected |
| `nav.repath_started` | Repath in progress |
| `nav.repath_completed` | Repath finished |
| `nav.obstacle_detected` | Obstacle encountered |
| `nav.path_requested` | Path request sent to server |
| `nav.path_received` | Path response received |
| `nav.path_failed` | Path request failed |
| `nav.waypoint_reached` | A waypoint was reached |
| `nav.server_connected` | Server connection established |
| `nav.server_retry` | Server retry attempt |
| `nav.server_disconnected` | Server connection lost |
| `nav.server_error` | Server error occurred |

**EventBus Methods:**

| Method | Description |
|--------|-------------|
| `bus:on(event, callback, opts?)` | Subscribe to event |
| `bus:once(event, callback, opts?)` | Subscribe once |
| `bus:on_pattern(pattern, callback, opts?)` | Subscribe to pattern (e.g. `"nav.server_*"`) |
| `bus:off(id)` | Unsubscribe by ID |
| `bus:off_owner(owner)` | Unsubscribe all by owner |
| `bus:pause()` | Pause event delivery |
| `bus:resume()` | Resume event delivery |

---

## State Model

### Top-Level States

| State | Description |
|-------|-------------|
| `idle` | No active navigation |
| `navigating` | Actively navigating |
| `arrived` | Destination reached |
| `failed` | Navigation failed |

### Navigating Substates

| Substate | Description |
|----------|-------------|
| `awaiting_path` | Waiting for path from server |
| `following_path` | Following the active path |
| `recovering` | Attempting stuck recovery |
| `repathing` | Re-requesting the path |
| `deferred` | Move deferred (e.g. while casting) |

### Recovery Sub-Substates

| Sub-Substate | Description |
|--------------|-------------|
| `jumping` | Attempting to jump over obstacle |
| `probing` | Probing for alternative path |
| `strafing` | Strafing sideways |
| `backtracking` | Moving backwards |

### Failure Reasons

| Reason | Description |
|--------|-------------|
| `unreachable` | Destination cannot be reached |
| `server_timeout` | Server did not respond |
| `max_stuck_exceeded` | Too many stuck recovery attempts |
| `max_repath_exceeded` | Too many repath attempts |

---

## Advanced APIs

> **Use With Care**: These are lower-level services exposed on the client. They are more likely to change than the high-level Client API.

Accessible as fields on the client:
- `client.nav_client` — NavigationService (core pathing, spatial queries, tactical)
- `client.movement` — MovementService (waypoint following, strafe, speed)
- `client.obstacle` — ObstacleService (probing, avoidance zones)

### NavigationService (`client.nav_client`)

| Method | Description |
|--------|-------------|
| `find_path(start, dest, callback, opts?)` | Core A* pathfinding |
| `find_route_tsp(nodes, callback, opts?)` | TSP route planning |
| `find_route_multi(stops, callback, opts?)` | Multi-stop route |
| `check_path(pos, waypoints, callback, opts?)` | Validate existing path |
| `find_path_corridor(start, dest, callback, opts?)` | Path with corridor widths |
| `find_path_avoid(start, dest, zones, callback, opts?)` | Path avoiding zones |
| `raycast(start, dest, callback, opts?)` | Navmesh raycast |
| `get_height(pos, callback, opts?)` | Navmesh height query |
| `get_all_heights(pos, callback, opts?)` | Multi-layer height query |
| `random_point(callback, opts?)` | Random reachable point |
| `flee(player_pos, threats, callback, opts?)` | Flee from threats |
| `kite(player_pos, target_pos, callback, opts?)` | Kite a target |
| `health_check(callback)` | Server health ping |
| `is_available()` | Server connection status |
| `NavigationService.is_indoor()` | Indoor detection (static) |
| `NavigationService.get_continent_id()` | Current continent ID (static) |

### MovementService (`client.movement`)

| Method | Description |
|--------|-------------|
| `navigate(waypoints)` | Start following waypoints |
| `process()` | Tick movement processing |
| `stop()` | Stop movement |
| `get_current_index()` | Current waypoint index |
| `get_remaining_waypoints()` | Remaining waypoint count |
| `is_moving()` | Is movement active |
| `strafe(direction)` | Strafe in a direction |
| `apply_dynamic_speed(blackboard?)` | Apply dynamic speed adjustments |

### ObstacleService (`client.obstacle`)

| Method | Description |
|--------|-------------|
| `probe_forward(player_pos, target_pos)` | Probe ahead for obstacles |
| `probe_segment(pos_a, pos_b)` | Probe a line segment |
| `probe_path_ahead(waypoints, max_segments?)` | Probe multiple segments ahead |
| `add_zone(pos, radius?)` | Add avoidance zone |
| `remove_zone(index)` | Remove avoidance zone |
| `get_avoidance_zones()` | Get all avoidance zones |
| `get_zone_count()` | Number of active zones |
| `clear()` | Clear all zones |
