# Movement API Reference

High-level path-following module that wraps [Navigation](Navigation.md). Handles waypoint traversal, stuck detection and recovery, route planning, indoor corridor adaptation, obstacle avoidance, and casting deferral.

**Important:** You must call `movement:update()` every frame for the module to function.

## Table of Contents

- [Constructor](#constructor)
- [Movement Control](#movement-control)
  - [move_to](#move_to)
  - [move_direct](#move_direct)
  - [stop](#stop)
  - [follow_path](#follow_path)
- [Route Planning](#route-planning)
  - [plan_route](#plan_route)
  - [replan](#replan)
- [Validation](#validation)
  - [validate_destination_reachable](#validate_destination_reachable)
- [State & Progress](#state--progress)
  - [update](#update)
  - [get_state](#get_state)
  - [is_moving](#is_moving)
  - [get_current_path](#get_current_path)
  - [get_destination](#get_destination)
  - [get_path_index](#get_path_index)
  - [get_progress](#get_progress)
  - [get_corridor_widths](#get_corridor_widths)
- [Obstacle Integration](#obstacle-integration)
  - [set_obstacle_module](#set_obstacle_module)
- [Configuration](#configuration)
  - [Constructor Config](#constructor-config)
  - [update_config](#update_config)
- [State Machine](#state-machine)
- [Stuck Recovery](#stuck-recovery)
- [Indoor Corridor Adaptation](#indoor-corridor-adaptation)
- [Proactive Obstacle Detection](#proactive-obstacle-detection)
- [Casting Deferral](#casting-deferral)
- [Path Validation](#path-validation)

---

## Constructor

### `Movement:new(nav_client, config) -> Movement`

Create a new movement module instance.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `nav_client` | Navigation | yes | Navigation instance for pathfinding |
| `config` | table | no | Configuration overrides (see [Constructor Config](#constructor-config)) |

**Example:**
```lua
local nav = _G.NavLib.Navigation:new()
local movement = _G.NavLib.Movement:new(nav, {
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

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `target` | vec3 | yes | Destination `{x, y, z}` |
| `callback` | function | no | `function(success, reason)` |
| `opts` | table | no | Movement options |

**Options:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `use_navmesh` | boolean | `true` | Use pathfinding (false = direct movement) |
| `map_id` | number | auto | Continent ID to pass to NavBuddy |

**Callback:**
```lua
function(success, reason)
    -- success: true = arrived at destination
    -- reason:  nil on success, error string on failure
end
```

**Behavior:**
1. If player is casting/channeling, defers until cast ends
2. If `use_navmesh = false`, moves directly without pathfinding
3. Otherwise requests path from NavBuddy (corridor path if indoors, normal path outdoors)
4. If an Obstacle is attached and has avoidance zones, uses `find_path_avoid()` instead of `find_path()`
5. On path received, starts following waypoints
6. Adjusts waypoint tolerance for narrow indoor corridors (40% of min corridor width, minimum 1.0)

**Example:**
```lua
movement:move_to({ x = -8900, y = 560, z = 94 }, function(ok, reason)
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
movement:move_direct(target, callback?)
```

Move directly to a target without pathfinding. Equivalent to `move_to(target, callback, { use_navmesh = false })`.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `target` | vec3 | yes | Destination |
| `callback` | function | no | `function(success, reason)` |

---

### stop

```lua
movement:stop()
```

Stop all movement and reset to idle state.

**Clears:**
- Active path and destination
- Pending callbacks
- Stuck detection counters
- Route data and corridor widths
- Resets waypoint tolerance to config defaults

---

### follow_path

```lua
movement:follow_path(waypoints, callback?)
```

Follow a pre-computed waypoint array without requesting a new path from NavBuddy. Sets state to `"moving"` and begins waypoint traversal with stuck detection. Useful when you already have waypoints from a manual `nav_client:find_path()` call or a cached path.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `waypoints` | vec3[] | yes | Array of positions to follow |
| `callback` | function | no | `function(success, reason)` |

**Example:**
```lua
movement:follow_path(cached_waypoints, function(ok, reason)
    if ok then
        core.log("Followed cached path to destination!")
    else
        core.log_error("Follow failed: " .. tostring(reason))
    end
end)
```

---

## Route Planning

### plan_route

```lua
movement:plan_route(nodes, callback?, opts?)
```

Plan and execute a TSP-optimized route through multiple nodes. NavBuddy calculates the optimal visit order, then Movement follows each leg sequentially.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `nodes` | vec3[] | yes | At least 2 positions to visit |
| `callback` | function | no | Route progress callback |
| `opts` | table | no | Route options |

**Options:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `map_id` | number | auto | Continent ID |
| `return_to_start` | boolean | — | Return to starting position after visiting all nodes |

**Callback:** Called multiple times during route execution:
```lua
function(success, data)
    if success then
        if data.type == "leg_complete" then
            -- Reached a node
            -- data.leg:   current leg number
            -- data.total: total number of legs
        elseif data.type == "route_complete" then
            -- All nodes visited
        end
    else
        -- Route failed
        -- data.error: error message
    end
end
```

**Example:**
```lua
local herb_spots = {
    { x = -9100, y = 400, z = 93 },
    { x = -9200, y = 500, z = 91 },
    { x = -8900, y = 600, z = 95 },
    { x = -9000, y = 350, z = 90 },
}

movement:plan_route(herb_spots, function(ok, data)
    if ok and data.type == "leg_complete" then
        core.log(string.format("Node %d/%d reached", data.leg, data.total))
    elseif ok and data.type == "route_complete" then
        core.log("Gathering route complete!")
    elseif not ok then
        core.log_error("Route error: " .. data.error)
    end
end, {
    return_to_start = true,
})
```

---

### replan

```lua
movement:replan(reason?)
```

Replan the active route starting from the current leg. Useful when conditions change mid-route (e.g., a node was depleted).

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `reason` | string | no | Reason for replanning (logged) |

**Behavior:**
- Requires an active route (from `plan_route`)
- Collects remaining unvisited nodes
- Stops current movement
- Calls `plan_route` with remaining nodes
- Fails if fewer than 2 nodes remain

---

## Validation

### validate_destination_reachable

```lua
movement:validate_destination_reachable(target, callback)
```

Check if a destination is reachable via navmesh **without starting movement**. Useful for pre-validating waypoints before committing to travel.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `target` | vec3 | yes | Target position `{x, y, z}` |
| `callback` | function | yes | `function(reachable, reason, distance)` |

**Callback:**
```lua
function(reachable, reason, distance)
    -- reachable: true if path exists
    -- reason:    nil on success, error string on failure
    -- distance:  path distance in yards on success, nil on failure
end
```

**Example:**
```lua
movement:validate_destination_reachable(next_waypoint, function(ok, reason, dist)
    if ok then
        core.log(string.format("Waypoint reachable, %.0f yards away", dist))
        movement:move_to(next_waypoint)
    else
        core.log_error("Waypoint unreachable: " .. tostring(reason))
        -- Skip this waypoint
    end
end)
```

---

## State & Progress

### update

```lua
movement:update()
```

**Must be called every frame.** Drives the movement state machine: advances waypoints, checks for arrival, runs stuck detection, processes recovery actions, validates paths, scans for obstacles, and tracks route progress.

```lua
core.register_on_update_callback(function()
    movement:update()
end)
```

---

### get_state

```lua
movement:get_state() -> string
```

Returns the current state. One of:

| State | Description |
|-------|-------------|
| `"idle"` | Not moving |
| `"requesting_path"` | Waiting for path from NavBuddy |
| `"moving"` | Actively following waypoints |
| `"stuck"` | Stuck recovery in progress |
| `"arrived"` | Reached destination (transitions to idle after callback) |
| `"failed"` | Movement failed (max stuck attempts, path error, etc.) |

---

### is_moving

```lua
movement:is_moving() -> boolean
```

Returns `true` if state is `"moving"` or `"requesting_path"`.

---

### get_current_path

```lua
movement:get_current_path() -> vec3[]|nil
```

Returns the current waypoint array, or `nil` if not moving.

---

### get_destination

```lua
movement:get_destination() -> vec3|nil
```

Returns the current destination, or `nil` if not moving.

---

### get_path_index

```lua
movement:get_path_index() -> number
```

Returns the current waypoint index in the active path. Returns `1` if no path is active.

---

### get_progress

```lua
movement:get_progress() -> table
```

Detailed progress snapshot.

**Returns:**
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

**Example:**
```lua
local p = movement:get_progress()
if p.route_mode then
    core.log(string.format("Leg %d/%d, WP %d/%d, %.0f yards left",
        p.current_leg, p.total_legs,
        p.path_index, p.path_count,
        p.distance_remaining or 0))
end
```

---

### get_corridor_widths

```lua
movement:get_corridor_widths() -> number[]|nil
```

Returns corridor width data for the current path (indoor corridor paths only), or `nil` if outdoors or no data.

---

## Obstacle Integration

### set_obstacle_module

```lua
movement:set_obstacle_module(obstacle_module)
```

Attach an [Obstacle](Obstacle.md) instance for avoidance-aware pathfinding. When set:

- Proactive obstacle scanning runs every `proactive_obstacle_interval` seconds during movement
- Detected obstacle zones are passed to [`find_path_avoid()`](Navigation.md#find_path_avoid) for rerouting
- Reactive probing triggers on the 2nd stuck recovery attempt

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `obstacle_module` | Obstacle | yes | Obstacle detection instance |

> **Note:** When using [Facade](Facade.md), this is called automatically during construction. You only need to call this if you're wiring modules manually.

---

## Configuration

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

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `overrides` | table | yes | Key-value pairs to merge into config |

**Example:**
```lua
movement:update_config({
    smoothing = "catmull_rom",
    anti_detection = true,
    max_deviation = 5.0,
})
```

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
- `requesting_path` -> `moving`: Path received from NavBuddy
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

When an [Obstacle](Obstacle.md) is attached via `set_obstacle_module()` and `proactive_obstacle_check = true`:

1. Every `proactive_obstacle_interval` seconds (default: 1.5s) during movement, scans upcoming waypoint segments for doodad collisions
2. Uses `Obstacle:probe_path_ahead()` with `core.graphics.trace_line` to check for blocked segments
3. If an obstacle is detected: adds an avoidance zone to the Obstacle, then triggers a repath via [`find_path_avoid()`](Navigation.md#find_path_avoid) to route around it
4. **Reactive fallback:** On the 2nd stuck recovery attempt, probes forward from the player's position. If an obstacle is found, adds a zone and repaths immediately

This feature is fully automatic when using [Facade](Facade.md) — the facade wires the Obstacle into Movement during construction.

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

## Complete Usage Example

```lua
-- Recommended: Use Facade for automatic setup
local nav = _G.NavLib.create({
    movement = {
        waypoint_tolerance = 3.0,
        smoothing = "chaikin",
        optimize = true,
        anti_detection = true,
        max_deviation = 3.0,
        use_corridor_indoor = true,
    },
})

-- Register frame update
core.register_on_update_callback(function()
    nav:update()
end)

-- Move to a location
local dest = { x = -8900, y = 560, z = 94 }

-- Pre-validate first
nav:validate_destination(dest, function(reachable, reason, distance)
    if not reachable then
        core.log_error("Can't reach destination: " .. tostring(reason))
        return
    end

    core.log(string.format("Destination valid, %.0f yards away", distance))

    -- Start moving
    nav:move_to(dest, function(success, reason)
        if success then
            core.log("Arrived at destination!")
        else
            core.log_error("Movement failed: " .. tostring(reason))
        end
    end)
end)
```

**Manual setup (advanced):**
```lua
local Navigation = _G.NavLib.Navigation
local Movement = _G.NavLib.Movement
local Obstacle = _G.NavLib.Obstacle

local nav_client = Navigation:new()
local movement = Movement:new(nav_client, { smoothing = "chaikin" })
local obstacle = Obstacle:new()
movement:set_obstacle_module(obstacle)

core.register_on_update_callback(function()
    obstacle:update()
    movement:update()
end)
```
