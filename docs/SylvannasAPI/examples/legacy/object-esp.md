---
title: "Object ESP"
source: "https://docs.project-sylvanas.net/examples/legacy/object-esp"
crawled: "2026-07-14"
---

# Object ESP Example

This example demonstrates how to create an ESP (Extra Sensory Perception) system for game objects using the Project Sylvanas API. We'll build a plugin that tracks and displays Ancient Mana objects for Legion Remix, but the concepts apply to any object type.

## What You'll Learn

- How to validate the local player before plugin initialization
- Best practices for defining constants instead of using magic numbers
- Efficient object filtering using lookup tables
- Performance optimization through caching
- Proper iteration techniques for large datasets
- Drawing text on objects
- Using labels for loop control flow

## Plugin Structure

### header.lua

```lua
local plugin = {}
plugin.name = "Object ESP"
plugin.version = "1.01"
plugin.author = "Voltz"
plugin.load = true

local local_player = core.object_manager:get_local_player()
if not local_player or not local_player:is_valid() then
    plugin.load = false
    return plugin
end

return plugin
```

### main.lua

```lua
local object_ids ={
    [252408] = true, --Ancient Mana Shard (gives 10 ancient mana)
    [252772] = true, --Ancient Mana Chunk (gives 20 ancient mana)
    [252774] = true, --Ancient Mana Crystal (gives 50 - 100 ancient mana)
}

local color = require("common/color")

local TEXT_COLOR = color.white(200)
local TEXT_SIZE = 12
local TEXT_CENTERED = true
local TEXT_FONT = 10
local TEXT_Z_OFFSET = -0.25

local CACHE_UPDATE_RATE_MS = 500
local last_cache_update_ms = 0
---@type game_object[]
local objects_to_draw ={}

core.register_on_render_callback(function()
    for i = 1, #objects_to_draw do
        local object = objects_to_draw[i]
        if not object or not object.is_valid or not object:is_valid() then
            goto continue
        end
        local name = object:get_name()
        local pos = object:get_position()
        local scale = object:get_scale()
        pos.z = pos.z + TEXT_Z_OFFSET * scale
        core.graphics.text_3d(name, pos, TEXT_SIZE, TEXT_COLOR, TEXT_CENTERED, TEXT_FONT)
        ::continue::
    end
end)

core.register_on_update_callback(function()
    local current_time_ms = core.game_time()
    local time_since_last_update_ms = current_time_ms - last_cache_update_ms
    if time_since_last_update_ms > CACHE_UPDATE_RATE_MS then
        local objects = core.object_manager:get_all_objects()
        objects_to_draw ={}
        for i = 1, #objects do
            local object = objects[i]
            local id = object:get_npc_id()
            if object_ids[id] then
                table.insert(objects_to_draw, object)
            end
        end
        last_cache_update_ms = current_time_ms
    end
end)
```

## Code Breakdown

### 1. Object ID Lookup Table

```lua
local object_ids ={
    [252408] = true,
    [252772] = true,
    [252774] = true,
}
```

Using a lookup table instead of an array allows O(1) constant-time lookups instead of O(n) linear searches.

### 2. Constants for Drawing Configuration

```lua
local TEXT_COLOR = color.white(200)
local TEXT_SIZE = 12
local TEXT_CENTERED = true
local TEXT_FONT = 10
local TEXT_Z_OFFSET = -0.25
```

Defining constants at the top makes the code maintainable and avoids "magic numbers".

### 3. Caching System

The caching system updates at a fixed interval (500ms) instead of every game tick. This provides a **30x performance improvement** while objects rarely change that quickly.

### 4. Render Callback

```lua
for i = 1, #objects_to_draw do
    local object = objects_to_draw[i]
    if not object or not object.is_valid or not object:is_valid() then
        goto continue
    end
    local name = object:get_name()
    local pos = object:get_position()
    local scale = object:get_scale()
    pos.z = pos.z + TEXT_Z_OFFSET * scale
    core.graphics.text_3d(name, pos, TEXT_SIZE, TEXT_COLOR, TEXT_CENTERED, TEXT_FONT)
    ::continue::
end
```

- Uses traditional `for i = 1, #table` loop for maximum performance
- Validates objects with `is_valid()` before accessing properties
- Uses `goto continue` label to skip invalid objects efficiently
- Adjusts Z position based on object scale for proper text placement

## Performance Optimizations

### Traditional For Loops vs ipairs/pairs

```lua
-- Fast (recommended)
for i = 1, #objects do
    local object = objects[i]
end

-- Slower
for i, object in ipairs(objects) do end

-- Slowest
for i, object in pairs(objects) do end
```

### Lookup Tables vs Arrays

```lua
-- Fast: O(1) lookup
if object_ids[id] then -- found end

-- Slow: O(n) lookup
for i = 1, #object_ids_array do
    if object_ids_array[i] == id then -- found end
end
```

## Customization

### Adding More Object Types

```lua
local object_ids ={
    [252408] = true,
    [252772] = true,
    [252774] = true,
    [123456] = true,
    [789012] = true,
}
```

### Changing Appearance

```lua
local TEXT_COLOR = color.cyan(255)
local TEXT_SIZE = 16
local TEXT_Z_OFFSET = 1.0
```

## Related Documentation

- [Object Manager API](/dev/api/object-manager)
- [Game Object Functions](/dev/api/game-object)
- [Graphics API](/dev/api/graphics)
- [Color API](/dev/api/color)

## Tips

- **Performance** - If tracking many objects, consider increasing `CACHE_UPDATE_RATE_MS`
- **Object Validity** - Always check `object:is_valid()` before accessing properties
- **In Practice** - Use `unit_manager:get_cache_object_list()` which handles caching automatically

## Conclusion

This Object ESP example demonstrates essential techniques for working with game objects efficiently. By implementing manual caching and optimization patterns, you've learned the fundamental principles that power the higher-level helper libraries.

**Key Takeaways:**
- Lookup Tables - Use key-value tables for O(1) constant-time lookups
- Caching Strategy - Update object lists at fixed intervals for 30x+ performance gains
- Traditional For Loops - Use `for i = 1, #table` instead of `ipairs()` or `pairs()`
- Constants - Define configuration values at the top
- Label Control Flow - Use `goto continue` labels for clean loop control
- Validation - Always check `object:is_valid()` before accessing properties

— Voltz
