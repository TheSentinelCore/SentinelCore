---
title: "Waypoint Recorder"
source: "https://docs.project-sylvanas.net/examples/legacy/waypoint-recorder"
crawled: "2026-07-14"
---

# Waypoint Recorder

This example demonstrates how to create a custom waypoint recorder that saves positions to a file with custom formatting.

## What You'll Learn

- How to use core utility functions for waypoint recording
- How to use the file writer utility
- How to define custom waypoint formats
- How to register custom recording callbacks

## Implementation

```lua
local waypoint_writer = require("common/utility/waypoint_writer")

-- Create a custom recorder that defines its own format
waypoint_writer:new_recorder("example_format", function()
    local local_player = core.object_manager.get_local_player()
    if not local_player then
        return "1.00", {}
    end

    local position = local_player:get_position()

    return string.format("%s %s %s", tostring(position.x), tostring(position.y), tostring(position.z)), {}
end)

waypoint_writer:new_recorder("default_format", function()
    local local_player = core.object_manager.get_local_player()
    if not local_player then
        return "1.00", {}
    end

    local position = local_player:get_position()

    return tostring(position.x),{
        tostring(position.y),
        tostring(position.z),
        tostring(local_player:get_facing()),
    }
end)

core.register_on_update_callback(function()
    local local_player = core.object_manager.get_local_player()
    if not local_player then
        return false
    end

    if core.input.is_key_pressed(19) then -- ctrl + s
        -- Add position to file
        -- File name (example.txt)
        -- Path (waypoint/example.txt) (in the main scripts directory)
        -- Example: Scripts/MyScript/waypoint/example.txt
        waypoint_writer:record_position("default_format", "example", "txt")
    end
end)
```

## Format 1: Custom Format

```lua
waypoint_writer:new_recorder("example_format", function()
    local local_player = core.object_manager.get_local_player()
    if not local_player then
        return "1.00", {}
    end

    local position = local_player:get_position()

    return string.format("%s %s %s", tostring(position.x), tostring(position.y), tostring(position.z)), {}
end)
```

The output format is:

```
"0.0 1.0 2.0"
```

## Format 2: Default Format

```lua
waypoint_writer:new_recorder("default_format", function()
    local local_player = core.object_manager.get_local_player()
    if not local_player then
        return "1.00", {}
    end

    local position = local_player:get_position()

    return tostring(position.x),{
        tostring(position.y),
        tostring(position.z),
        tostring(local_player:get_facing()),
    }
end)
```

The output format is:

```
"0.0\n1.0\n2.0\n0.0"
```

## Saving Positions

```lua
waypoint_writer:record_position("default_format", "example", "txt")
```

The position is saved to: `Scripts/MyScript/waypoint/example.txt`

## Related Documentation

- [Custom Waypoints](/examples/custom-waypoints)

## Tips

- **File Location** - Waypoints are saved in the main scripts directory under `waypoint/`
- **Multiple Formats** - You can define as many custom recorders as needed
- **Key Bindings** - Register keybinds in menu elements for user-friendly recording
- **Direction** - Include `get_facing()` for waypoints that need orientation

— Sylvanas
