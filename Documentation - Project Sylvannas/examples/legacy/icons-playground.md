---
title: "Icons Playground (Legacy)"
source: "https://docs.project-sylvanas.net/examples/legacy/icons-playground"
crawled: "2026-07-14"
---

# Icons Playground (Legacy)

This example demonstrates how to use the core graphics API to draw spell and item icons on screen.

## What You'll Learn

- How to draw spell icons on the screen
- How to draw item icons on the screen
- How to get icon textures from the spell book and item database
- How to create custom icon-based UI elements

## Implementation

```lua
local icon_type = core.menu.combo_box({"Spell", "Item"}, 1)

local spell_icon_id = core.menu.slider_int(1, 30000, 1, "Spell ID")
local item_icon_id = core.menu.slider_int(1, 30000, 1, "Item ID")

local slider_float_size_x = core.menu.slider_float(0.1, 5.0, 1.0, "Assets Size X")
local slider_float_size_y = core.menu.slider_float(0.1, 5.0, 1.0, "Assets Size Y")

core.register_on_render_callback(function()
    local local_player = core.object_manager.get_local_player()
    if not local_player then return end

    if icon_type:get() == 1 then
        local spell_texture = core.spell_book.get_spell_texture(spell_icon_id:get())
        core.graphics.image_2d(spell_texture, 10, 200, slider_float_size_x:get(), slider_float_size_y:get(), 1.0)
    end

    if icon_type:get() == 2 then
        local item_texture = core.item.get_item_texture(item_icon_id:get())
        core.graphics.image_2d(item_texture, 10, 200, slider_float_size_x:get(), slider_float_size_y:get(), 1.0)
    end
end)
```

## Key Functions

### Getting Icon Textures

```lua
-- Spell icon
local spell_texture = core.spell_book.get_spell_texture(spell_id)

-- Item icon
local item_texture = core.item.get_item_texture(item_id)
```

### Drawing Icons on Screen

```lua
core.graphics.image_2d(texture, x, y, size_x, size_y, alpha)
```

| Parameter | Description |
|-----------|-------------|
| `texture` | The texture path returned by `get_spell_texture()` or `get_item_texture()` |
| `x` | X position on screen |
| `y` | Y position on screen |
| `size_x` | Horizontal scale |
| `size_y` | Vertical scale |
| `alpha` | Opacity (0.0 to 1.0) |

## Menu Elements Used

- **combo_box** - Choose between Spell and Item icon types
- **slider_int** - Enter spell or item ID
- **slider_float** - Adjust the size of the icon

## Related Documentation

- [Graphics API](/dev/api/graphics)
- [Spell Book API](/dev/api/spellbook)
- [Item API](/dev/api/item)
- [Menu Elements](/dev/api/menu)

## Tips

- **Texture Paths** - Spell and item textures are internal WoW texture paths
- **Finding IDs** - Use `/dump` commands in-game to find spell and item IDs
- **Performance** - Drawing many icons can impact performance; consider batching renders
- **Screen Position** - X and Y coordinates are in screen pixels, not game world coordinates

— Sylvanas
