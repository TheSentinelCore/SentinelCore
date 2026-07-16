---
title: "Map Playground"
source: "https://docs.project-sylvanas.net/examples/izi/map_playground"
crawled: "2026-07-14"
---

# Map Playground Example

This example demonstrates how to interact with the World of Warcraft minimap using the **IZI SDK**. We'll build a plugin that lets you click on the map to place 3D markers in the game world, with support for adding, removing, and clearing markers.

## What You'll Learn

- How to detect map clicks with `izi.on_key_release()`
- Converting map cursor position to world coordinates with `izi.get_cursor_world_pos()`
- Checking if the map is open with `core.game_ui.is_map_open()`
- Drawing 3D circles and lines for marker visualization
- Managing a collection of world positions
- Finding the nearest marker for removal

## Plugin Structure

### header.lua

```lua
local plugin = {}
plugin.name = "Map Playground"
plugin.version = "1.0.0"
plugin.author = "Silvi"
plugin.load = true

local local_player = core.object_manager.get_local_player()
if not local_player or not local_player:is_valid() then
    plugin.load = false
    return plugin
end

return plugin
```

### main.lua

```lua
--[[
    Map Playground - Minimap interaction with IZI SDK

    This plugin demonstrates how to:
    - Detect mouse clicks on the minimap
    - Convert map cursor position to world coordinates
    - Place and manage 3D markers in the game world
    - Draw visual feedback (circles, lines, HUD)

    Controls:
    - Left-click on minimap: Add a marker
    - Right-click on minimap: Remove nearest marker
    - Middle-click on minimap: Clear all markers

    Author: Silvi
]]--

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================
local vec2 = require("common/geometry/vector_2")
local vec3 = require("common/geometry/vector_3")
local color = require("common/color")
local izi = require("common/izi_sdk")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local CONFIG ={
    marker_radius = 1.5,
    marker_thickness = 2.0,
    marker_fade = 2.5,
    marker_color = color.green(),
    line_color = color.cyan(),
    remove_threshold = 8.0,
}

-- ============================================================================
-- KEY CODES
-- ============================================================================
local VK_LBUTTON = 0x01  -- Left mouse button
local VK_RBUTTON = 0x02  -- Right mouse button
local VK_MBUTTON = 0x04  -- Middle mouse button

-- ============================================================================
-- MARKER STORAGE
-- ============================================================================
local markers ={}  -- Array of vec3 world positions

-- ============================================================================
-- MARKER FUNCTIONS
-- ============================================================================
local function add_marker(world_pos)
    markers[#markers + 1] = world_pos
    core.log("[MapPlayground] Marker added: (" ..
        string.format("%.1f", world_pos.x) .. ", " ..
        string.format("%.1f", world_pos.y) .. ", " ..
        string.format("%.1f", world_pos.z) .. ")")
end

local function find_nearest_marker(world_pos)
    local nearest_idx = nil
    local nearest_dist = CONFIG.remove_threshold * CONFIG.remove_threshold
    for i, marker in ipairs(markers) do
        local dist = marker:squared_dist_to_ignore_z(world_pos)
        if dist < nearest_dist then
            nearest_dist = dist
            nearest_idx = i
        end
    end
    return nearest_idx
end

local function remove_marker(world_pos)
    local idx = find_nearest_marker(world_pos)
    if idx then
        local removed = markers[idx]
        table.remove(markers, idx)
        core.log("[MapPlayground] Marker removed: (" ..
            string.format("%.1f", removed.x) .. ", " ..
            string.format("%.1f", removed.y) .. ")")
        return true
    end
    return false
end

local function clear_markers()
    local count = #markers
    markers ={}
    if count > 0 then
        core.log("[MapPlayground] Cleared " .. count .. " markers")
    end
end

-- ============================================================================
-- CLICK HANDLERS
-- ============================================================================
local function handle_left_click()
    if core.graphics.is_menu_open() then return end
    if not core.game_ui.is_map_open() then return end
    local world_pos = izi.get_cursor_world_pos()
    if world_pos then
        add_marker(world_pos)
    end
end

local function handle_right_click()
    if core.graphics.is_menu_open() then return end
    if not core.game_ui.is_map_open() then return end
    local world_pos = izi.get_cursor_world_pos()
    if world_pos then
        remove_marker(world_pos)
    end
end

local function handle_middle_click()
    if core.graphics.is_menu_open() then return end
    if not core.game_ui.is_map_open() then return end
    clear_markers()
end

-- ============================================================================
-- REGISTER KEY CALLBACKS
-- ============================================================================
izi.on_key_release(VK_LBUTTON, handle_left_click)
izi.on_key_release(VK_RBUTTON, handle_right_click)
izi.on_key_release(VK_MBUTTON, handle_middle_click)

-- ============================================================================
-- RENDER CALLBACK
-- ============================================================================
local function on_render()
    local player = core.object_manager.get_local_player()
    if not player then return end
    local player_pos = player:get_position()

    for _, marker in ipairs(markers) do
        core.graphics.circle_3d(
            marker,
            CONFIG.marker_radius,
            CONFIG.marker_color,
            CONFIG.marker_thickness,
            CONFIG.marker_fade
        )
        core.graphics.line_3d(
            player_pos,
            marker,
            CONFIG.line_color,
            3,
            1.5,
            true
        )
    end

    if #markers > 0 then
        local hud_text = "Markers: " .. #markers .. " | MMB to clear"
        core.graphics.text_2d(hud_text, vec2.new(20, 20), 16, CONFIG.marker_color, false)
    end
end
core.register_on_render_callback(on_render)

-- ============================================================================
-- STARTUP LOG
-- ============================================================================
core.log("[MapPlayground] Loaded! LMB=Add, RMB=Remove, MMB=Clear")
```

## Code Breakdown

### 1. Key IZI Functions

```lua
-- Get world position from where cursor is pointing on the map
local world_pos = izi.get_cursor_world_pos()

-- Register a callback for when a key is released
izi.on_key_release(VK_LBUTTON, handle_left_click)
```

### 2. Checking Map State

```lua
local function handle_left_click()
    -- Don't process if our menu is open
    if core.graphics.is_menu_open() then return end
    -- Only process clicks when the game map is open
    if not core.game_ui.is_map_open() then return end
    -- Now safe to get map cursor position
    local world_pos = izi.get_cursor_world_pos()
    -- ...
end
```

**Important checks before processing map clicks:**
1. `core.graphics.is_menu_open()` - Skip if plugin menu is open
2. `core.game_ui.is_map_open()` - Only process when map is visible

### 3. Converting Map to World Coordinates

```lua
local world_pos = izi.get_cursor_world_pos()
```

This single function call:
1. Gets the current map ID
2. Gets the normalized cursor position on the map
3. Converts map coordinates to world X/Y
4. Calculates the terrain height (Z) at that position
5. Returns a complete `vec3` world position

**Without IZI, you'd need:**
```lua
-- The hard way (what IZI does internally)
local map_id = core.game_ui.get_current_map_id()
local cursor = core.game_ui.get_normalized_cursor_position()
local world_2d = core.game_ui.get_world_pos_from_map_pos(map_id, cursor)
local height = core.get_height_for_position(vec3.new(world_2d.x, world_2d.y, 0))
local world_pos = vec3.new(world_2d.x, world_2d.y, height)

-- The easy way (IZI)
local world_pos = izi.get_cursor_world_pos()
```

### 4. Registering Key Callbacks

```lua
local VK_LBUTTON = 0x01  -- Left mouse
local VK_RBUTTON = 0x02  -- Right mouse
local VK_MBUTTON = 0x04  -- Middle mouse

izi.on_key_release(VK_LBUTTON, handle_left_click)
izi.on_key_release(VK_RBUTTON, handle_right_click)
izi.on_key_release(VK_MBUTTON, handle_middle_click)
```

`izi.on_key_release()` fires once when a key is released. Better than checking `is_key_pressed()` every frame because:
- Fires exactly once per click
- No need to track previous key state
- Cleaner code without state management

### 5. Finding the Nearest Marker

```lua
local function find_nearest_marker(world_pos)
    local nearest_idx = nil
    local nearest_dist = CONFIG.remove_threshold * CONFIG.remove_threshold
    for i, marker in ipairs(markers) do
        local dist = marker:squared_dist_to_ignore_z(world_pos)
        if dist < nearest_dist then
            nearest_dist = dist
            nearest_idx = i
        end
    end
    return nearest_idx
end
```

**Performance tip:** Use `squared_dist_to_ignore_z()` instead of `dist_to()` when comparing distances. Squared distance avoids the expensive square root calculation.

### 6. Drawing 3D Markers

```lua
-- Draw circle at marker position
core.graphics.circle_3d(
    marker,                  -- vec3 position
    CONFIG.marker_radius,    -- radius in yards
    CONFIG.marker_color,     -- color
    CONFIG.marker_thickness, -- line thickness
    CONFIG.marker_fade       -- fade factor
)

-- Draw line from player to marker
core.graphics.line_3d(
    player_pos,          -- start position
    marker,              -- end position
    CONFIG.line_color,   -- color
    3,                   -- thickness
    1.5,                 -- fade factor
    true                 -- has_volume (3D depth)
)
```

## IZI SDK Map API Reference

### Functions

| Function | Description |
|----------|-------------|
| `izi.get_cursor_world_pos()` | Get world vec3 from map cursor position |
| `izi.on_key_release(key, callback)` | Register callback for key release event |
| `izi.on_key_press(key, callback)` | Register callback for key press event |

### Related Core Functions

| Function | Description |
|----------|-------------|
| `core.game_ui.is_map_open()` | Check if world map is open |
| `core.graphics.is_menu_open()` | Check if plugin menu is open |
| `core.game_ui.get_current_map_id()` | Get current map ID |
| `core.game_ui.get_world_pos_from_map_pos()` | Convert map coords to world |

### Common Virtual Key Codes

| Code | Constant | Key |
|------|----------|-----|
| `0x01` | `VK_LBUTTON` | Left mouse button |
| `0x02` | `VK_RBUTTON` | Right mouse button |
| `0x04` | `VK_MBUTTON` | Middle mouse button |
| `0x70` | `VK_F1` | F1 key |
| `0x74` | `VK_F5` | F5 key |
| `0x1B` | `VK_ESCAPE` | Escape key |

## Customization

### Changing Marker Appearance

```lua
local CONFIG ={
    marker_radius = 2.0,
    marker_thickness = 3.0,
    marker_color = color.yellow(),
    line_color = color.red(),
}
```

### Adding Marker Labels

```lua
local function on_render()
    for i, marker in ipairs(markers) do
        core.graphics.circle_3d(marker, CONFIG.marker_radius, CONFIG.marker_color, 2, 2.5)
        local label_pos = vec3.new(marker.x, marker.y, marker.z + 2)
        core.graphics.text_3d("Marker " .. i, label_pos, 14, color.white(), true)
    end
end
```

### Saving Markers to File

```lua
local function save_markers()
    if #markers == 0 then return end
    local data ={}
    for i, m in ipairs(markers) do
        data[i] = string.format('{"x":%.2f,"y":%.2f,"z":%.2f}', m.x, m.y, m.z)
    end
    local content = "[" .. table.concat(data, ",") .. "]"
    core.create_data_file("markers.json")
    core.write_data_file("markers.json", content)
    core.log("Saved " .. #markers .. " markers")
end

local function load_markers()
    local content = core.read_data_file("markers.json")
    if not content or content == "" then return end
    markers ={}
    for x, y, z in content:gmatch('{"x":([%d%.%-]+),"y":([%d%.%-]+),"z":([%d%.%-]+)}') do
        markers[#markers + 1] = vec3.new(tonumber(x), tonumber(y), tonumber(z))
    end
    core.log("Loaded " .. #markers .. " markers")
end
```

### Using Markers for Navigation

```lua
local movement = require("common/utility/simple_movement")

local function navigate_to_markers()
    if #markers == 0 then return end
    movement:navigate(markers, false, true)
end
```

## Related Documentation

- [IZI SDK Reference](/dev/libraries/izi) - Complete IZI SDK documentation
- [Game UI API](/dev/api/game-ui) - Map and UI functions
- [Graphics API](/dev/api/graphics) - Drawing functions
- [Input API](/dev/api/input) - Key detection
- [Simple Movement](/dev/api/simple-movement) - Automated navigation

## Tips

- **Map Must Be Open** - `izi.get_cursor_world_pos()` only works when the world map is open. Always check `core.game_ui.is_map_open()` before calling it.
- **Menu Overlap** - When the plugin menu is open, clicks might be intended for the menu. Check `core.graphics.is_menu_open()` to avoid unintended marker placement.
- **Key Release vs Press** - Use `on_key_release()` for click actions to ensure the callback fires exactly once per click.
- **Squared Distance** - When comparing distances, use `squared_dist_to_ignore_z()` instead of `dist_to()` for better performance.

## Conclusion

This Map Playground example demonstrates powerful map interaction capabilities using the IZI SDK. By combining `izi.get_cursor_world_pos()` with `izi.on_key_release()`, you can create intuitive tools that let users interact with the game world through the minimap.

**Key Takeaways:**
- `izi.get_cursor_world_pos()` - One-liner to get world position from map cursor
- `izi.on_key_release()` - Clean callback registration for mouse/key events
- `core.game_ui.is_map_open()` - Essential check before map interactions
- Squared Distance - Use for performance when comparing distances
- 3D Visualization - `circle_3d()` and `line_3d()` for marker display
