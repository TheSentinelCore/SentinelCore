---
title: "Map Click to Nav Advanced"
source: "https://docs.project-sylvanas.net/dev/examples/navmesh-playground-advanced"
crawled: "2026-07-14"
---

# Map Click to Nav Advanced

## Overview

Map Click to Nav Advanced is an upgraded version of the Nav Playground that replaces the notification-based confirmation flow with a **native-looking map button** — a UI element rendered directly on the in-game map that feels like part of the game itself. Click the button, the map enters targeting mode with a crosshair cursor and yellow overlay, click your destination, and your character starts walking.

**What's different from the basic version:**
- **Map Button UI** — a styled button rendered directly on the map, with hover effects and DPI scaling
- **Targeting Overlay** — the map gets a yellow tint and border while in targeting mode, with a crosshair cursor
- **No Confirmation Step** — click the button → click the map → walking starts immediately
- **Window-Based Rendering** — demonstrates `register_on_render_window_callback` and custom window drawing
- **DPI-Aware Layout** — button sizes and fonts scale automatically based on screen resolution
- **Configurable Position** — slider controls to reposition the button anywhere on the map

## How It Works

```
┌──────┐   click button  ┌───────────┐   click map   ┌────────────┐
│ IDLE │ ─────────────▶ │ TARGETING  │ ───────────▶ │  WALKING   │
└──────┘                 └───────────┘               └────────────┘
   ▲                          │                            │
   │   button toggle / MMB    │      MMB or arrival        │
   │◀─────────────────────────┘◀──────────────────────────┘
```

1. **Idle** — a dark "CLICK TO MOVE" button sits in the corner of the map.
2. **Targeting** — button turns yellow and reads "CLICK MAP". The map gets a yellow tint overlay with a crosshair cursor. A CANCEL button appears alongside. Click anywhere on the map to set your destination.
3. **Walking** — button turns green and reads "WALKING...". Your character follows the navmesh path. A CANCEL button remains visible. When the map is closed, a HUD banner shows on-screen.

## Key New Features

### State Machine

```lua
local STATE_IDLE      = 1
local STATE_TARGETING = 2
local STATE_WALKING   = 3
local state = STATE_IDLE
```

### Map Bounds Detection

```lua
local function get_map_bounds_screen()
    local tl = core.game_ui.get_map_top_left()
    local br = core.game_ui.get_map_bottom_right()
    if not tl or not br then return nil end
    local tl_scr = core.game_ui.ui_pos_to_screen_pos(tl)
    local br_scr = core.game_ui.ui_pos_to_screen_pos(br)
    if not tl_scr or not br_scr then return nil end
    return {
        x1 = math.min(tl_scr.x, br_scr.x),
        y1 = math.min(tl_scr.y, br_scr.y),
        x2 = math.max(tl_scr.x, br_scr.x),
        y2 = math.max(tl_scr.y, br_scr.y),
    }
end
```

### DPI-Aware Button Sizing

```lua
local function get_btn_layout()
    local screen_size = core.graphics.get_screen_size()
    local btn_size = vec2.new(120, 34)
    local font_id = enums.window_enums.font_id.FONT_SMALL
    local gap = 4
    if screen_size.y >= 2000 then
        btn_size = vec2.new(180, 51)
        font_id = enums.window_enums.font_id.FONT_SEMI_BIG
        gap = 6
    elseif screen_size.y >= 1440 then
        btn_size = vec2.new(148, 42)
        font_id = enums.window_enums.font_id.FONT_NORMAL
        gap = 5
    end
    return btn_size, font_id, gap
end
```

### Custom Window Button

```lua
local walk_btn   = core.menu.window("nav_pg_walk_btn")
local cancel_btn = core.menu.window("nav_pg_cancel_btn")

local function render_map_button(win, pos, size, font_id, label, bg, text_col)
    win:set_initial_size(size)
    win:set_next_window_min_size(size)
    win:force_window_size(size)
    win:force_next_begin_window_pos(pos)
    local clicked = false
    win:set_render_layer(1)
    win:begin(
        enums.window_enums.window_resizing_flags.NO_RESIZE,
        false, bg, bg,
        enums.window_enums.window_cross_visuals.NO_CROSS,
        function()
            win:push_font(font_id)
            local is_hovering = win:is_mouse_hovering_rect(
                vec2.new(0, 0), win:get_size()
            )
            if is_hovering then
                win:render_rect_filled(
                    vec2.new(0, 0), win:get_size(),
                    color.new(255, 255, 255, 35), 0
                )
            end
            win:render_text(
                font_id,
                vec2.new(
                    win:get_text_centered_x_pos(label),
                    win:get_size().y * 0.5
                        - win:get_text_size(label).y * 0.5
                ),
                text_col,
                label
            )
            win:set_next_window_min_size(size)
            win:force_next_begin_window_pos(pos)
            if win:is_rect_clicked(
                vec2.new(0, 0), vec2.new(0, 0) + win:get_size()
            ) then
                clicked = true
            end
        end
    )
    return clicked
end
```

### Targeting Overlay

```lua
if state == STATE_TARGETING then
    local w = bounds.x2 - bounds.x1
    local h = bounds.y2 - bounds.y1
    core.graphics.rect_2d_filled(
        vec2.new(bounds.x1, bounds.y1), w, h, c_target_bg
    )
    core.graphics.rect_2d(
        vec2.new(bounds.x1, bounds.y1),
        w, h, c_target, 2
    )
    local cursor = core.get_cursor_position()
    if cursor then
        core.graphics.circle_2d(cursor, 12, c_target, 2)
        core.graphics.circle_2d(cursor, 4, c_target, 2)
    end
    core.graphics.text_2d(
        "Click anywhere on the map | MMB to cancel",
        vec2.new(20, 20), 16, c_target, false
    )
end
```

## Comparison with Basic Version

| Feature | Basic (Nav Playground) | Advanced |
|---------|----------------------|----------|
| Confirmation method | Notification popup | Map button + targeting overlay |
| Clicks to start walking | 3 (map click → wait → notif click) | 2 (button → map click) |
| Visual targeting state | None | Yellow overlay + crosshair |
| Button on map | No | Yes, DPI-scaled |
| Render callbacks | `on_render` only | `on_render` + `on_render_window` |
| Button repositioning | N/A | Percentage-based sliders |
| State management | 3 separate variables | Clean state enum |

## Key Patterns to Reuse

| Pattern | Where in Code | Reuse For |
|---------|---------------|-----------|
| Map bounds detection | `get_map_bounds_screen()` | Any UI overlay on the in-game map |
| DPI-aware sizing | `get_btn_layout()` resolution tiers | Scaling any custom UI across resolutions |
| Window-based button | `render_map_button()` | Styled clickable buttons anywhere on screen |
| Targeting overlay | `rect_2d_filled` + `rect_2d` + cursor circles | Any "aim mode" or "selection mode" UI |
| Screen-space click marker | `click_screen_pos` saved on click | Showing where the user clicked on 2D surfaces |
| Render callback separation | `on_render_window` vs `on_render` | Keeping 2D UI and 3D world drawing organized |
| Proportional positioning | Slider % × map dimensions | Resolution-independent element placement |
| Auto-cancel on context loss | Check `is_map_open()` in update | Cleaning up state when UI context disappears |
| State enum | `STATE_IDLE` / `STATE_TARGETING` / `STATE_WALKING` | Any multi-mode plugin with clean transitions |

## Requirements

- **[Nasrine's NavLib](https://project-sylvanas.net/panel/plugins/detail/414)** — The navmesh pathfinding library must be loaded (`_G.NavLib` must exist)
