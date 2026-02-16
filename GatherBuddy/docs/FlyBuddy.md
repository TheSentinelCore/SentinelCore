# FlyBuddy (Developer Notes)

## Purpose
`FlyBuddy` is a lightweight flying travel helper used by GatherBuddy when a profile has:
- `requirements.requires_flying = true`

It is not a full 3D air navmesh system.  
It drives flight using:
- profile waypoints
- cruise altitude logic
- forward collision probing
- terrain height safety floor

## Current Behavior
When traveling to a waypoint, FlyBuddy:
1. Builds a short flight path (1-3 points) with optional cruise points.
2. Applies vertical control (`move_up_start` / `move_down_start`) to track desired altitude.
3. Probes ahead with 3 rays (center/left/right) using `core.graphics.trace_line`.
4. If blocked, temporarily increases altitude target.
5. Samples navmesh ground height (`nav_client:get_height`) and enforces minimum terrain clearance during cruise.

## Main Config Keys
Defined in `GatherBuddy/modules/FlyBuddy.lua` constructor `config`:

- `cruise_altitude` (default `22.0`)
- `approach_distance` (default `30.0`)
- `cruise_trigger_distance` (default `25.0`)
- `midpoint_distance` (default `80.0`)
- `vertical_deadzone` (default `2.5`)
- `travel_timeout` (default `60.0`)

Obstacle/altitude control:
- `forward_probe_distance` (default `14.0`)
- `forward_probe_min_distance` (default `6.0`)
- `probe_spread_deg` (default `18.0`)
- `probe_height_offset` (default `1.2`)
- `probe_interval` (default `0.15`)
- `obstacle_altitude_step` (default `6.0`)
- `obstacle_altitude_decay_per_sec` (default `8.0`)
- `max_obstacle_altitude_bonus` (default `45.0`)
- `terrain_clearance` (default `18.0`)
- `ground_sample_interval` (default `0.8`)

## Exposed Status (for debug/UI)
`FlyBuddy:get_status()` now includes:
- `obstacle_blocked`
- `obstacle_altitude_bonus`
- `last_ground_height`

## Integration Points
- `GatherBuddy/core/TravelingController.lua` chooses FlyBuddy travel when profile is flying.
- Movement execution still uses shared NavLib movement (`follow_path`).
- Vertical correction loop is handled inside `FlyBuddy:update()`.

## Known Limits
- No true air-volume pathfinding (no flying mesh graph).
- Obstacle handling is reactive (ray probe + climb), not global planning.
- Behavior quality depends on profile waypoint quality.

## Tuning Tips
If the bot clips mountains/trees:
- increase `forward_probe_distance`
- increase `obstacle_altitude_step`
- increase `terrain_clearance`

If it oscillates vertically:
- increase `vertical_deadzone`
- reduce `obstacle_altitude_step`
