---
title: "IZI - SDK"
source: "https://docs.project-sylvanas.net/dev/libraries/izi"
crawled: "2026-07-14"
---

# IZI - SDK

## Overview

The IZI SDK is a comprehensive, high-level toolkit designed to accelerate and simplify your plugin development workflow. It provides a rich set of utilities, event-driven callbacks, and intelligent helpers that abstract away common complexities, allowing you to focus on building powerful features rather than reinventing the wheel.

**Key Features:**

-   **Enhanced Logging** - Formatted console and file logging utilities
-   **Extended Event System** - Register callbacks for combat events, spell casts, buffs/debuffs, and keyboard input
-   **Time Management** - Precise timing utilities with scheduled callbacks
-   **Target Selection** - Seamlessly integrate with the target selector system
-   **Smart Unit Management** - Easily query and filter enemies, friends, and party members with flexible predicates
-   **Queue Automation** - Detect and interact with PvP/PvE queue popups
-   **Game Object Extensions** - Automatic extensions to the [`game_object`](/dev/api/game-object) class with advanced utility methods

Whether you're building a combat routine, automation tool, or utility plugin, the IZI SDK provides the building blocks you need to create professional-grade solutions with minimal boilerplate code.

## Module Reference

The IZI SDK provides direct access to several modules for convenience:

| Module | Access | Documentation |
|--------|--------|---------------|
| Enumerations | `izi.enums` | [Enums API](/dev/api/enums) |
| Color utilities | `izi.color` | [Color API](/dev/api/color) |
| 2D Vectors | `izi.vec2` | [Vector 2 API](/dev/api/vector-2) |
| 3D Vectors | `izi.vec3` | [Vector 3 API](/dev/api/vector-3) |
| Circles | `izi.circle` | [Geometry - Circles](/dev/libraries/izi/geometry#circles) |
| Rectangles | `izi.rectangle` | [Geometry - Rectangles](/dev/libraries/izi/geometry#rectangles) |
| Cones | `izi.cone` | [Geometry - Cones](/dev/libraries/izi/geometry#cones) |

**Example Usage**

```lua
-- Access enums directly
local class = izi.enums.class_id.WARRIOR

-- Create geometry shapes
local aoe_circle = izi.circle(target:get_position(), 8)
local cleave_cone = izi.cone(player:get_position(), player:get_forward(), 90, 10)

-- Create vectors
local screen_pos = izi.vec2(100, 200)
local world_pos = izi.vec3(1234.5, 5678.9, 100)
```

---

## Related Documentation

The IZI SDK is documented across several focused pages:

| Topic | Description | Link |
|-------|-------------|------|
| **Types** | Type definitions for cast options, defensive filters, queue metadata | [IZI Types](/dev/libraries/izi/types) |
| **Callbacks** | Event-driven callbacks for buffs, combat, spells, keyboard | [IZI Callbacks](/dev/libraries/izi/callbacks) |
| **Units** | Target selector integration, unit queries, smart filtering | [IZI Units](/dev/libraries/izi/units) |
| **Queue** | Queue popup detection and automation | [IZI Queue](/dev/libraries/izi/queue) |
| **Geometry** | Vector and shape constructors | [IZI Geometry](/dev/libraries/izi/geometry) |
| **Spell Sequences** | Chain spell casts with conditions and confirmations | [IZI Spell Sequences](/dev/libraries/izi/izi-spells-sequences) |
| **Graphics** | Asset loading, textures, and icon rendering | [IZI Graphics](/dev/libraries/izi/graphics) |
| **Maps** | Coordinate conversion, cursor position, minimap utilities | [IZI Maps](/dev/libraries/izi/maps) |

---

## Importing The Module

> **Warning:** This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the `require` function and store it in a local variable.

Here is an example of how to do it:

```lua
-- recomended "izi" name for consistency
---@type izi_api
local izi = require("common/izi_sdk")
```

## Logging

### `izi.print`

Syntax

```
izi.print(...: any)
```

**Parameters**

-   `...: any` - The arguments to print

Description

Concatenates the arguments and prints them to the console. Any non-string arguments will automatically be casted to a string.

**Example Usage**

```lua
izi.print("izi ", "rocks!") -- Outputs: "izi rocks!" to the console
```

---

### `izi.printf`

Syntax

```
izi.printf(fmt: string, ...: any)
```

**Parameters**

-   `fmt: string` - The format string defining the structure of the message
-   `...: any` - The values for the format string placeholders

Description

Formats a message with the provided format string and values and then prints it to the console.

**Example Usage**

```lua
izi.printf("izi %s!", "rocks")    -- Outputs: "izi rocks!" to the console
izi.printf("%d and %i", 1, 2)     -- Outputs: "1 and 2" to the console
izi.printf("%.2f", 3.14159265359) -- Outputs: "3.14" to the console
```

---

### `izi.log`

Syntax

```
izi.log(filename: string, ...: any)
```

**Parameters**

-   `filename: string` - The name of the log file
-   `...: any` - The arguments to log

Description

Logs the concatenated arguments to a file and prints the same message to the console. Log files are located in the "logs" folder inside the scripts folder. Each log file is timestamped.

**Example Usage**

```lua
izi.log("test", "izi ", "rocks!") -- Outputs "izi rocks!" to test.log and the console
```

---

### `izi.logf`

Syntax

```
izi.logf(filename: string, fmt: string, ...: any)
```

**Parameters**

-   `filename: string` - The name of the log file
-   `fmt: string` - The format string
-   `...: any` - The values for the format string placeholders

Description

Formats a message with the provided format string and values and then logs it to a file and prints the same message to the console.

**Example Usage**

```lua
izi.logf("test", "izi %s!", "rocks") -- Outputs "izi rocks!" to test.log and the console
```

---

## Time

### `izi.now`

Syntax

```
izi.now(): number
```

Returns

-   `number` - Current time in seconds since Unix epoch

Description

Returns the current time in seconds as a floating point number. This is useful for measuring elapsed time, creating cooldowns, and scheduling actions.

**Example Usage**

```lua
local start = izi.now()
-- Do something...
local elapsed = izi.now() - start
izi.printf("Operation took %.2f seconds", elapsed)
```

---

### `izi.now_ms`

Syntax

```
izi.now_ms(): number
```

Returns

-   `number` - Current time in milliseconds

Description

Returns the current time in milliseconds. Useful for precise timing operations where second-level precision is insufficient.

**Example Usage**

```lua
local start_ms = izi.now_ms()
-- Do something...
local elapsed_ms = izi.now_ms() - start_ms
izi.printf("Operation took %d ms", elapsed_ms)
```

---

### `izi.now_game_time_ms`

Syntax

```
izi.now_game_time_ms(): number
```

Returns

-   `number` - Current game time in milliseconds

Description

Returns the current game time in milliseconds. Game time is synchronized with the server and is useful for timing combat events accurately.

**Example Usage**

```lua
local game_ms = izi.now_game_time_ms()
izi.printf("Current game time: %d ms", game_ms)
```

---

### `izi.time_since`

Syntax

```
izi.time_since(past_time_in_seconds: number): number
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `past_time_in_seconds` | `number` | Required | A timestamp from `izi.now()` |

Returns

-   `number` - Seconds elapsed since the provided timestamp

Description

Calculates the number of seconds that have elapsed since a past timestamp. This is a convenience function equivalent to `izi.now() - past_time_in_seconds`.

**Example Usage**

```lua
local last_cast_time = izi.now()
-- Later in your code...
if izi.time_since(last_cast_time) > 2.0 then
    izi.print("At least 2 seconds have passed since last cast")
end
```

---

### `izi.time_since_ms`

Syntax

```
izi.time_since_ms(past_time_in_ms: number): number
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `past_time_in_ms` | `number` | Required | A timestamp from `izi.now_game_time_ms()` |

Returns

-   `number` - Milliseconds elapsed since the provided timestamp (game time)

Description

Calculates the number of milliseconds that have elapsed since a past game time timestamp. Uses game time for accurate combat timing.

**Example Usage**

```lua
local spell_cast_time = izi.now_game_time_ms()
-- Later...
if izi.time_since_ms(spell_cast_time) > 1500 then
    izi.print("1.5 seconds have passed (game time)")
end
```

---

### `izi.time_until`

Syntax

```
izi.time_until(future_time_in_seconds: number): number
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `future_time_in_seconds` | `number` | Required | A future timestamp |

Returns

-   `number` - Seconds until the future timestamp (0 if already past)

Description

Calculates the number of seconds remaining until a future timestamp. Returns 0 if the timestamp is in the past.

**Example Usage**

```lua
local cooldown_end = izi.now() + 10  -- 10 second cooldown
-- Check remaining time
local remaining = izi.time_until(cooldown_end)
if remaining > 0 then
    izi.printf("Cooldown: %.1f seconds remaining", remaining)
else
    izi.print("Cooldown ready!")
end
```

---

### `izi.time_until_ms`

Syntax

```
izi.time_until_ms(future_time_in_ms: number): number
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `future_time_in_ms` | `number` | Required | A future game time timestamp |

Returns

-   `number` - Milliseconds until the future timestamp (0 if already past, game time)

Description

Calculates the number of milliseconds remaining until a future game time timestamp. Returns 0 if the timestamp is in the past. Uses game time for precise combat timing.

**Example Usage**

```lua
local effect_expires = izi.now_game_time_ms() + 5000  -- 5 second effect
-- Check remaining time
local remaining_ms = izi.time_until_ms(effect_expires)
izi.printf("Effect expires in %d ms", remaining_ms)
```

---

### `izi.after`

Syntax

```
izi.after(delay_in_seconds: number, callback: function)
```

**Parameters**

-   `delay_in_seconds: number` - The delay before calling the callback function
-   `callback: function` - The function to execute after the delay

Description

Schedules a callback function to be executed after a specified delay in seconds. Useful for delayed actions, cooldown management, and timed sequences.

**Example Usage**

```lua
izi.print("Starting...")
izi.after(2, function()
    izi.print("This message appears 2 seconds later")
end)
```

---

## Helpers

### `izi.get_player`

Syntax

```
izi.get_player(): game_object
```

Returns

-   `game_object` - The player's game object

Description

Returns a reference to the local player's game object. This is cached for performance and refreshed automatically.

**Example Usage**

```lua
local player = izi.get_player()
local health_pct = player:get_health_percent()
izi.printf("Player health: %.1f%%", health_pct)
```

---

### `izi.target`

Syntax

```
izi.target(): game_object|nil
```

Returns

-   `game_object|nil` - The player's current target, or nil if no target

Description

Returns the player's current target game object, or nil if no target is selected.

**Example Usage**

```lua
local target = izi.target()
if target then
    izi.printf("Target: %s", target:get_name())
else
    izi.print("No target selected")
end
```

---

### `izi.is_in_arena`

Syntax

```
izi.is_in_arena(): boolean
```

Returns

-   `boolean` - True if the player is currently in an arena

Description

Checks if the player is currently in an arena instance. Useful for enabling PvP-specific logic or disabling certain behaviors in arena.

**Example Usage**

```lua
if izi.is_in_arena() then
    izi.print("Arena mode active - adjusting strategy")
end
```

---

### `izi.is_battleground`

Syntax

```
izi.is_battleground(map_id?: integer): boolean
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `map_id` | `integer` | Current map | Optional map ID to check (defaults to current map) |

Returns

-   `boolean` - True if the map is a battleground or arena

Description

Checks if the specified map (or current map) is a battleground or arena instance. This is broader than `is_in_arena()` as it includes all PvP instances.

**Example Usage**

```lua
-- Check current map
if izi.is_battleground() then
    izi.print("In a PvP instance")
end

-- Check a specific map ID
if izi.is_battleground(2107) then
    izi.print("Map 2107 is a battleground")
end
```

---

### `izi.is_bg`

Syntax

```
izi.is_bg(map_id?: integer): boolean
```

Description

Alias for [`izi.is_battleground`](#iziis_battleground). See that function for full documentation.

---

### `izi.get_time_to_die_global`

Syntax

```
izi.get_time_to_die_global(unit: game_object): number
```

**Parameters**

-   `unit: game_object` - The unit to check

Returns

-   `number` - Estimated time in seconds until the unit dies

Description

Returns the estimated time to death for a unit based on recent damage intake. Useful for execute phase detection and priority targeting.

**Example Usage**

```lua
local target = izi.target()
if target then
    local ttd = izi.get_time_to_die_global(target)
    if ttd < 5 then
        izi.print("Target dying soon - execute phase!")
    end
end
```

---

## Buff Removal

### `izi.remove_buff`

Syntax

```
izi.remove_buff(buff_ids: integer|integer[], cache_mult?: number): boolean
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `buff_ids` | `integer\|integer[]` | Required | Single buff ID or array of buff IDs to remove |
| `cache_mult` | `number` | `1.0` | Cache multiplier for performance |

Returns

-   `boolean` - True if a buff was successfully removed

Description

Attempts to remove (right-click cancel) a buff from the player. Useful for removing unwanted buffs like slow fall before combat or cancelaura macros.

**Example Usage**

```lua
-- Remove a single buff
local SLOW_FALL = 130
if izi.remove_buff(SLOW_FALL) then
    izi.print("Removed Slow Fall")
end

-- Remove any of multiple buffs
local BUFFS_TO_REMOVE = {130, 1706}  -- Slow Fall, Levitate
izi.remove_buff(BUFFS_TO_REMOVE)
```
