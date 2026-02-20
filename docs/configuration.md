---
title: Configuration
layout: default
nav_order: 4
---

# Configuration
{: .no_toc }

All 40+ settings with defaults, valid ranges, and descriptions. All settings are managed by SentinelNavClient's built-in UI.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## How Settings Work

SentinelNavClient owns **all** navigation settings via its built-in settings UI. The flow is:

1. ~40 menu elements in the settings window (persisted across sessions via `core.menu.*`)
2. `sync_to_client()` reads all element values every render frame
3. Calls `client:update_config()` with the resolved values
4. Movement and Obstacle modules update their internal config tables

**Consumers should NOT call `update_config()` directly** &mdash; their changes will be overwritten on the next render frame by SentinelNavClient's sync.

To change navigation settings, use the **SentinelNavClient Settings UI** (toggled via the "SentinelNavClient" button in the Sylvannas menu).

### Settings Ownership

| Owner | Settings | Where Configured |
|:------|:---------|:-----------------|
| **SentinelNavClient** | All movement, pathfinding, obstacle, and debug settings | SentinelNavClient Settings UI |
| **Consumer plugin** | Domain-specific settings only | Consumer's own UI |

**Example consumer-owned settings (SentinelGather):** gather types (herbs/ores), mount distance threshold, random pause/jump intervals, enemy scan radius, flee health threshold.

---

## Movement Settings

Configured in the **Movement** tab of the settings UI.

### Core Movement

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `waypoint_tolerance` | float | `3.0` | 0.5 &ndash; 10.0 | Yards from a waypoint before advancing to the next one |
| `final_tolerance` | float | `1.5` | 0.5 &ndash; 5.0 | Yards from the final destination to consider "arrived" |
| `anti_detection` | bool | `false` | &mdash; | Use randomized path endpoints (`/path-random`) for anti-detection jitter |
| `max_deviation` | float | `3.0` | 1.0 &ndash; 20.0 | Maximum yards waypoints can deviate during anti-detection randomization |

### Dynamic Speed

When enabled, scales look-ahead distance, tolerance, and turn speed based on the player's actual movement speed relative to base run speed (7.0 yd/s).

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `dynamic_speed` | bool | `false` | &mdash; | Enable dynamic speed scaling |
| `dynamic_speed_max_tolerance_scale` | float | `1.20` | 1.0 &ndash; 2.0 | Maximum tolerance multiplier at high speed |
| `dynamic_speed_max_tolerance_bonus` | float | `0.75` | 0.0 &ndash; 2.0 | Extra tolerance added at high speed (yards) |
| `dynamic_speed_ramp_z_delta` | float | `1.2` | 0.5 &ndash; 5.0 | Z-delta threshold to engage ramp guard (yards) |
| `dynamic_speed_ramp_tolerance` | float | `1.8` | 0.5 &ndash; 5.0 | Max tolerance when ramp guard is active (yards) |
| `dynamic_speed_ramp_look_distance` | float | `6.0` | 2.0 &ndash; 15.0 | Max look distance when ramp guard is active (yards) |

**Ramp guard:** When the vertical distance between the player and the active waypoint exceeds `ramp_z_delta`, tolerance and look distance are clamped to prevent overshooting on slopes and ramps.

**Throttle:** Dynamic speed only recalculates when the player's speed changes by more than 5%, preventing per-frame calculation churn.

### Stuck Recovery

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `stuck_check_interval` | float | `0.25` | 0.25 &ndash; 5.0 | Seconds between stuck checks |
| `stuck_distance_min` | float | `0.1` | 0.1 &ndash; 2.0 | Minimum yards moved to not be considered "stuck" |
| `max_stuck_attempts` | int | `6` | 1 &ndash; 10 | Max recovery attempts before movement fails |

See [Stuck Recovery](/reference/state-machine#stuck-recovery) for the full escalation sequence.

### Path Validation & Deviation

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `path_check_interval` | float | `5.0` | 1.0 &ndash; 30.0 | Seconds between periodic path validity checks |
| `deviation_check_interval` | float | `1.0` | 0.1 &ndash; 5.0 | Seconds between path deviation checks |
| `deviation_threshold` | float | `2.0` | 1.0 &ndash; 20.0 | Yards off-path before triggering repath (outdoor) |
| `deviation_vertical_threshold` | float | `2.0` | 0.5 &ndash; 10.0 | Yards vertical drift before triggering repath |
| `deviation_corridor_factor` | float | `0.75` | 0.1 &ndash; 2.0 | Indoor threshold = `corridor_width * factor` |
| `repath_cooldown` | float | `0.1` | 0.1 &ndash; 5.0 | Minimum seconds between deviation-triggered repaths |
| `max_deviation_repaths` | int | `5` | 1 &ndash; 10 | Maximum consecutive deviation repaths before giving up |

### Proactive Obstacle Scanning

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `proactive_obstacle_check` | bool | `true` | &mdash; | Enable proactive obstacle scanning on upcoming path segments |
| `proactive_obstacle_interval` | float | `1.5` | 0.5 &ndash; 5.0 | Seconds between proactive obstacle scans during movement |

### Debug

| Setting | Type | Default | Description |
|:--------|:-----|:--------|:------------|
| `debug_verbose` | bool | `false` | Enable verbose debug logging for movement internals |

---

## Pathfinding Settings

Configured in the **Pathfinding** tab of the settings UI.

### Smoothing

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `smoothing` | bool | `true` | &mdash; | Enable path smoothing (Chaikin algorithm when true, `"none"` when false) |
| `smooth_iterations` | int | `2` | 0 &ndash; 5 | Number of smoothing passes |
| `smooth_samples` | int | `10` | 2 &ndash; 20 | Sample count per smoothing pass |
| `smooth_ratio` | float | `0.9` | 0.1 &ndash; 1.0 | Smoothing interpolation ratio (0.0 = no smoothing, 1.0 = maximum) |

When `smoothing` is enabled, the server-side algorithm is set to `"chaikin"`. SentinelNavServer also supports `"catmull_rom"` and `"bezier"` via direct Navigation API calls.

### Optimization

| Setting | Type | Default | Description |
|:--------|:-----|:--------|:------------|
| `optimize` | bool | `true` | Enable waypoint optimization (reduce redundant waypoints) |
| `allow_partial` | bool | `true` | Accept partial paths when full path is impossible |

### Terrain Cost Filters

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `filter_ground` | float | `1.0` | 0.1 &ndash; 10.0 | Ground polygon traversal cost (1.0 = normal) |
| `filter_water` | float | `10.0` | 0.1 &ndash; 100.0 | Water polygon traversal cost (higher = avoid water) |
| `filter_lava` | float | `100.0` | 0.1 &ndash; 1000.0 | Lava polygon traversal cost (higher = avoid lava) |

### Indoor Corridor Mode

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `use_corridor_indoor` | bool | `true` | &mdash; | Use corridor pathfinding when inside dungeons/raids |
| `corridor_probe_dist` | float | `15.0` | 5.0 &ndash; 30.0 | Corridor width probe distance in yards |

When enabled and the player is in a dungeon/raid zone (detected via `Navigation.is_indoor()`):
- `move_to()` uses `find_path_corridor` instead of `find_path`
- Corridor width data is stored per-waypoint
- Waypoint tolerance is automatically reduced to `max(1.0, min_corridor_width * 0.4)` to prevent overshooting in tight passages

### Wall Clearance

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `wall_clearance_enabled` | bool | `true` | &mdash; | Enable wall clearance in pathfinding |
| `wall_clearance` | float | `1.2` | 0.5 &ndash; 5.0 | Minimum distance from walls in yards |

When `wall_clearance_enabled` is false, a value of `0` is sent to the server (which disables the feature). When enabled, the slider value is sent. Wall clearance must be `> 0` to take effect on the server side.

---

## Obstacle Settings

Configured in the **Obstacles** tab of the settings UI.

### Avoidance Zones

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `avoidance_radius` | float | `3.0` | 1.0 &ndash; 10.0 | Radius in yards around each detected obstacle |
| `avoidance_cost` | float | `100.0` | 1.0 &ndash; 100.0 | Cost multiplier for avoidance zones (higher = more strongly avoided) |
| `max_zones` | int | `5` | 1 &ndash; 20 | Maximum remembered avoidance zones (SentinelNavServer supports up to 20) |
| `zone_ttl` | float | `120.0` | 30.0 &ndash; 300.0 | Seconds before avoidance zones auto-expire |
| `zone_prune_dist` | float | `100.0` | 50.0 &ndash; 500.0 | Yards &mdash; remove zones farther than this from the player |

Zone deduplication: A new zone will not be added if an existing zone is already within `avoidance_radius` of the new position. When the cap is exceeded, the oldest zone is evicted (FIFO).

### Reactive Probing

Used during stuck recovery (2nd attempt). Probes forward from the player toward the next waypoint.

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `probe_distance` | float | `8.0` | 2.0 &ndash; 20.0 | Reactive probe distance from player in yards |
| `probe_spread_deg` | float | `20.0` | 5.0 &ndash; 45.0 | Reactive probe spread angle in degrees (+/- from center) |
| `probe_height_offset` | float | `1.0` | 0.5 &ndash; 5.0 | Yards to raise reactive probe origin above ground |

### Proactive Probing (Look-Ahead)

Scans upcoming waypoint segments on a timer during movement (default: every 1.5s).

| Setting | Type | Default | Range | Description |
|:--------|:-----|:--------|:------|:------------|
| `lookahead_height_offset` | float | `1.5` | 0.5 &ndash; 5.0 | Yards to raise proactive probe rays above waypoint Z |
| `lookahead_spread_deg` | float | `15.0` | 5.0 &ndash; 45.0 | Proactive probe spread angle in degrees |
| `lookahead_segments` | int | `3` | 1 &ndash; 10 | Number of upcoming path segments to scan |

### Hardcoded Values

These values are not exposed in the settings UI:

| Value | Setting | Description |
|:------|:--------|:------------|
| `0x00000001` | `collision_flags` | Trace line flags (`DoodadCollision`) |

---

## Debug & Visualization Settings

Configured in the **Debug** tab of the settings UI.

| Setting | Type | Default | Description |
|:--------|:-----|:--------|:------------|
| `debug_mode` | int | `0` | Active test mode (0 = none, 1&ndash;13 = test modes) |
| `viz_master` | bool | `false` | Master toggle for all 3D visualization |
| `viz_path` | bool | `true` | Show path overlay (future waypoints in blue) |
| `viz_destination` | bool | `true` | Show destination marker (green circle) |
| `viz_obstacles` | bool | `true` | Show obstacle avoidance zones (red circles) |
| `viz_corridor` | bool | `true` | Show corridor width indicators (white) |
| `viz_state` | bool | `true` | Show movement state text overlay |
| `show_advanced` | bool | `false` | Show advanced settings in all tabs |

### Visualization Details

| Element | Color | Cull Distance |
|:--------|:------|:-------------|
| Future path | iOS Blue `rgb(10, 132, 255)` | 300 yards |
| Destination | iOS Green `rgb(48, 209, 88)` | 300 yards |
| Obstacle zones | iOS Red `rgb(255, 69, 58)` | 200 yards |
| State text | Various | 100 yards |
| Corridor | White `rgb(255, 255, 255)` | 250 yards |

All visualization elements are rendered at 2.0 yards above ground level. The stuck state indicator pulses at 4Hz, and the arrival ring expands over 2 seconds.

---

## Menu Element IDs

Every setting has a persistent menu element ID used by `core.menu.*`:

<details markdown="block">
  <summary>Click to expand full ID mapping</summary>

| Menu ID | Setting |
|:--------|:--------|
| `snc_waypoint_tolerance` | Waypoint tolerance |
| `snc_final_tolerance` | Final tolerance |
| `snc_anti_detection` | Anti-detection |
| `snc_max_deviation` | Max deviation |
| `snc_dynamic_speed` | Dynamic speed |
| `snc_dyn_tol_scale` | Dynamic speed max tolerance scale |
| `snc_dyn_tol_bonus` | Dynamic speed max tolerance bonus |
| `snc_dyn_ramp_z` | Dynamic speed ramp Z delta |
| `snc_dyn_ramp_tol` | Dynamic speed ramp tolerance |
| `snc_dyn_ramp_look` | Dynamic speed ramp look distance |
| `snc_stuck_interval` | Stuck check interval |
| `snc_stuck_distance_v2` | Stuck distance minimum |
| `snc_max_stuck` | Max stuck attempts |
| `snc_path_check` | Path check interval |
| `snc_deviation_check_interval` | Deviation check interval |
| `snc_deviation_threshold` | Deviation threshold |
| `snc_deviation_vertical_threshold` | Deviation vertical threshold |
| `snc_deviation_corridor_factor` | Deviation corridor factor |
| `snc_repath_cooldown` | Repath cooldown |
| `snc_max_deviation_repaths` | Max deviation repaths |
| `snc_smoothing` | Smoothing enabled |
| `snc_optimize` | Optimization enabled |
| `snc_allow_partial` | Allow partial paths |
| `snc_filter_ground` | Ground cost filter |
| `snc_filter_water` | Water cost filter |
| `snc_filter_lava` | Lava cost filter |
| `snc_corridor` | Use corridor indoor |
| `snc_corridor_probe` | Corridor probe distance |
| `snc_wall_clearance_en` | Wall clearance enabled |
| `snc_wall_clearance` | Wall clearance distance |
| `snc_smooth_iterations` | Smooth iterations |
| `snc_smooth_samples` | Smooth samples |
| `snc_smooth_ratio` | Smooth ratio |
| `snc_proactive_obstacle` | Proactive obstacle check |
| `snc_obstacle_interval` | Proactive obstacle interval |
| `snc_debug_verbose` | Debug verbose |
| `snc_avoidance_radius` | Avoidance radius |
| `snc_max_zones` | Max zones |
| `snc_zone_ttl` | Zone TTL |
| `snc_avoidance_cost` | Avoidance cost |
| `snc_zone_prune` | Zone prune distance |
| `snc_probe_distance` | Probe distance |
| `snc_probe_spread` | Probe spread |
| `snc_probe_height` | Probe height offset |
| `snc_look_height` | Lookahead height offset |
| `snc_look_spread` | Lookahead spread |
| `snc_look_segments` | Lookahead segments |
| `snc_debug_mode` | Debug mode |
| `snc_viz_master` | Visualization master |
| `snc_viz_path` | Visualize path |
| `snc_viz_destination` | Visualize destination |
| `snc_viz_obstacles` | Visualize obstacles |
| `snc_viz_corridor` | Visualize corridor |
| `snc_viz_state` | Visualize state |
| `snc_show_advanced` | Show advanced |

</details>
