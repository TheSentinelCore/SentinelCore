---
title: "Damage Meter"
source: "https://docs.project-sylvanas.net/dev/api/damage-meter"
crawled: "2026-07-14"
---

# Damage Meter Functions

## Overview

The `core.damage_meter` module provides access to the in-game damage meter (`C_DamageMeter`). You can query combat sessions, retrieve per-player breakdowns, and reset data.

> **note**: This API requires the game's built-in damage meter to be available. Use `is_available()` to check before calling other functions.

---

### `core.damage_meter.is_available`

```
core.damage_meter.is_available() -> boolean, string
```

Returns:
- `boolean`: Whether the damage meter API is available.
- `string`: The reason it is unavailable (empty string if available).

Description: Checks if the damage meter API is currently available. Should be called before using other `core.damage_meter` functions.

**Example Usage**

```lua
local available, reason = core.damage_meter.is_available()
if not available then
    core.log("Damage meter unavailable: " .. reason)
    return
end
```

---

### `core.damage_meter.get_available_sessions`

```
core.damage_meter.get_available_sessions() -> table[]
```

Returns:
- `table[]`: Array of session entries. Each entry contains:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | `integer` | The session identifier |
| `name` | `string` | The session name |
| `duration` | `number` | The session duration in seconds |

Description: Returns all available combat sessions from the damage meter.

**Example Usage**

```lua
local sessions = core.damage_meter.get_available_sessions()
for _, s in ipairs(sessions) do
    core.log(s.name .. " - " .. s.duration .. "s")
end
```

---

### `core.damage_meter.get_session_from_id`

```
core.damage_meter.get_session_from_id(session_id: integer, meter_type: integer) -> table
```

**Parameters**
- `session_id`: `integer` - The session ID (from `get_available_sessions`).
- `meter_type`: `integer` - The meter type (e.g. damage, healing).

Returns:
- `table`: A session table with the following structure:

| Field | Type | Description |
|-------|------|-------------|
| `max_amount` | `number` | Highest amount from a single source |
| `total_amount` | `number` | Total combined amount |
| `duration` | `number` | Session duration in seconds |
| `sources` | `table[]` | Array of combatant entries (see below) |

Each entry in `sources`:

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | The combatant name |
| `class` | `string` | The class filename |
| `total_amount` | `number` | Total amount dealt/healed |
| `per_second` | `number` | Amount per second |
| `is_local_player` | `boolean` | Whether this is the local player |
| `spec_icon` | `integer` | Specialization icon ID |
| `unit` | `game_object\|nil` | The game object if found in the world |

Description: Returns detailed combat session data by session ID, including per-player breakdowns. The `unit` field in each source is resolved by matching the combatant name against visible game objects.

**Example Usage**

```lua
local session = core.damage_meter.get_session_from_id(1, 0)
for _, src in ipairs(session.sources) do
    core.log(src.name .. " (" .. src.class .. "): " .. src.per_second .. " DPS")
end
```

---

### `core.damage_meter.get_session_from_type`

```
core.damage_meter.get_session_from_type(session_type: integer, meter_type: integer) -> table
```

**Parameters**
- `session_type`: `integer` - The session type:
  - `0`: Overall
  - `1`: Current
  - `2`: Expired
- `meter_type`: `integer` - The meter type (e.g. damage, healing).

Returns:
- `table`: A session table (same structure as `get_session_from_id`).

Description: Returns detailed combat session data by session type instead of ID. Useful for quickly accessing the current or overall session.

**Example Usage**

```lua
-- Get current session damage data
local current = core.damage_meter.get_session_from_type(1, 0)
core.log("Total damage: " .. current.total_amount)
```

---

### `core.damage_meter.get_session_duration`

```
core.damage_meter.get_session_duration(session_type: integer) -> number
```

**Parameters**
- `session_type`: `integer` - The session type (0=Overall, 1=Current, 2=Expired).

Returns:
- `number`: The session duration in seconds.

Description: Returns the duration of a combat session by type. Returns `0` if no session exists.

**Example Usage**

```lua
local duration = core.damage_meter.get_session_duration(1)
core.log("Current fight: " .. duration .. " seconds")
```

---

### `core.damage_meter.reset_all`

```
core.damage_meter.reset_all() -> nil
```

Description: Resets all combat sessions in the damage meter.

**Example Usage**

```lua
core.damage_meter.reset_all()
core.log("Damage meter reset")
```
