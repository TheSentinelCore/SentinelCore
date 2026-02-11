# NavLibFacade API Reference

Single entry-point facade for NavLib. Creates, wires, and drives all modules with one constructor call, one `update()` per frame, and a built-in event system for state-change notifications.

**This is the recommended way to use NavLib.** For advanced use cases requiring direct module access, see the [escape hatch](#escape-hatch) section or the individual module docs.

## Table of Contents

- [Constructor](#constructor)
- [Update Loop](#update-loop)
- [Movement](#movement)
  - [move_to](#move_to)
  - [move_direct](#move_direct)
  - [plan_route](#plan_route)
  - [replan](#replan)
  - [validate_destination](#validate_destination)
  - [stop](#stop)
  - [destroy](#destroy)
- [State Queries](#state-queries)
  - [get_state](#get_state)
  - [is_moving](#is_moving)
  - [get_destination](#get_destination)
  - [get_current_path](#get_current_path)
  - [get_path_index](#get_path_index)
  - [get_progress](#get_progress)
  - [get_corridor_widths](#get_corridor_widths)
- [Server Queries](#server-queries)
  - [is_server_available](#is_server_available)
  - [health_check](#health_check)
- [Configuration](#configuration)
  - [Constructor Config](#constructor-config)
  - [update_config](#update_config)
- [Events](#events)
  - [on](#on)
  - [off](#off)
  - [Event Types](#event-types)
- [Escape Hatch](#escape-hatch)

---

## Constructor

### `_G.NavLib.create(config?) -> NavLibFacade`

Create a fully-wired NavLib instance. Internally creates a [NavigationClient](NavigationClient.md), [MovementModule](MovementModule.md), and [ObstacleModule](ObstacleModule.md), then wires the obstacle module into the movement module automatically.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `config` | table | no | Sectioned config (see [Constructor Config](#constructor-config)) |

**Config structure:**
```lua
{
    navigation = {  -- NavigationClient config
        base_url = "http://localhost:47110",  -- default
        max_retries = 3,                      -- default
    },
    movement = {    -- MovementModule config (24 fields)
        waypoint_tolerance = 3.0,
        smoothing = "chaikin",
        -- ... see MovementModule docs for all fields
    },
    obstacles = {   -- ObstacleModule config (12 fields)
        avoidance_radius = 3.0,
        max_zones = 5,
        -- ... see ObstacleModule docs for all fields
    },
}
```

All sections are optional. Omitted sections use the module's defaults.

**Example:**
```lua
-- Minimal — all defaults
local nav = _G.NavLib.create()

-- With config
local nav = _G.NavLib.create({
    movement = {
        smoothing = "chaikin",
        waypoint_tolerance = 3.0,
        anti_detection = true,
        max_deviation = 5.0,
    },
    obstacles = {
        avoidance_radius = 4.0,
    },
})
```

---

## Update Loop

### update

```lua
nav:update()
```

**Must be called every frame.** Drives all internal modules in the correct order:

1. `obstacle:update()` — compatibility hook (probing is timer-driven)
2. `movement:update()` — advances waypoints, stuck detection, obstacle scanning, path validation
3. Detects state transitions and fires [events](#events)

```lua
core.register_on_update_callback(function()
    nav:update()
end)
```

---

## Movement

All movement methods delegate to the internal [MovementModule](MovementModule.md). See that doc for detailed behavior (casting deferral, corridor adaptation, stuck recovery, etc.).

### move_to

```lua
nav:move_to(target, callback?, opts?)
```

Move to a target position using navmesh pathfinding.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `target` | vec3 | yes | Destination `{x, y, z}` |
| `callback` | function | no | `function(success, reason)` |
| `opts` | table | no | `{ use_navmesh = true, map_id = auto }` |

**Example:**
```lua
nav:move_to(destination, function(ok, reason)
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
nav:move_direct(target, callback?)
```

Move directly without pathfinding. Equivalent to `move_to(target, callback, { use_navmesh = false })`.

---

### plan_route

```lua
nav:plan_route(nodes, callback?, opts?)
```

Plan and execute a TSP-optimized route through multiple nodes.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `nodes` | vec3[] | yes | At least 2 positions to visit |
| `callback` | function | no | Route progress callback |
| `opts` | table | no | `{ map_id = auto, return_to_start = false }` |

**Callback:** Called multiple times:
```lua
function(success, data)
    if success then
        if data.type == "leg_complete" then
            -- data.leg, data.total
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
nav:replan(reason?)
```

Replan the active route from the current leg. Requires an active route from `plan_route()`.

---

### validate_destination

```lua
nav:validate_destination(target, callback)
```

Check if a destination is reachable **without starting movement**.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `target` | vec3 | yes | Target position |
| `callback` | function | yes | `function(reachable, reason, distance)` |

> **Note:** This delegates to `MovementModule:validate_destination_reachable()`. The shorter name is a facade convenience.

---

### stop

```lua
nav:stop()
```

Stop all movement and reset to idle. Clears active path, destination, callbacks, stuck counters, and route data.

---

### destroy

```lua
nav:destroy()
```

Stop movement, clear all obstacle zones, and remove event listeners. Call when permanently done with the NavLib instance.

---

## State Queries

### get_state

```lua
nav:get_state() -> string
```

Returns the current movement state:

| State | Description |
|-------|-------------|
| `"idle"` | Not moving |
| `"requesting_path"` | Waiting for path from NavBuddy |
| `"moving"` | Actively following waypoints |
| `"stuck"` | Stuck recovery in progress |
| `"arrived"` | Reached destination |
| `"failed"` | Movement failed |

---

### is_moving

```lua
nav:is_moving() -> boolean
```

Returns `true` if state is `"moving"` or `"requesting_path"`.

---

### get_destination

```lua
nav:get_destination() -> vec3|nil
```

Returns the current destination, or `nil` if not moving.

---

### get_current_path

```lua
nav:get_current_path() -> vec3[]|nil
```

Returns the current waypoint array, or `nil` if no active path.

---

### get_path_index

```lua
nav:get_path_index() -> number
```

Returns the current waypoint index in the active path. Returns `1` if no path is active.

---

### get_progress

```lua
nav:get_progress() -> table
```

Detailed progress snapshot:

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

---

### get_corridor_widths

```lua
nav:get_corridor_widths() -> number[]|nil
```

Returns corridor width data for the current indoor path, or `nil` if outdoors or no data.

---

## Server Queries

### is_server_available

```lua
nav:is_server_available() -> boolean
```

Returns `true` if NavBuddy server appears connected (has had a recent successful request, fewer than 3 consecutive failures).

---

### health_check

```lua
nav:health_check(callback)
```

Check NavBuddy server health.

**Callback:**
```lua
function(ok, data, err)
    -- data.status, data.version, data.uptime_secs, data.loaded_maps
end
```

---

## Configuration

### Constructor Config

The `create()` config is **sectioned** — each key maps to a module's configuration:

| Section | Module | Doc |
|---------|--------|-----|
| `navigation` | NavigationClient | [Config](NavigationClient.md#configuration) |
| `movement` | MovementModule | [Config](MovementModule.md#constructor-config) |
| `obstacles` | ObstacleModule | [Config](ObstacleModule.md#constructor-config) |

See each module's doc for the full list of config fields and defaults.

---

### update_config

```lua
nav:update_config(overrides)
```

Distribute config updates to underlying modules at runtime. Only provided keys are changed.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `overrides` | table | yes | `{ movement = {...}, obstacles = {...} }` |

> **Note:** `navigation` config (base_url, max_retries) cannot be updated at runtime — it is set once during construction.

**Example:**
```lua
nav:update_config({
    movement = {
        anti_detection = true,
        max_deviation = 5.0,
        smoothing = "catmull_rom",
    },
    obstacles = {
        avoidance_radius = 5.0,
        max_zones = 10,
    },
})
```

---

## Events

The facade fires events when the movement state changes. Use `on()` to subscribe and `off()` to unsubscribe.

### on

```lua
nav:on(event, callback)
```

Register a listener for an event.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `event` | string | yes | Event name (see [Event Types](#event-types)) |
| `callback` | function | yes | Handler function |

Multiple listeners can be registered for the same event. Listeners are called in registration order.

---

### off

```lua
nav:off(event, callback)
```

Remove a previously registered listener. Pass the **same function reference** used in `on()`.

---

### Event Types

| Event | Fired when | Callback data |
|-------|-----------|---------------|
| `"state_change"` | Any state transition | `{ from = string, to = string }` |
| `"arrived"` | Reached destination | `nil` |
| `"stuck"` | Stuck detected | `nil` |
| `"failed"` | Movement failed | `nil` |

**Example:**
```lua
nav:on("state_change", function(data)
    core.log(string.format("NavLib: %s -> %s", data.from, data.to))
end)

nav:on("arrived", function()
    core.log("Destination reached!")
end)

nav:on("failed", function()
    core.log_error("Movement failed — check path or obstacles")
end)
```

**Error handling:** Event callbacks are wrapped in `pcall`. If a handler throws, it is caught and logged but does not affect other handlers or NavLib operation.

---

## Escape Hatch

For advanced use cases, the underlying module instances are exposed as public fields:

| Field | Type | Description |
|-------|------|-------------|
| `nav.nav_client` | NavigationClient | Raw HTTP client — direct access to all 14 endpoints |
| `nav.movement` | MovementModule | Path follower — full state machine, stuck recovery |
| `nav.obstacle` | ObstacleModule | Obstacle detector — zone memory, ray probing |

**Example:**
```lua
local nav = _G.NavLib.create()

-- Use the facade for common operations
nav:move_to(target, callback)

-- Drop to raw client for specialized queries
nav.nav_client:raycast(start, dest, function(ok, data)
    if ok and not data.hit then
        core.log("Clear line of sight!")
    end
end)

-- Access obstacle zones directly
local zones = nav.obstacle:get_avoidance_zones()
core.log("Active obstacle zones: " .. #zones)

-- Read movement internals
local widths = nav.movement:get_corridor_widths()
```

> **Note:** The facade and its modules share the same instances. Calling `movement:stop()` on the escape hatch has the same effect as `nav:stop()`.

---

## Complete Example

```lua
-- 1. Create NavLib with config
local nav = _G.NavLib.create({
    movement = {
        smoothing = "chaikin",
        optimize = true,
        waypoint_tolerance = 3.0,
        anti_detection = true,
        max_deviation = 3.0,
        use_corridor_indoor = true,
    },
    obstacles = {
        avoidance_radius = 3.0,
        max_zones = 5,
    },
})

-- 2. Register event listeners
nav:on("arrived", function()
    core.log("Arrived at destination!")
end)

nav:on("failed", function()
    core.log_error("Movement failed")
end)

nav:on("state_change", function(data)
    core.log("[Nav] " .. data.from .. " -> " .. data.to)
end)

-- 3. Register frame update
core.register_on_update_callback(function()
    nav:update()
end)

-- 4. Check server health
nav:health_check(function(ok, data)
    if ok then
        core.log("NavBuddy v" .. data.version .. " (" .. data.uptime_secs .. "s uptime)")
    else
        core.log_error("NavBuddy server not reachable")
    end
end)

-- 5. Move to a destination
local dest = { x = -8900, y = 560, z = 94 }

nav:validate_destination(dest, function(reachable, reason, distance)
    if reachable then
        core.log(string.format("Target reachable, %.0f yards", distance))
        nav:move_to(dest)
    else
        core.log_error("Unreachable: " .. tostring(reason))
    end
end)

-- 6. Update config at runtime (e.g., from UI settings)
nav:update_config({
    movement = {
        anti_detection = Settings.get("movement.anti_detection", false),
        max_deviation = Settings.get("movement.max_deviation", 3.0),
    },
})

-- 7. Plan a multi-node route
local herb_spots = {
    { x = -9100, y = 400, z = 93 },
    { x = -9200, y = 500, z = 91 },
    { x = -8900, y = 600, z = 95 },
}

nav:plan_route(herb_spots, function(ok, data)
    if ok and data.type == "route_complete" then
        core.log("Route finished!")
    end
end, { return_to_start = true })

-- 8. Stop when needed
-- nav:stop()

-- 9. Cleanup when done
-- nav:destroy()
```
