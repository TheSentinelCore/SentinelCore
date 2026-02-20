# SentinelNavClient API and Architecture

Last updated for `SentinelNavClient` `v0.0.6` (current `master`).

This document is the canonical reference for:

- The public consumer API (`_G.SentinelNavClient` and `Client`)
- The current architecture (EventBus + Blackboard + HSM + BT + services)
- Advanced escape hatches (`nav_client`, `movement`, `obstacle`, EventBus, Blackboard)
- Migration notes from the pre-refactor architecture

## Table of Contents

- [1. Quick Start](#1-quick-start)
- [2. Public Global API](#2-public-global-api)
- [3. Client API (Stable)](#3-client-api-stable)
- [4. Event Model](#4-event-model)
- [5. State Model](#5-state-model)
- [6. Architecture](#6-architecture)
- [7. Advanced APIs (Use With Care)](#7-advanced-apis-use-with-care)
- [8. Configuration Reference](#8-configuration-reference)
- [9. Migration Guide](#9-migration-guide)
- [10. Consumer Best Practices](#10-consumer-best-practices)
- [11. Coverage Checklist](#11-coverage-checklist)
- [12. Consumer Cookbook](#12-consumer-cookbook)

## 1. Quick Start

```lua
-- In your plugin initialize():
if not (_G.SentinelNavClient and _G.SentinelNavClient.client) then
    core.log_error("SentinelNavClient not loaded")
    return
end

local client = _G.SentinelNavClient.client

client:move_to({ x = -8900, y = 560, z = 94 }, function(ok, reason)
    if ok then
        core.log("Arrived")
    else
        core.log_error("Navigation failed: " .. tostring(reason))
    end
end)
```

Notes:

- Do not call `client:update()` from consumers. SentinelNavClient drives updates.
- Do not own navigation tuning in consumer plugins. SentinelNavClient UI owns config.

## 2. Public Global API

Defined in `SentinelNavClient/main.lua`.

### `_G.SentinelNavClient`

| Field | Type | Stability | Description |
|---|---|---|---|
| `client` | `Client\|nil` | Stable | Live metatable getter for the shared singleton Client |
| `create(config?)` | `function` | Stable | Returns the shared Client. `config` is accepted but ignored |
| `ui` | UIWindow module | Stable | UI orchestrator (`ui/window.lua`) |
| `JSON` | module | Stable | JSON utility |
| `Helpers` | module | Stable | General helper utility |
| `VERSION` | string | Stable | Current plugin version |

### Removed from older builds

These are not exported on `_G.SentinelNavClient` anymore:

- `create_ui(...)`
- `Navigation`
- `Movement`
- `Obstacle`

If consumers used those directly, update them to use `client` and the advanced escape hatches in this document.

## 3. Client API (Stable)

Defined in `SentinelNavClient/core/Client.lua`.

### 3.1 Construction and lifecycle

Consumers should not instantiate `Client` directly.

| Method | Signature | Description |
|---|---|---|
| `new` | `Client:new(config?) -> Client` | Internal constructor used by plugin singleton |
| `update` | `client:update()` | Internal frame tick (already called by plugin) |
| `destroy` | `client:destroy()` | Cleanup and teardown |

### 3.2 Movement commands

| Method | Signature | Description |
|---|---|---|
| `move_to` | `client:move_to(target, callback?, opts?)` | Pathfinds and starts navigation |
| `move_direct` | `client:move_direct(target, callback?)` | Follows a direct single-waypoint path |
| `follow_path` | `client:follow_path(waypoints, callback?)` | Follow precomputed waypoints |
| `plan_route` | `client:plan_route(nodes, callback?, opts?)` | Plans a TSP route and returns route data |
| `start_route` | `client:start_route(nodes, callback?, opts?)` | Plans and executes a tracked route session with leg callbacks/events |
| `replan` | `client:replan(reason?)` | Re-requests current path to current destination |
| `validate_destination` | `client:validate_destination(target, callback)` | Reachability probe without starting movement |
| `stop` | `client:stop()` | Stops movement and resets active nav state |

#### `move_to(target, callback?, opts?)`

- `target`: `{ x, y, z }`
- `callback`: `function(success, reason)` (optional)
- `opts`: optional per-command pathfinding overrides stored as `path.command_opts`

Behavior:

- Defers move while casting (enters `navigating.deferred`).
- Otherwise transitions into `navigating.awaiting_path` and BT requests path.

#### `plan_route(nodes, callback?, opts?)`

Current behavior:

- Calls `nav_client:find_route_tsp(...)`
- Returns planned route data in callback
- Does not execute multi-leg callbacks like legacy `leg_complete/route_complete`

Route callback shape:

```lua
function(success, data)
    -- success = true:
    -- data.waypoints      vec3[]
    -- data.visit_order    int[] (1-based)
    -- data.leg_boundaries int[]
    -- data.leg_distances  number[]
    -- data.total_distance number

    -- success = false:
    -- data may be nil (for early local-player failure)
    -- or { error = string }
end
```

To execute a returned route immediately, call `client:follow_path(data.waypoints, ...)`.

#### `start_route(nodes, callback?, opts?)`

- Plans via TSP and then executes the route automatically.
- Emits `nav.leg_completed` as legs are crossed.
- Reuses the callback for route lifecycle updates.

Route execution callback shape:

```lua
function(success, data)
    -- success=true leg event:
    -- data.type  == "leg_complete"
    -- data.leg   number
    -- data.total number

    -- success=true completion:
    -- data.type           == "route_complete"
    -- data.total_distance number
    -- data.visit_order    int[]

    -- success=false:
    -- data.type  == "route_failed"
    -- data.error string
end
```

#### `replan(reason?)`

- Replans active destination path by clearing current path state and returning to `awaiting_path`.
- If a tracked route session is active (`start_route`), replans from remaining nodes.

### 3.3 State and progress

| Method | Signature | Returns |
|---|---|---|
| `get_state` | `client:get_state()` | `"idle" \| "navigating" \| "arrived" \| "failed"` |
| `get_full_state` | `client:get_full_state()` | Dot-joined hierarchical state |
| `is_moving` | `client:is_moving()` | `true` only while top-level state is `navigating` |
| `get_destination` | `client:get_destination()` | `vec3\|nil` |
| `get_current_path` | `client:get_current_path()` | `vec3[]\|nil` |
| `get_path_index` | `client:get_path_index()` | `number` |
| `get_progress` | `client:get_progress()` | Progress snapshot |
| `get_route_progress` | `client:get_route_progress()` | Active route session progress, or `nil` |
| `get_corridor_widths` | `client:get_corridor_widths()` | `number[]\|nil` |

`get_progress()` shape:

```lua
{
    percent = number,             -- 0..1
    waypoints_remaining = number,
    total_waypoints = number,
    current_index = number,
    route_mode = boolean|nil,
    current_leg = number|nil,
    total_legs = number|nil,
}
```

### 3.4 Server queries

| Method | Signature | Description |
|---|---|---|
| `is_server_available` | `client:is_server_available()` | `true` when server connection flag is up |
| `health_check` | `client:health_check(callback)` | Server health ping |
| `get_height` | `client:get_height(pos, callback)` | Navmesh height at pos |
| `get_player_height` | `client:get_player_height(callback)` | Height at current player position |
| `get_all_heights` | `client:get_all_heights(pos, callback, opts?)` | Multi-layer heights at XY |
| `get_player_all_heights` | `client:get_player_all_heights(callback, opts?)` | Multi-layer heights at player |

`is_server_available()` reflects the blackboard connection flag maintained by `NavigationService`:

- Set `true` after successful responses
- Marked disconnected after repeated failures
- Domain/path errors returned inside HTTP 200 responses do not mark the server disconnected

### 3.5 Path option builders

| Method | Signature | Description |
|---|---|---|
| `get_path_opts` | `client:get_path_opts(extra?) -> table` | Builds path options from current config |
| `get_corridor_opts` | `client:get_corridor_opts(extra?) -> table` | Same as above plus corridor fields |

### 3.6 Runtime config

| Method | Signature | Description |
|---|---|---|
| `update_config` | `client:update_config(overrides)` | Writes movement/obstacle/navigation config |

Important:

- SentinelNavClient UI calls `update_config(...)` every render frame from `ui/window.lua`.
- Consumer-side `update_config(...)` calls are usually overwritten by UI sync.

### 3.7 Event subscription

| Method | Signature | Description |
|---|---|---|
| `on` | `client:on(event, callback)` | Legacy compatibility events |
| `off` | `client:off(event, callback)` | Remove legacy callback |
| `get_event_bus` | `client:get_event_bus()` | Returns EventBus instance |
| `get_blackboard` | `client:get_blackboard()` | Returns Blackboard instance |

Legacy `client:on(...)` events:

- `"state_change"` with `{ from, to }`
- `"arrived"`
- `"stuck"` (mapped from `navigating.recovering`)
- `"failed"`

## 4. Event Model

### 4.1 EventBus-based events (`events/Events.lua`)

Declared event keys are:

```lua
nav.state_changed
nav.arrived
nav.failed

nav.stuck_detected
nav.stuck_recovered
nav.deviation_detected
nav.repath_started
nav.repath_completed
nav.obstacle_detected

nav.path_requested
nav.path_received
nav.path_failed
nav.waypoint_reached
nav.leg_completed

nav.server_connected
nav.server_retry
nav.server_disconnected
nav.server_error
```

Currently emitted in the live pipeline:

- `nav.state_changed`
- `nav.arrived`
- `nav.failed`
- `nav.stuck_detected`
- `nav.stuck_recovered`
- `nav.deviation_detected`
- `nav.repath_started`
- `nav.repath_completed`
- `nav.obstacle_detected`
- `nav.path_requested`
- `nav.path_received`
- `nav.path_failed`
- `nav.waypoint_reached`
- `nav.leg_completed`
- `nav.server_connected`
- `nav.server_retry`
- `nav.server_disconnected`
- `nav.server_error`

### 4.2 EventBus usage

```lua
local bus = client:get_event_bus()

local sub_id = bus:on("nav.state_changed", function(data, event_name)
    core.log(event_name .. ": " .. tostring(data.from) .. " -> " .. tostring(data.to))
end, { owner = self, priority = 50 })

bus:on_pattern("nav.server_*", function(data, event_name)
    core.log("Server event: " .. event_name)
end, { owner = self })

-- Later cleanup:
bus:off(sub_id)
bus:off_owner(self)
```

EventBus supports:

- `on`, `once`, `on_pattern`
- `off(id)` and `off(event, callback)`
- `off_owner(owner)`
- `pause()` / `resume()`

## 5. State Model

Defined by `core/StateMachine.lua`.

### Top-level states

- `idle`
- `navigating`
- `arrived`
- `failed`

### Navigating substates

- `awaiting_path`
- `following_path`
- `recovering`
- `repathing`
- `deferred`

### Recovery sub-substates

- `jumping`
- `probing`
- `strafing`
- `backtracking`

### Failure reasons

- `unreachable`
- `server_timeout`
- `max_stuck_exceeded`
- `max_repath_exceeded`

### Full-state examples

- `idle`
- `navigating.awaiting_path`
- `navigating.recovering.strafing`

## 6. Architecture

### 6.1 Runtime design

```
main.lua
  -> init.lua singleton
  -> shared Client
      -> EventBus
      -> Blackboard
      -> ConsoleLogger
      -> StateMachine
      -> Sensors
      -> Services:
         - NavigationService
         - MovementService
         - ObstacleService
         - PathValidationService
      -> NavigationTree (Behavior Tree)
```

### 6.2 Frame flow (`client:update()`)

1. Sensors write player state into blackboard.
2. If in `navigating`, tick Behavior Tree.
3. Resolve terminal failure policy from blackboard (`nav.fail_reason`) and transition to `failed` when set.
4. Run stuck detection and max-stuck guard.
5. Process deferred move when casting ends.
6. Fire legacy compatibility events.

### 6.3 Render flow (`ui/window.lua`)

1. Read menu values.
2. Clamp/sanitize values (example: log severity).
3. Push config via `client:update_config(...)`.
4. Update DebugTab behavior (preview generation/re-generation).
5. Render settings UI.

### 6.4 Behavior Tree responsibilities

Defined in `behaviors/trees/NavigationTree.lua`:

- Ensure path exists (`RequestPath`)
- Normal follow (`AdvanceWaypoint`, dynamic speed)
- Proactive obstacle probing + soft repath
- Periodic path validation
- Deviation-triggered repath (cooldown bounded)
- Escalating stuck recovery (`StuckRecoveryTree`)

## 7. Advanced APIs (Use With Care)

The following are exposed as fields on the shared client:

- `client.nav_client` (`NavigationService`)
- `client.movement` (`MovementService`)
- `client.obstacle` (`ObstacleService`)

These are intentionally available for advanced consumers, but are lower-level and more likely to change than the high-level Client API.

### 7.1 `NavigationService` methods

Core pathing:

- `find_path(start_pos, dest, callback, opts?)`
- `find_route_tsp(nodes, callback, opts?)`
- `find_route_multi(stops, callback, opts?)`
- `check_path(current_pos, waypoints, callback, opts?)`
- `find_path_corridor(start_pos, dest, callback, opts?)`
- `find_path_avoid(start_pos, dest, avoid_zones, callback, opts?)`

Spatial:

- `raycast(start_pos, dest, callback, opts?)`
- `get_height(pos, callback, opts?)`
- `get_all_heights(pos, callback, opts?)`
- `random_point(callback, opts?)`

Tactical:

- `flee(player_pos, threats, callback, opts?)`
- `kite(player_pos, target_pos, callback, opts?)`

Health/config:

- `health_check(callback)`
- `is_available()`
- `get_consecutive_failures()`
- `reset()`
- `update_config(overrides)`

Utilities:

- `NavigationService.is_indoor()`
- `NavigationService.get_continent_id()`

### 7.2 `MovementService` methods

- `navigate(waypoints)`
- `process()`
- `stop()`
- `get_current_index()`
- `get_remaining_waypoints()`
- `is_moving()`
- `strafe(direction)`
- `apply_dynamic_speed(blackboard?)`
- `update_config(overrides)`
- `get_config(key, default?)`

### 7.3 `ObstacleService` methods

- `probe_forward(player_pos, target_pos)`
- `probe_segment(pos_a, pos_b)`
- `probe_path_ahead(waypoints, max_segments?)`
- `add_zone(pos, radius?)`
- `remove_zone(index)`
- `prune(player_pos?)`
- `get_avoidance_zones()`
- `get_zone_count()`
- `clear()`
- `update_config(overrides)`

## 8. Configuration Reference

Source of truth: `core/Defaults.lua`.

### 8.1 Movement defaults

```lua
dynamic_speed = true
dynamic_speed_max_tolerance_scale = 1.20
dynamic_speed_max_tolerance_bonus = 0.75
dynamic_speed_ramp_z_delta = 1.2
dynamic_speed_ramp_tolerance = 1.8
dynamic_speed_ramp_look_distance = 6.0

waypoint_tolerance = 3.0
final_tolerance = 1.5

anti_detection = false
max_deviation = 3.0

stuck_check_interval = 1.0
stuck_distance_min = 1.0
max_stuck_attempts = 6

path_check_interval = 5.0
path_request_max_retries = 2
path_request_retry_base = 0.5
max_repath_failures = 3

deviation_check_interval = 1.0
deviation_threshold = 2.0
deviation_vertical_threshold = 2.0
deviation_corridor_factor = 0.75
repath_cooldown = 0.1
max_deviation_repaths = 5

optimize = true
allow_partial = true

string_pull_deviation = 1.0
string_pull_heading = 30.0
string_pull_wall_dist = 1.0
densify_segment_length = 1.0

filter_ground = 1.0
filter_water = 10.0
filter_lava = 100.0

use_corridor_indoor = true
corridor_probe_dist = 15.0

wall_clearance_enabled = true
wall_clearance = 2.0

proactive_obstacle_check = true
proactive_obstacle_interval = 1.5

log_severity = 2   -- 0=error, 1=warn, 2=info, 3=debug
debug_verbose = false
```

### 8.2 Obstacle defaults

```lua
avoidance_radius = 3.0
max_zones = 5
zone_ttl = 120.0
avoidance_cost = 100.0
zone_prune_dist = 100.0

probe_distance = 8.0
probe_spread_deg = 20.0
probe_height_offset = 1.0

lookahead_height_offset = 1.5
lookahead_spread_deg = 15.0
lookahead_segments = 3
```

### 8.3 Debug/UI defaults

`Defaults.debug` and `Defaults.window` are UI controls, not direct pathfinding engine config.

## 9. Migration Guide

If you are migrating from pre-refactor SentinelNavClient (pre EventBus/Blackboard/HSM architecture), review these changes:

1. Global exports changed

- Removed: `_G.SentinelNavClient.Navigation`, `.Movement`, `.Obstacle`, `.create_ui`
- Use: `_G.SentinelNavClient.client` and `client.nav_client` / `client.movement` / `client.obstacle` when needed

2. `plan_route` behavior changed

- Old: route execution callbacks (`leg_complete`, `route_complete`)
- New: planning call only; returns route path metadata
- New route execution API: `start_route(...)`

3. `replan` behavior changed

- Old: route-leg-aware replanning
- New: destination refresh by default, and route-aware when a `start_route` session is active

4. State names changed

- Old examples: `requesting_path`, `moving`, `stuck`
- New top-level: `idle`, `navigating`, `arrived`, `failed`
- Use `get_full_state()` for substate detail

5. `get_progress()` payload changed

- Now returns percent + waypoint counts/index only

6. Internals moved from monolith modules to service architecture

- `core/Movement.lua` and `core/Obstacle.lua` removed
- `core/Navigation.lua` replaced by `services/NavigationService.lua`

## 10. Consumer Best Practices

1. Resolve and store client once in plugin initialization.
2. Treat high-level `Client` methods as the primary API.
3. Prefer event-driven flow (`arrived`, `failed`) over polling loops.
4. Use EventBus `owner` and `off_owner` for clean teardown.
5. Avoid writing nav tuning from consumer plugins; use SentinelNavClient UI.
6. If you must use escape hatches, isolate that code behind your own adapter so you can update in one place later.

## 11. Coverage Checklist

This document currently covers all consumer-critical contracts:

- How to obtain and use the shared client (`_G.SentinelNavClient.client`, `create`)
- Stable movement/state/query/event APIs on `Client`
- Current state model and event model
- Runtime config ownership and override behavior
- Advanced escape hatches and their stability caveats
- Default tuning values used at runtime
- Migration deltas from the legacy architecture

If you need additional guarantees for your own plugin, add a contract test against:

- `core/Client.lua` public methods
- `events/Events.lua` event keys
- `core/StateMachine.lua` state constants

## 12. Consumer Cookbook

### 12.1 Safe client acquisition

```lua
local function get_nav_client()
    if not (_G.SentinelNavClient and _G.SentinelNavClient.client) then
        return nil, "SentinelNavClient unavailable"
    end
    return _G.SentinelNavClient.client, nil
end
```

### 12.2 Validate then move

```lua
local client, err = get_nav_client()
if not client then
    core.log_error(err)
    return
end

local target = { x = -8900, y = 560, z = 94 }
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

### 12.3 Plan a TSP route then execute it

```lua
local nodes = {
    { x = -9100, y = 400, z = 93 },
    { x = -9200, y = 500, z = 91 },
    { x = -8900, y = 600, z = 95 },
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

### 12.4 Event lifecycle with owner cleanup

```lua
local bus = client:get_event_bus()

bus:on("nav.state_changed", function(data)
    core.log(string.format("State: %s -> %s", tostring(data.from), tostring(data.to)))
end, { owner = self })

bus:on("nav.failed", function(data)
    core.log_error("Nav failed: " .. tostring(data and data.reason))
end, { owner = self })

-- In plugin teardown:
bus:off_owner(self)
```

### 12.5 Polling guard with full-state checks

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

### 12.6 Server readiness gate

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

If behavior and this document disagree, the code in `core/Client.lua`, `core/StateMachine.lua`, and `services/*.lua` is the final source of truth.
