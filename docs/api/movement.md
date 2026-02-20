---
title: Movement
layout: default
parent: API Reference
nav_order: 3
---

# Movement API
{: .no_toc }

High-level path-following module that wraps [Navigation](/api/navigation). Handles waypoint traversal, stuck detection and recovery, route planning, indoor corridor adaptation, obstacle avoidance, deviation monitoring, and casting deferral.
{: .fs-6 .fw-300 }

{: .note }
Consumers should access the shared Movement module via `_G.SentinelNavClient.client.movement`. The shared instance is created and configured by SentinelNavClient. `movement:update()` is called every frame and `update_config()` is synced every render frame &mdash; consumers do not need to call either.

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## Constructor

### `Movement:new(nav_client, config) -> Movement`

Create a new Movement instance.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `nav_client` | Navigation | yes | Navigation instance for pathfinding |
| `config` | table | no | Configuration overrides (see [Configuration](/configuration#movement-settings)) |

```lua
local nav = Navigation:new({ base_url = "http://localhost:47110" })
local movement = Movement:new(nav, {
    waypoint_tolerance = 3.0,
    smoothing = true,
    optimize = true,
})
```

### Internal Constants

| Constant | Value | Description |
|:---------|:------|:------------|
| `BASE_RUN_SPEED` | `7.0` | Base run speed in yards/second, used for stuck detection scaling and dynamic speed ratio |

---

## Movement Control

### move_to

```lua
movement:move_to(target, callback?, opts?)
```

Move to a target position using navmesh pathfinding. Requests a path from Navigation, then follows it with stuck recovery.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `target` | vec3 | yes | Destination `{x, y, z}` |
| `callback` | function | no | `function(success, reason)` |
| `opts` | table | no | `{ use_navmesh = true, map_id = auto }` |

**Full behavior sequence:**

1. If the player is casting/channeling &rarr; defers the request until cast ends (see [Casting Deferral](#casting-deferral))
2. If `use_navmesh = false` &rarr; moves directly without pathfinding
3. Determines pathfinding mode:
   - If indoors and `use_corridor_indoor` is enabled &rarr; uses `find_path_corridor`
   - If Obstacle is attached and has avoidance zones &rarr; uses `find_path_avoid`
   - Otherwise &rarr; uses `find_path`
4. On path received &rarr; starts following waypoints
5. If indoor corridor path &rarr; adjusts waypoint tolerance to `max(1.0, min_corridor_width * 0.4)`

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

Stop all movement and reset to idle state. Clears:
- Active path and destination
- Pending callbacks
- Stuck counters and phase
- Route data (legs, boundaries, visit order)
- Corridor widths
- Deviation repath counters
- Waypoint and final tolerance (reset to config defaults)

---

### follow_path

```lua
movement:follow_path(waypoints, callback?)
```

Follow a pre-computed waypoint array without requesting a new path from SentinelNavServer. Sets state to `"moving"` and begins waypoint traversal with stuck detection.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
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
|:------|:-----|:---------|:------------|
| `nodes` | vec3[] | yes | At least 2 positions to visit |
| `callback` | function | no | Route progress callback |
| `opts` | table | no | `{ map_id = auto, return_to_start = false }` |

**Callback:** Called multiple times as each leg completes:

```lua
function(success, data)
    if success then
        if data.type == "leg_complete" then
            -- data.leg (current), data.total
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

Replan the active route starting from the current leg. Requires an active route.

**Behavior:**
1. Collects remaining unvisited nodes
2. Stops current movement
3. Calls `plan_route()` with remaining nodes
4. Fails if fewer than 2 nodes remain

---

## Validation

### validate_destination_reachable

```lua
movement:validate_destination_reachable(target, callback)
```

Check if a destination is reachable via navmesh **without starting movement**.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `target` | vec3 | yes | Target position |
| `callback` | function | yes | `function(reachable, reason, distance)` |

---

## State & Progress

### update

```lua
movement:update()
```

**Must be called every frame.** Drives the movement state machine:

1. Check pending move (casting deferral)
2. Advance waypoints (distance check against tolerance)
3. Check for arrival at final destination
4. Stuck detection (every `stuck_check_interval`)
5. Process recovery actions during stuck phase
6. Proactive obstacle scan (every `proactive_obstacle_interval`)
7. Deviation monitoring (every `deviation_check_interval`)
8. Path validity checks (every `path_check_interval`)
9. Route leg advancement

{: .note }
SentinelNavClient calls this automatically from its `on_update` callback. Consumers do not need to call it.

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

Returns the current waypoint array, or nil if no active path.

### get_destination

```lua
movement:get_destination() -> vec3|nil
```

Returns the current destination, or nil.

### get_path_index

```lua
movement:get_path_index() -> number
```

Returns the current waypoint index (1-based).

### get_progress

```lua
movement:get_progress() -> table
```

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

### get_corridor_widths

```lua
movement:get_corridor_widths() -> number[]|nil
```

Returns corridor width data for the current indoor path (one width value per waypoint), or nil if outdoors or no corridor data.

---

## Obstacle Integration

### set_obstacle_module

```lua
movement:set_obstacle_module(obstacle_module)
```

Attach an Obstacle instance for avoidance-aware pathfinding. When set:

- **Proactive scanning** runs every `proactive_obstacle_interval` seconds during movement
- Detected obstacle zones are passed to `find_path_avoid()` for rerouting
- **Reactive probing** triggers on the 2nd stuck recovery attempt

{: .note }
When using the Client, this is called automatically during construction. You only need to call this if you're wiring modules manually.

---

## State Machine

```
                    move_to() / plan_route()
     [IDLE] ─────────────────────────────────> [REQUESTING_PATH]
       ^                                              │
       │                                         path received
       │                                              │
       │                                              v
       │                                         [MOVING]
       │                                          │     │
       │         arrival                          │     │ stuck detected
       │         ┌────────────────────────────────┘     │
       │         v                                      v
       │    [ARRIVED]                               [STUCK]
       │         │                                    │ recovery action
       │         │ auto-reset                         v
       │<────────┘                               [MOVING] (retry)
       │
       │         max stuck attempts
       │<────── [FAILED]

     Any state ──stop()──> [IDLE]
```

### State Transitions

| From | To | Trigger |
|:-----|:---|:--------|
| `idle` | `requesting_path` | `move_to()` or `plan_route()` called |
| `requesting_path` | `moving` | Path received from SentinelNavServer |
| `requesting_path` | `failed` | Path request failed |
| `moving` | `arrived` | Reached destination (within `final_tolerance`) |
| `arrived` | `idle` | Automatic reset after callback fires |
| `moving` | `stuck` | Stuck detected (insufficient movement) |
| `stuck` | `moving` | Recovery action taken |
| `moving` | `failed` | Max stuck attempts exceeded |
| Any | `idle` | `stop()` called |

---

## Stuck Recovery

When the player hasn't moved far enough (`stuck_distance_min`) during a check interval (`stuck_check_interval`), stuck recovery escalates through these strategies:

| Count | Strategy | Action | Duration |
|:------|:---------|:-------|:---------|
| 1 | **Jump** | `core.input.jump()` | Instant |
| 2 | **Probe & Repath** | Ray-probe for doodad; if hit, add avoidance zone and repath. If no hit, fall back to strafe. | Varies |
| 3 | **Strafe + Jump** | Random left/right strafe | 0.5s then jump |
| 4 | **Backward + Jump** | Move backward | 1.0s then jump |
| 5 | **Zone & Repath** | Add avoidance zone at player position, request fresh path | Async |
| &ge; `max_stuck_attempts` (6) | **Fail** | Set state to `"failed"`, fire callback with error | &mdash; |

### Stuck Detection Details

- Checked every `stuck_check_interval` seconds (default: 0.25s)
- Compares distance moved since last check against `stuck_distance_min` (default: 0.1 yards)
- **Skipped** while the player is casting or channeling a spell
- Counter resets to 0 when sufficient movement is detected

### Repath Behavior

When stuck recovery triggers a repath:
1. Stops current path
2. Requests a new path from current position to original destination
3. Uses corridor pathfinding if indoors
4. Includes avoidance zones if Obstacle has detected obstacles
5. Resets stuck counter on successful repath

---

## Indoor Corridor Adaptation

When `use_corridor_indoor = true` and the player is in a dungeon/raid zone:

1. `move_to()` uses `find_path_corridor` instead of `find_path`
2. Corridor width data is stored and accessible via `get_corridor_widths()`
3. Waypoint tolerance is automatically reduced for narrow passages:
   - Set to **40% of the minimum corridor width**
   - Minimum of **1.0 yards**
   - Applied to both waypoint tolerance and final tolerance
   - Prevents overshooting in tight corridors

**Indoor detection:** Uses `Navigation.is_indoor()` which checks the current UiMapID against a built-in table of dungeon/raid zones (see [Constants Reference](/reference/constants#indoor_ui_maps)).

---

## Proactive Obstacle Detection

When an Obstacle module is attached and `proactive_obstacle_check = true`:

1. Every `proactive_obstacle_interval` seconds (default: 1.5s) during movement, scans upcoming waypoint segments for doodad collisions
2. Uses `Obstacle:probe_path_ahead(remaining_waypoints)` with `core.graphics.trace_line` to check for blocked segments
3. If an obstacle is detected:
   - Adds an avoidance zone to the Obstacle module
   - Triggers a repath via `find_path_avoid()` to route around it
4. **Reactive fallback:** On the 2nd stuck recovery attempt, probes forward from the player's position. If an obstacle is found, adds a zone and repaths immediately.

This is fully automatic when using the Client &mdash; the Client wires the Obstacle into Movement during construction.

---

## Casting Deferral

If the player is casting or channeling a spell when `move_to()` is called:

1. Movement request is stored as pending (`{ target, callback, opts }`)
2. On each `update()`, checks if the cast/channel has ended
3. When the cast ends, automatically retries the `move_to()` call
4. Original callback and options are preserved

This prevents interrupting spell casts with movement commands.

---

## Path Validation

During movement, paths are periodically validated to detect navmesh changes or accumulated drift:

### Periodic Check

- Runs every `path_check_interval` seconds (default: 5.0s)
- Only validates if 3+ waypoints remain
- Downsamples to ~10 evenly-spaced waypoints when more than 12 remain (reduces query size)
- Uses `Navigation:check_path()` to verify navmesh walkability
- If an invalid segment is detected &rarr; triggers a **soft repath** from current position
- Logs the invalid segment index for debugging

### Soft Repath

A "soft repath" does **not** stop movement &mdash; the player continues walking while the new path is fetched. A `_validity_repath_pending` guard prevents multiple concurrent soft repaths. If the path is exhausted while a soft repath is pending, movement stops to wait for the new path.

---

## Deviation Monitoring

Movement continuously monitors whether the player has drifted too far from the planned path:

### Detection Algorithm

1. Runs every `deviation_check_interval` seconds (default: 1.0s)
2. Searches **backwards** up to 60 segments from `_path_index` to find the nearest path segment
3. Uses 3D point-to-segment distance calculation (via `Helpers.point_to_segment_distance`)
4. Early exit if distance < 1.0 yard (on path)

### Vertical Drift Check

- If vertical distance exceeds `deviation_vertical_threshold` (default: 2.0 yards) &rarr; triggers repath

### Lateral Drift Check

- **Indoor (corridor):** Threshold = `corridor_width[segment] * deviation_corridor_factor` (default factor: 0.75)
- **Outdoor:** Threshold = fixed `deviation_threshold` (default: 2.0 yards)
- If lateral distance exceeds threshold &rarr; triggers repath

### Guards

- **Cooldown:** `repath_cooldown` (default: 0.1s) minimum between repaths
- **Max repaths:** `max_deviation_repaths` (default: 5) consecutive repaths before stopping
- **Unstuck phase:** Deviation monitoring is disabled during stuck recovery

---

## Path Options Building

### `_build_path_opts` (Internal)

Constructs server query parameters from the current config:

| Parameter | Source | Notes |
|:----------|:-------|:------|
| `smoothing` | `"chaikin"` when `smoothing=true`, else `"none"` | |
| `optimize` | Config `optimize` | |
| `anti_detection` | Config `anti_detection` | |
| `max_deviation` | Config `max_deviation` | |
| `allow_partial` | Config `allow_partial` | |
| `filter_ground` | Config `filter_ground` | |
| `filter_water` | Config `filter_water` | |
| `filter_lava` | Config `filter_lava` | |
| `wall_clearance` | Config `wall_clearance` | Only included if > 0 |
| `smooth_iterations` | Config `smooth_iterations` | |
| `smooth_samples` | Config `smooth_samples` | |
| `smooth_ratio` | Config `smooth_ratio` | |

### `_build_corridor_opts` (Internal)

Same as `_build_path_opts` minus `anti_detection` and `max_deviation`, plus:

| Parameter | Source |
|:----------|:-------|
| `probe_distance` | Config `corridor_probe_dist` |

---

## Dynamic Speed

When `dynamic_speed` is enabled, Movement scales several parameters based on the player's actual movement speed relative to `BASE_RUN_SPEED` (7.0 yd/s):

### Computed Values

| Value | Formula | Clamped Range |
|:------|:--------|:-------------|
| Look distance | `cur_speed * 0.45` | 5.0 &ndash; 12.0 |
| Tolerance scale | `0.85 + ratio * 0.20` | 0.90 &ndash; `max_tolerance_scale` |
| Turn speed | `0.05 * ratio` | 0.05 &ndash; 0.25 |

### Ramp Guard

When the vertical distance between the player and the active waypoint exceeds `ramp_z_delta` (default: 1.2 yards):
- Tolerance is clamped to `ramp_tolerance` (default: 1.8 yards)
- Look distance is clamped to `ramp_look_distance` (default: 6.0 yards)

This prevents overshooting on slopes and ramps.

### Throttle

Dynamic speed only recalculates when the player's speed changes by more than **5%** since the last application, preventing per-frame calculation churn.
