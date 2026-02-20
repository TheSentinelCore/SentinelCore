---
title: State Machine
layout: default
parent: Reference
nav_order: 1
---

# Movement State Machine
{: .no_toc }

Detailed reference for Movement's state machine, stuck recovery escalation, deviation monitoring, path validation, and dynamic speed scaling.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## States

| State | Description |
|:------|:------------|
| `"idle"` | Not moving. Default state. |
| `"requesting_path"` | Waiting for a path response from SentinelNavServer. |
| `"moving"` | Actively following waypoints toward the destination. |
| `"stuck"` | Stuck detected; recovery action in progress. |
| `"arrived"` | Reached the final destination within `final_tolerance`. |
| `"failed"` | Movement failed after exhausting all recovery attempts. |

---

## State Diagram

```
                       move_to() / plan_route()
        [IDLE] ──────────────────────────────────> [REQUESTING_PATH]
          ^                                               │
          │                                          path received
          │                                     ┌────────────┤
          │                                     │            │
          │                                     │     path request failed
          │                                     │            │
          │                                     v            v
          │                                  [MOVING]    [FAILED]
          │                                   │    │         │
          │      arrival (within              │    │         │
          │       final_tolerance)            │    │ stuck   │
          │      ┌────────────────────────────┘    │ detect  │
          │      v                                  v         │
          │   [ARRIVED]                         [STUCK]       │
          │      │                                │           │
          │      │ auto-reset                     │ recovery  │
          │      │ (after callback)               │ action    │
          │<─────┘                                v           │
          │                                   [MOVING]        │
          │                                   (retry)         │
          │                                     │             │
          │                          max stuck exceeded       │
          │<──────────────────────────────────────────────────┘
          │
          │
        Any state ──── stop() ────> [IDLE]
```

---

## State Transitions

| From | To | Trigger | Notes |
|:-----|:---|:--------|:------|
| `idle` | `requesting_path` | `move_to()` or `plan_route()` called | Path request sent to SentinelNavServer |
| `requesting_path` | `moving` | Path received | Waypoint traversal begins |
| `requesting_path` | `failed` | Path request failed after all retries | Callback fired with error |
| `moving` | `arrived` | Player within `final_tolerance` of destination | Arrival callback fired |
| `arrived` | `idle` | Automatic | Resets immediately after callback fires |
| `moving` | `stuck` | Stuck detected | Insufficient movement during check interval |
| `stuck` | `moving` | Recovery action taken | Stuck counter incremented |
| `moving` | `failed` | Max stuck attempts exceeded | `max_stuck_attempts` reached (default: 6) |
| Any | `idle` | `stop()` called | All state cleared |

---

## Events Fired on Transitions

| Transition | Events Fired |
|:-----------|:-------------|
| Any &rarr; Any | `"state_change"` with `{ from = old_state, to = new_state }` |
| Any &rarr; `"arrived"` | `"state_change"` + `"arrived"` |
| Any &rarr; `"stuck"` | `"state_change"` + `"stuck"` |
| Any &rarr; `"failed"` | `"state_change"` + `"failed"` |

---

## Stuck Recovery Escalation

When the player hasn't moved `stuck_distance_min` yards (default: 0.1) within `stuck_check_interval` seconds (default: 0.25s), stuck recovery escalates:

### Level 1: Jump

| Property | Value |
|:---------|:------|
| **Stuck count** | 1 |
| **Action** | `core.input.jump()` |
| **Duration** | Instant |
| **Purpose** | Overcome small terrain bumps |

### Level 2: Probe & Repath

| Property | Value |
|:---------|:------|
| **Stuck count** | 2 |
| **Action** | Ray-probe for doodad obstacle toward next waypoint |
| **If hit** | Add avoidance zone at obstacle, repath via `find_path_avoid()` |
| **If no hit** | Fall back to strafe (random left/right, 0.5s + jump) |
| **Purpose** | Detect and route around invisible doodad collisions |

### Level 3: Strafe + Jump

| Property | Value |
|:---------|:------|
| **Stuck count** | 3 |
| **Action** | Random left or right strafe |
| **Duration** | 0.5s strafe, then jump |
| **Purpose** | Lateral displacement to unstick from narrow obstacles |

### Level 4: Backward + Jump

| Property | Value |
|:---------|:------|
| **Stuck count** | 4 |
| **Action** | Move backward |
| **Duration** | 1.0s backward, then jump |
| **Purpose** | Retreat from dead-end or wedged position |

### Level 5: Zone & Repath

| Property | Value |
|:---------|:------|
| **Stuck count** | 5 |
| **Action** | Add avoidance zone at current player position, request fresh path |
| **Duration** | Async (path request) |
| **Purpose** | Mark current position as problematic and find alternate route |

### Level 6+: Fail

| Property | Value |
|:---------|:------|
| **Stuck count** | &ge; `max_stuck_attempts` (default: 6) |
| **Action** | Set state to `"failed"`, fire callback with error |
| **Purpose** | Give up after all recovery strategies exhausted |

### Stuck Detection Details

| Property | Value |
|:---------|:------|
| Check interval | `stuck_check_interval` (default: 0.25s) |
| Distance threshold | `stuck_distance_min` (default: 0.1 yards) |
| Skipped when | Player is casting or channeling |
| Counter reset | When sufficient movement detected |
| Repath resets | Stuck counter resets on successful repath |

---

## Deviation Monitoring

Movement continuously monitors whether the player has drifted from the planned path.

### Detection Algorithm

```
Every deviation_check_interval (1.0s):
    │
    ├── Search backwards from _path_index (up to 60 segments)
    │   └── Find nearest path segment via 3D point-to-segment distance
    │       └── Early exit if distance < 1.0 yd (on path)
    │
    ├── Check vertical drift:
    │   └── If |vertical_distance| > deviation_vertical_threshold (2.0 yd)
    │       └── Trigger repath
    │
    └── Check lateral drift:
        ├── Indoor: threshold = corridor_width[segment] * corridor_factor (0.75)
        └── Outdoor: threshold = deviation_threshold (2.0 yd)
            └── If lateral_distance > threshold
                └── Trigger repath
```

### Deviation Guards

| Guard | Default | Description |
|:------|:--------|:------------|
| `repath_cooldown` | 0.1s | Minimum time between repaths |
| `max_deviation_repaths` | 5 | Max consecutive deviation repaths |
| Unstuck phase | &mdash; | Deviation monitoring disabled during stuck recovery |

---

## Path Validation

Periodic checks that remaining waypoints are still walkable on the navmesh.

### Validation Flow

```
Every path_check_interval (5.0s) during movement:
    │
    ├── Skip if fewer than 3 waypoints remain
    │
    ├── Downsample remaining waypoints:
    │   └── If > 12 remaining: sample ~10 evenly-spaced waypoints
    │   └── Else: use all remaining waypoints
    │
    ├── Send to nav_client:check_path()
    │
    └── On result:
        ├── If valid: continue normally
        └── If invalid:
            ├── Log invalid segment index
            └── Trigger soft repath from current position
```

### Soft Repath

A soft repath differs from a hard repath:

| Property | Soft Repath | Hard Repath (stuck recovery) |
|:---------|:------------|:-----------------------------|
| **Movement** | Player continues walking | Movement stops |
| **Guard** | `_validity_repath_pending` prevents concurrent | None |
| **Path exhaustion** | Stops movement to wait for new path | N/A |
| **Trigger** | Path validation failure | Stuck recovery level 4+ |

---

## Dynamic Speed Scaling

When `dynamic_speed` is enabled, Movement adapts parameters based on the player's actual speed.

### Speed Ratio

```
ratio = current_speed / BASE_RUN_SPEED    (BASE_RUN_SPEED = 7.0 yd/s)
```

### Computed Parameters

| Parameter | Formula | Clamped Range |
|:----------|:--------|:-------------|
| **Look distance** | `current_speed * 0.45` | 5.0 &ndash; 12.0 yards |
| **Tolerance scale** | `0.85 + ratio * 0.20` | 0.90 &ndash; `max_tolerance_scale` (1.20) |
| **Tolerance bonus** | `max_tolerance_bonus` | 0.0 &ndash; 2.0 yards |
| **Turn speed** | `0.05 * ratio` | 0.05 &ndash; 0.25 |

### Ramp Guard

Prevents overshooting on elevation changes:

```
If |active_waypoint.z - player.z| >= ramp_z_delta (1.2 yd):
    tolerance = min(tolerance, ramp_tolerance)      -- default: 1.8 yd
    look_distance = min(look_distance, ramp_look)   -- default: 6.0 yd
```

### Throttle

Dynamic speed recalculates **only when the player's speed changes by more than 5%** since the last computation, preventing unnecessary per-frame calculations.

---

## Indoor Corridor Tolerance

When indoors, waypoint tolerance is dynamically reduced based on corridor width:

```
tolerance = max(1.0, min_corridor_width * 0.4)
```

This applies to both `waypoint_tolerance` and `final_tolerance`, overriding config defaults. The tolerance resets to config values when:
- `stop()` is called
- A new outdoor path is started
- The corridor width data is cleared

---

## Casting Deferral

```
move_to() called while casting:
    │
    ├── Store as pending: { target, callback, opts }
    │
    └── Each update() frame:
        ├── Check: player:is_casting_spell() or player:is_channelling_spell()
        ├── If still casting: skip
        └── If cast ended: re-dispatch move_to(target, callback, opts)
```

The original callback and options are preserved through the deferral.

---

## Route Leg Execution

When `plan_route()` is active, Movement follows each leg of the TSP-optimized route:

```
plan_route(nodes)
    │
    ├── Send to nav_client:find_route_tsp(nodes)
    │
    └── On result:
        ├── Store route data (waypoints, leg_boundaries, visit_order)
        ├── Start leg 1: follow_path(leg_1_waypoints)
        │
        └── On leg arrival:
            ├── Fire callback({ type = "leg_complete", leg = N, total = M })
            ├── If more legs: start next leg
            └── If last leg: fire callback({ type = "route_complete" })
```

### Replanning

`replan()` collects remaining unvisited nodes and re-requests a TSP route:

```
replan()
    │
    ├── Collect remaining nodes (current leg + future legs)
    ├── stop() current movement
    │
    ├── If < 2 nodes remain: fail
    └── Else: plan_route(remaining_nodes, original_callback, original_opts)
```
