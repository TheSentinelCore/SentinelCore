---
title: "World Functions"
source: "https://docs.project-sylvanas.net/dev/api/world"
crawled: "2026-07-14"
---

# World Functions

## Overview

The `core.world` module exposes world-level state queries, including flying availability, map encounter positions, and active Mythic+ keystone information.

---

### `core.world.is_flyable_area`

**Syntax:**
```lua
core.world.is_flyable_area() -> boolean
```

**Returns:** `boolean` - `true` if the current area allows regular flying, `false` otherwise.

**Description:** Returns whether the current area allows regular flying.

**Example Usage:**
```lua
if core.world.is_flyable_area() then
    core.log("Regular flying is available here")
end
```

---

### `core.world.is_advanced_flyable_area`

**Syntax:**
```lua
core.world.is_advanced_flyable_area() -> boolean
```

**Returns:** `boolean` - `true` if the current area allows advanced flying, `false` otherwise.

**Description:** Returns whether the current area allows advanced dynamic flying or skyriding.

**Example Usage:**
```lua
if core.world.is_advanced_flyable_area() then
    core.log("Advanced flying is available here")
end
```

---

### `core.world.get_encounters_on_map`

**Syntax:**
```lua
core.world.get_encounters_on_map(ui_map_id: integer) -> encounter_info[]
```

**Parameters:**
- `ui_map_id`: `integer` - The UI map ID to query encounters for.

**Returns:** `encounter_info[]` - An array of encounter info tables.

Each encounter table contains:

| Field | Type | Description |
|-------|------|-------------|
| `encounter_id` | `integer` | The encounter ID |
| `map_x` | `number` | The normalized X position on the map |
| `map_y` | `number` | The normalized Y position on the map |

**Description:** Returns encounter data for the specified UI map ID. Each entry contains the encounter ID and its normalized map position.

**Example Usage:**
```lua
local map_id = core.game_ui.get_current_map_id()
local encounters = core.world.get_encounters_on_map(map_id)
for _, encounter in ipairs(encounters) do
    core.log(string.format(
        "Encounter %d at %.2f, %.2f",
        encounter.encounter_id,
        encounter.map_x,
        encounter.map_y
    ))
end
```

---

### `core.world.get_active_keystone_info`

**Syntax:**
```lua
core.world.get_active_keystone_info() -> active_keystone_info
```

**Returns:** `active_keystone_info` - A table containing active Mythic+ keystone data. Returns an empty table when unavailable or when no active keystone exists.

The returned table contains:

| Field | Type | Description |
|-------|------|-------------|
| `level` | `integer` | The active keystone level |
| `was_charged` | `boolean` | Whether the active keystone was charged |
| `affix_ids` | `integer[]` | The active keystone affix IDs |

**Description:** Returns active Mythic+ keystone information from the client challenge mode API.

**Example Usage:**
```lua
local keystone = core.world.get_active_keystone_info()
if keystone.level then
    core.log("Active keystone level: " .. keystone.level)
    for _, affix_id in ipairs(keystone.affix_ids) do
        core.log("Affix: " .. affix_id)
    end
end
```
