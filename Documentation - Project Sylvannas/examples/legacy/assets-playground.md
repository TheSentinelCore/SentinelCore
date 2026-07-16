---
title: "Assets Playground (Legacy)"
source: "https://docs.project-sylvanas.net/examples/legacy/assets-playground"
crawled: "2026-07-14"
---

# Assets Playground (Legacy)

This example demonstrates how to use the core graphics API to draw different types of asset representations in the game world.

## What You'll Learn

- How to use the graphics API to render visual elements
- Different types of asset drawing functions
- How to create visual overlays and indicators

## Implementation

```lua
local assets_data = core.assets.get_assets("Interface\\icons")
local myAsset = core.menu.dropdown(assets_data, 1)

local object_type = core.menu.combo_box({"Line", "Circle", "Circle Outlined", "Circle Filled", "Arrow", "Rectangle", "Rectangle Outlined", "Rectangle Filled"}, 1)

local slider_float_size = core.menu.slider_float(0.5, 2.0, 1.0, "Assets Size")

core.register_on_render_callback(function()
    local local_player = core.object_manager.get_local_player()
    if not local_player then return end
    local player_pos = local_player:get_position()

    local text = assets_data[myAsset:get()]

    if object_type:get() == 1 then
        core.graphics.line_2d(text, player_pos)
    end

    if object_type:get() == 2 then
        core.graphics.circle_3d(text, player_pos, slider_float_size:get())
    end

    if object_type:get() == 3 then
        core.graphics.circle_3d_outlined(text, player_pos, slider_float_size:get())
    end

    if object_type:get() == 4 then
        core.graphics.circle_3d_filled(text, player_pos, slider_float_size:get())
    end

    if object_type:get() == 5 then
        core.graphics.arrow_3d(text, player_pos)
    end

    if object_type:get() == 6 then
        core.graphics.rectangle_2d(text, player_pos)
    end

    if object_type:get() == 7 then
        core.graphics.rectangle_3d_outlined(text, player_pos, slider_float_size:get())
    end

    if object_type:get() == 8 then
        core.graphics.rectangle_3d_filled(text, player_pos, slider_float_size:get())
    end
end)
```

## Graphics Functions

| Function | Description |
|----------|-------------|
| `line_2d` | Draws a 2D line in the game world |
| `circle_3d` | Draws a 3D circle outline at a position |
| `circle_3d_outlined` | Draws a 3D circle with outline and texture |
| `circle_3d_filled` | Draws a filled 3D circle at a position |
| `arrow_3d` | Draws a 3D arrow at a position |
| `rectangle_2d` | Draws a 2D rectangle in the game world |
| `rectangle_3d_outlined` | Draws a 3D rectangle with outline and texture |
| `rectangle_3d_filled` | Draws a filled 3D rectangle at a position |

## Loading Assets

```lua
local assets_data = core.assets.get_assets("Interface\\icons")
```

This loads all assets from the specified path. You can use any valid WoW asset path.

## Menu Elements Used

- **dropdown** - Select an asset from the loaded list
- **combo_box** - Choose the rendering type
- **slider_float** - Adjust the size of the rendered element

## Related Documentation

- [Assets API](/dev/api/assets)
- [Graphics API](/dev/api/graphics)
- [Menu Elements](/dev/api/menu)

## Tips

- **Performance** - Rendering too many elements can impact FPS. Limit the number of drawn objects.
- **Positioning** - Use `get_position()` to get the exact location for rendering
- **Asset Paths** - Use `Interface\\icons` for WoW spell/item icons

— Sylvanas
