# ObstacleModule API Reference

Doodad collision detection via `core.graphics.trace_line` ray probing, with avoidance zone memory. Detected obstacles are stored as zones and fed to [NavigationClient:find_path_avoid()](NavigationClient.md#find_path_avoid) for rerouting.

ObstacleModule has two probing modes, both driven by [MovementModule](MovementModule.md):

- **Proactive:** Scans upcoming waypoint segments on a timer during movement (default every 1.5s)
- **Reactive:** Probes forward from the player's position when stuck recovery triggers (2nd attempt)

## Table of Contents

- [Constructor](#constructor)
- [Probing](#probing)
  - [probe_forward](#probe_forward)
  - [probe_segment](#probe_segment)
  - [probe_path_ahead](#probe_path_ahead)
- [Zone Management](#zone-management)
  - [add_zone](#add_zone)
  - [prune](#prune)
  - [clear](#clear)
  - [get_avoidance_zones](#get_avoidance_zones)
  - [get_zone_count](#get_zone_count)
- [Configuration](#configuration)
  - [Constructor Config](#constructor-config)
  - [update_config](#update_config)
- [Update Loop](#update-loop)
- [Integration with MovementModule](#integration-with-movementmodule)
- [How Ray Probing Works](#how-ray-probing-works)

---

## Constructor

### `ObstacleModule:new(config?) -> ObstacleModule`

Create a new obstacle detection instance.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `config` | table | no | Configuration overrides (see [Constructor Config](#constructor-config)) |

**Example:**
```lua
local obstacle = _G.NavLib.ObstacleModule:new({
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

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `player_pos` | vec3 | yes | Current player position |
| `target_pos` | vec3 | yes | Direction to probe toward (typically the next waypoint) |

**Returns:** Approximate hit position `{x, y, z}` if any ray hits an obstacle, or `nil` if clear.

**Behavior:**
1. Computes a 2D heading from player to target (Z ignored for direction)
2. Raises the ray origin by `probe_height_offset` yards above ground to avoid false hits
3. Casts 3 rays of length `probe_distance`: center, left (−spread), right (+spread)
4. If any ray is blocked, returns the midpoint along that ray as the approximate obstacle center
5. Logs the hit position for debugging

**Used by:** MovementModule's reactive stuck handler (2nd stuck attempt)

---

### probe_segment

```lua
obstacle:probe_segment(pos_a, pos_b) -> table|nil
```

Probe along a single waypoint segment A→B for doodad collisions. Casts a center ray plus two spread rays at `±lookahead_spread_deg`.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `pos_a` | vec3 | yes | Start of segment |
| `pos_b` | vec3 | yes | End of segment |

**Returns:** Approximate obstacle center `{x, y, z}` (midpoint of segment) if any ray is blocked, or `nil` if clear.

**Behavior:**
1. Raises both endpoints by `lookahead_height_offset` yards
2. Casts center ray from A to B
3. If clear, casts left and right spread rays from A at `±lookahead_spread_deg` off the segment heading
4. Returns the segment midpoint as the obstacle estimate on first hit

---

### probe_path_ahead

```lua
obstacle:probe_path_ahead(waypoints, max_segments?) -> hit_pos, segment_index
```

Probe upcoming waypoint segments for obstacles. Iterates through the first N segments and returns the first collision found.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `waypoints` | vec3[] | yes | Remaining waypoints (at least 2) |
| `max_segments` | number | no | Max segments to check (default: `lookahead_segments` config) |

**Returns:**

| Return | Type | Description |
|--------|------|-------------|
| `hit_pos` | table\|nil | First obstacle found `{x, y, z}`, or nil if clear |
| `segment_index` | number\|nil | 1-based index of the segment with the hit |

**Example:**
```lua
local remaining = simple_movement:get_remaining_waypoints()
local hit, seg_idx = obstacle:probe_path_ahead(remaining, 3)
if hit then
    obstacle:add_zone(hit)
    -- Trigger repath with avoidance
end
```

**Used by:** MovementModule's proactive obstacle check (every 1.5s during movement)

---

## Zone Management

### add_zone

```lua
obstacle:add_zone(pos, radius?)
```

Add an avoidance zone at the given position. Zones are remembered and passed to NavBuddy's `/path-avoid` endpoint for rerouting.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `pos` | table | yes | Hit position `{x, y, z}` from a probe |
| `radius` | number | no | Override avoidance radius (default: `avoidance_radius` config) |

**Behavior:**
- **Deduplication:** Won't add a zone if one already exists within `avoidance_radius` of the position
- **Cap enforcement:** If adding exceeds `max_zones`, evicts the oldest zone first (FIFO)
- Stores the zone with: position, radius, cost multiplier (`avoidance_cost`), and creation timestamp

---

### prune

```lua
obstacle:prune(player_pos?)
```

Remove expired or distant zones. Should be called periodically (e.g., on repath).

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `player_pos` | vec3 | no | Player position for distance-based pruning |

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

Returns the current avoidance zones for passing to [`find_path_avoid()`](NavigationClient.md#find_path_avoid).

**Returns:** Array of zone tables:
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

## Configuration

### Constructor Config

All config fields with their defaults:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `avoidance_cost` | number | `5.0` | Cost multiplier for avoidance zones (higher = more strongly avoided) |
| `avoidance_radius` | number | `3.0` | Radius in yards around each detected obstacle |
| `zone_ttl` | number | `120.0` | Seconds before zones auto-expire |
| `zone_prune_dist` | number | `100.0` | Yards — remove zones farther than this from player |
| `max_zones` | number | `5` | Maximum remembered zones (NavBuddy supports up to 20) |
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

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `overrides` | table | yes | Key-value pairs to merge into config |

**Example:**
```lua
obstacle:update_config({
    avoidance_radius = 5.0,
    max_zones = 10,
})
```

---

## Update Loop

```lua
obstacle:update()
```

No-op method for compatibility with module update loops. Probing is not driven by `update()` — it is triggered by MovementModule:

- **Proactive probing** is called by `MovementModule:_check_proactive_obstacles()` on a timer
- **Reactive probing** is called by `MovementModule:_unstuck_probe_and_repath()` during stuck recovery

When using [NavLibFacade](NavLibFacade.md), `obstacle:update()` is called automatically by `facade:update()`.

---

## Integration with MovementModule

ObstacleModule is designed to work with MovementModule. The wiring is:

```lua
-- Manual wiring
local obstacle = ObstacleModule:new()
movement:set_obstacle_module(obstacle)

-- Or automatic via NavLibFacade
local nav = _G.NavLib.create()  -- wires everything internally
```

Once wired:

1. **Proactive scanning** (every 1.5s during movement):
   - MovementModule calls `obstacle:probe_path_ahead(remaining_waypoints)`
   - If hit found: calls `obstacle:add_zone(hit_pos)`, then repaths with `find_path_avoid()`

2. **Reactive scanning** (on 2nd stuck attempt):
   - MovementModule calls `obstacle:probe_forward(player_pos, next_waypoint)`
   - If hit found: calls `obstacle:add_zone(hit_pos)`, then repaths with `find_path_avoid()`

3. **Zone data flows to pathfinding:**
   - `obstacle:get_avoidance_zones()` returns zones for `NavigationClient:find_path_avoid()`
   - NavBuddy computes paths that avoid the zones with the specified cost multiplier

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

Spread: ±probe_spread_deg (default: 20°)
Height: origin raised by probe_height_offset (default: 1.0 yd)
```

**Proactive probing** (`probe_segment`):
```
        [Left Ray]
       /
  WP_A ──── [Center Ray] ────> WP_B
       \
        [Right Ray]

Spread: ±lookahead_spread_deg (default: 15°)
Height: both endpoints raised by lookahead_height_offset (default: 1.5 yd)
```

The narrower spread on proactive rays (15° vs 20°) reduces false positives on straight segments while still catching obstacles slightly off the direct path.
