# Sylvannas API Quick Reference — Movement & Navigation

This document contains ONLY the Sylvannas API functions needed for the Movement & Navigation Client implementation. Claude Code should reference this during implementation to ensure correct API usage.

---

## Core Timing & Info

```lua
core.time()           → number  -- seconds since injection (float)
core.delta_time()     → number  -- seconds since last frame (float)
core.game_time()      → number  -- game time in milliseconds (integer)
core.get_map_id()     → number  -- current continent/map ID
core.get_ping()       → number  -- network latency
```

## Logging

```lua
core.log(message)           -- white, info level
core.log_warning(message)   -- yellow, warning level
core.log_error(message)     -- red, error level
```

## HTTP

```lua
-- ASYNCHRONOUS — response comes in callback, NEVER blocks
core.http_get(url, callback)
-- callback signature: function(http_code, content_type, response_body, response_headers)
-- http_code: 200 = success, 0 = connection failed, 4xx/5xx = server error
-- response_body: string (JSON for NavBuddy)

-- With custom headers (not needed for NavBuddy):
core.http_get(url, headers_table, callback)
```

## Player (game_object)

```lua
local player = core.object_manager.get_local_player()
-- ⚠️ CAN RETURN NIL during loading screen — always check!

-- Position & Orientation
player:get_position()          → vec3   -- world position {x, y, z}
player:get_direction()         → vec3   -- facing direction unit vector
player:get_rotation()          → number -- facing angle in radians

-- Movement info
player:get_movement_speed()     → number -- current speed (yards/sec)
player:get_movement_speed_max() → number -- max possible speed
player:is_moving()              → boolean

-- State checks
player:is_valid()               → boolean
player:is_dead()                → boolean
player:is_mounted()             → boolean
player:is_indoors()             → boolean
player:is_in_combat()           → boolean
player:is_casting_spell()       → boolean
player:is_channelling_spell()   → boolean
player:get_bounding_radius()    → number -- hitbox radius in yards
```

## Movement Inputs (core.input)

```lua
-- Directional movement (start/stop pairs)
core.input.move_forward_start()   / core.input.move_forward_stop()
core.input.move_backward_start()  / core.input.move_backward_stop()
core.input.strafe_left_start()    / core.input.strafe_left_stop()
core.input.strafe_right_start()   / core.input.strafe_right_stop()
core.input.turn_left_start()      / core.input.turn_left_stop()
core.input.turn_right_start()     / core.input.turn_right_stop()
core.input.move_up_start()        / core.input.move_up_stop()   -- swim/fly up
core.input.move_down_start()      / core.input.move_down_stop() -- swim/fly down

-- Instant actions
core.input.look_at(vec3)          -- face toward a world position
core.input.jump()                 -- jump
core.input.enable_movement()      -- unlock movement
core.input.disable_movement(is_lock) -- lock movement (bool)
```

## Line of Sight

```lua
core.graphics.trace_line(pos1, pos2, flags) → boolean
-- Returns true if LOS is BLOCKED between pos1 and pos2
-- flags: use enums.collision_flags.LineOfSight or .Collision
```

## vec3

```lua
local vec3 = require("common/geometry/vector_3")

-- Creation
vec3.new(x, y, z)        → vec3

-- Fields
v.x, v.y, v.z            → number

-- Methods (COLON syntax)
v:dist_to(other)          → number  -- 3D distance
v:dist_to_ignore_z(other) → number  -- 2D distance (XY plane)
v:normalize()             → vec3    -- unit vector
v:length()                → number  -- magnitude
v:lerp(target, alpha)     → vec3    -- linear interpolation (0-1)
v:get_extended(target, n) → vec3    -- extend toward target by n yards
v:clone()                 → vec3    -- copy
v:is_zero()               → boolean
v:is_nan()                → boolean

-- Operators
v1 + v2                   → vec3
v1 - v2                   → vec3
v1 * scalar               → vec3
v1 / scalar               → vec3
```

## simple_movement

```lua
local simple_movement = require("common/utility/simple_movement")
-- ⚠️ SINGLETON — use colon syntax, do NOT create instances

-- Core movement
simple_movement:move_to_position(vec3)       → boolean  -- single point
simple_movement:navigate(vec3[], loop?, restart?) → boolean  -- waypoint list
simple_movement:process()                     → boolean  -- ⚠️ MUST call every frame! Returns true when done
simple_movement:stop()                        -- stop all movement
simple_movement:is_moving()                   → boolean

-- Waypoint info
simple_movement:get_target()                  → vec3|nil -- current waypoint
simple_movement:get_remaining_waypoints()     → vec3[]
simple_movement:get_current_index()           → number
simple_movement:get_waypoint_count()          → number
simple_movement:get_progress()                → number  -- 0-100%

-- Configuration
simple_movement:set_threshold(yards)           -- waypoint arrival distance (1-10)
simple_movement:set_final_threshold(yards)     -- final stop precision (0.5-5)
simple_movement:set_smoothing_enabled(bool)    -- Catmull-Rom smoothing
simple_movement:set_smoothing_subdivisions(n)  -- smoothing quality (1-20)
simple_movement:set_use_look_at(bool)          -- smooth vs legacy turning
simple_movement:set_turn_speed(speed)          -- turn rate (0.05-0.5)
simple_movement:set_look_distance(yards)       -- look-ahead (5-50)
simple_movement:set_debug(bool)                -- debug logging

-- State inspection
simple_movement:get_state()                    → simple_movement_state
```

## Enums

```lua
local enums = require("common/enums")

enums.collision_flags.LineOfSight  → number
enums.collision_flags.Collision    → number
```

## Callbacks

```lua
-- Register update callback (called every frame, throttled)
core.register_on_update_callback(function()
    -- your logic here, including movement:update()
end)

-- Register render callback (called every frame at full FPS)
core.register_on_render_callback(function()
    -- drawing only
end)
```

---

## Common Patterns

### Safe Player Access
```lua
local player = core.object_manager.get_local_player()
if not player or not player:is_valid() then return end
local pos = player:get_position()
```

### Timed Action (check interval)
```lua
-- In constructor:
self._last_check = 0

-- In update:
local now = core.time()
if now - self._last_check >= self._config.check_interval then
    self._last_check = now
    -- do periodic check
end
```

### Async Request with State Guard
```lua
function Module:request_path(target)
    self._state = "requesting_path"
    local state_at_request = self._state  -- capture for closure

    self._nav_client:find_path(start, target, function(success, data, err)
        -- Guard: state may have changed while waiting
        if self._state ~= "requesting_path" then return end

        if success then
            self._state = "moving"
            simple_movement:navigate(data.waypoints)
        else
            self._state = "failed"
        end
    end)
end
```
