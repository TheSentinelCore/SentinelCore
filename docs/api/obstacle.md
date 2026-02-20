---
title: Obstacle
layout: default
parent: API Reference
nav_order: 4
---

# Obstacle API
{: .no_toc }

Doodad collision detection via `core.graphics.trace_line` ray probing, with avoidance zone memory. Detected obstacles are stored as zones and fed to [Navigation:find_path_avoid()](/api/navigation#find_path_avoid) for rerouting.
{: .fs-6 .fw-300 }

{: .note }
Consumers should access the shared Obstacle module via `_G.SentinelNavClient.client.obstacle`. The shared instance is created and configured by SentinelNavClient.

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## Overview

Obstacle has two probing modes, both driven by [Movement](/api/movement):

| Mode | Trigger | Description |
|:-----|:--------|:------------|
| **Proactive** | Timer during movement (default: every 1.5s) | Scans upcoming waypoint segments for doodad collisions |
| **Reactive** | 2nd stuck recovery attempt | Probes forward from the player's position toward the next waypoint |

Both modes use `core.graphics.trace_line(origin, target, flags)` with `collision_flags = 0x00000001` (DoodadCollision).

---

## Constructor

### `Obstacle:new(config?) -> Obstacle`

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `config` | table | no | Configuration overrides (see [Configuration](/configuration#obstacle-settings)) |

```lua
local obstacle = Obstacle:new({
    avoidance_radius = 3.0,
    max_zones = 5,
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
|:------|:-----|:---------|:------------|
| `player_pos` | vec3 | yes | Current player position |
| `target_pos` | vec3 | yes | Direction to probe toward (typically the next waypoint) |

**Returns:** Approximate hit position `{x, y, z}` if any ray hits an obstacle, or `nil` if clear.

**Behavior:**

1. Computes a 2D heading from player to target (Z ignored for direction)
2. Raises the ray origin by `probe_height_offset` yards above ground
3. Casts 3 rays of length `probe_distance`:
   - Center ray (straight ahead)
   - Left ray (-`probe_spread_deg`)
   - Right ray (+`probe_spread_deg`)
4. If any ray is blocked, returns the midpoint along that ray as the approximate obstacle center (at `probe_distance * 0.5`)

**Ray diagram:**

```
        [Left Ray]   (-probe_spread_deg)
       /
Player ──── [Center Ray] ────> (probe_distance yards)
       \
        [Right Ray]  (+probe_spread_deg)

Spread: +/-probe_spread_deg (default: 20°)
Height: origin raised by probe_height_offset (default: 1.0 yd)
```

**Used by:** Movement's reactive stuck handler (2nd stuck attempt)

---

### probe_segment

```lua
obstacle:probe_segment(pos_a, pos_b) -> table|nil
```

Probe along a single waypoint segment A&rarr;B for doodad collisions. Casts a center ray plus two spread rays at `+/-lookahead_spread_deg`.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `pos_a` | vec3 | yes | Start of segment |
| `pos_b` | vec3 | yes | End of segment |

**Returns:** Approximate obstacle center `{x, y, z}` (midpoint of segment) if any ray is blocked, or `nil` if clear.

**Details:**
- Both endpoints are raised by `lookahead_height_offset` yards above their Z coordinate
- Segments shorter than **0.5 yards** are skipped (too short for meaningful probing)
- The narrower spread (15° vs 20°) reduces false positives on straight segments while still catching obstacles slightly off the direct path

**Ray diagram:**

```
        [Left Ray]   (-lookahead_spread_deg)
       /
  WP_A ──── [Center Ray] ────> WP_B
       \
        [Right Ray]  (+lookahead_spread_deg)

Spread: +/-lookahead_spread_deg (default: 15°)
Height: both endpoints raised by lookahead_height_offset (default: 1.5 yd)
```

---

### probe_path_ahead

```lua
obstacle:probe_path_ahead(waypoints, max_segments?) -> hit_pos, segment_index
```

Probe upcoming waypoint segments for obstacles. Iterates through the first N segments and returns the first collision found.

| Param | Type | Required | Description |
|:------|:-----|:---------|:------------|
| `waypoints` | vec3[] | yes | Remaining waypoints (at least 2) |
| `max_segments` | number | no | Max segments to check (default: `lookahead_segments` config) |

**Returns:**

| Return | Type | Description |
|:-------|:-----|:------------|
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
|:------|:-----|:---------|:------------|
| `pos` | table | yes | Hit position `{x, y, z}` from a probe |
| `radius` | number | no | Override avoidance radius (default: `avoidance_radius` config) |

**Behavior:**

- **Deduplication:** Won't add a zone if one already exists within `avoidance_radius` of the position
- **Cap enforcement:** If adding would exceed `max_zones`, the oldest zone is evicted first (FIFO)
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

| Criterion | Default |
|:----------|:--------|
| Zone age exceeds `zone_ttl` | 120 seconds |
| Zone distance from `player_pos` exceeds `zone_prune_dist` | 100 yards |

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

## Update Loop

```lua
obstacle:update()
```

**No-op method** for compatibility with module update loops. Probing is **not** driven by `update()` &mdash; it is triggered by Movement:

- **Proactive probing** is called by `Movement:_check_proactive_obstacles()` on a timer
- **Reactive probing** is called by `Movement:_unstuck_probe_and_repath()` during stuck recovery

When using the Client, `obstacle:update()` is called automatically by `client:update()` (but it does nothing).

---

## Configuration

All config fields with their defaults:

| Field | Type | Default | Range | Description |
|:------|:-----|:--------|:------|:------------|
| `avoidance_cost` | number | `100.0` | 1.0 &ndash; 100.0 | Cost multiplier for avoidance zones |
| `avoidance_radius` | number | `3.0` | 1.0 &ndash; 10.0 | Radius in yards around each detected obstacle |
| `zone_ttl` | number | `120.0` | 30.0 &ndash; 300.0 | Seconds before zones auto-expire |
| `zone_prune_dist` | number | `100.0` | 50.0 &ndash; 500.0 | Yards &mdash; remove zones farther than this from player |
| `max_zones` | number | `5` | 1 &ndash; 20 | Maximum remembered zones (SentinelNavServer supports up to 20) |
| `collision_flags` | number | `0x00000001` | &mdash; | Trace line flags (DoodadCollision, hardcoded) |
| `probe_distance` | number | `8.0` | 2.0 &ndash; 20.0 | Reactive probe distance in yards |
| `probe_spread_deg` | number | `20.0` | 5.0 &ndash; 45.0 | Reactive probe spread angle in degrees |
| `probe_height_offset` | number | `1.0` | 0.5 &ndash; 5.0 | Yards to raise reactive probe origin above ground |
| `lookahead_height_offset` | number | `1.5` | 0.5 &ndash; 5.0 | Yards to raise proactive rays above waypoint Z |
| `lookahead_spread_deg` | number | `15.0` | 5.0 &ndash; 45.0 | Proactive spread angle in degrees |
| `lookahead_segments` | number | `3` | 1 &ndash; 10 | Default number of upcoming segments to scan |

### update_config

```lua
obstacle:update_config(overrides)
```

Update configuration at runtime. Only provided keys are changed.

{: .note }
This is called by SentinelNavClient's UI sync system every render frame. Consumer calls would be overwritten. Use SentinelNavClient's Settings UI to change obstacle settings.

---

## Integration with Movement

Obstacle is designed to work with Movement. The wiring is automatic when using the Client:

```lua
-- Automatic via Client (recommended)
local client = _G.SentinelNavClient.client  -- wires everything internally

-- Manual wiring (advanced)
local obstacle = Obstacle:new()
movement:set_obstacle_module(obstacle)
```

### Data Flow

Once wired, the integration works as follows:

#### 1. Proactive Scanning (every 1.5s during movement)

```
Movement (timer fires)
    │
    ├── obstacle:probe_path_ahead(remaining_waypoints)
    │       └── trace_line() × 3 rays per segment × lookahead_segments
    │
    ├── If hit found:
    │       ├── obstacle:add_zone(hit_pos)
    │       └── nav_client:find_path_avoid(start, dest, zones, callback)
    │
    └── If clear: continue normally
```

#### 2. Reactive Scanning (on 2nd stuck attempt)

```
Movement (stuck count = 2)
    │
    ├── obstacle:probe_forward(player_pos, next_waypoint)
    │       └── trace_line() × 3 rays from player
    │
    ├── If hit found:
    │       ├── obstacle:add_zone(hit_pos)
    │       └── Repath with avoidance
    │
    └── If no hit: fall back to strafe recovery
```

#### 3. Zone Data Flows to Pathfinding

```
obstacle:get_avoidance_zones()
    │
    └── Returns zones → passed to nav_client:find_path_avoid()
            │
            └── SentinelNavServer computes path avoiding zones
                    with specified cost multiplier
```

---

## How Ray Probing Works

Both probing methods use `core.graphics.trace_line(origin, target, flags)`:

| Return Value | Meaning |
|:-------------|:--------|
| `true` | Ray is **clear** (no collision) |
| `false` | Ray is **blocked** (doodad hit) |

### Reactive vs Proactive Comparison

| Property | Reactive (`probe_forward`) | Proactive (`probe_segment`) |
|:---------|:---------------------------|:---------------------------|
| **Trigger** | Stuck recovery (2nd attempt) | Timer during movement |
| **Origin** | Player position | Waypoint A |
| **Target** | Next waypoint direction | Waypoint B |
| **Spread** | &plusmn;20&deg; (wider) | &plusmn;15&deg; (narrower) |
| **Height offset** | 1.0 yd above ground | 1.5 yd above waypoint Z |
| **Ray count** | 3 (center + L/R) | 3 (center + L/R) |
| **Hit result** | Midpoint along ray | Midpoint of segment |
| **Purpose** | Detect obstacle blocking player | Detect obstacle on upcoming path |

The narrower spread on proactive rays (15&deg; vs 20&deg;) reduces false positives on straight segments while still catching obstacles slightly off the direct path.
