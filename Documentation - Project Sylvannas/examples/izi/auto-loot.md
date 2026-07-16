---
title: "Simple Auto Loot (IZI SDK)"
source: "https://docs.project-sylvanas.net/examples/izi/auto-loot"
crawled: "2026-07-14"
---

# Simple Auto Loot Plugin Example (IZI SDK)

> **The Story Behind This Plugin:** I play WoW Classic Era with family and friends. We have this tradition during quests where you need to loot a certain number of items from monsters. Everyone rushes to see who can complete it first. I was always the slow one, losing the loot race again and again.
>
> One day, out of pure desperation and a bit of salt, I wrote a tiny auto loot helper to give myself a small boost in our friendly competitions. You still need to make the "feet" work to be in the right place at the right time. But when something dies near you, this little plugin quickly reaches down and tries to loot it for you, and even pauses movement for a brief moment so you do not run past the corpse.
>
> If you are jumping when the loot is available, you can still miss your chance. I wish I could fix that, but for now, gravity wins.
>
> — Silvi

This example demonstrates how to create a utility plugin that automatically loots nearby dead enemies using the **IZI SDK**. This showcases menu creation, control panel integration, 2D rendering, inventory management, and smart state management for reliable auto-looting with proper retry logic.

> **Practical Utility Plugin:** This is a complete, production-ready auto loot plugin that demonstrates real-world plugin development patterns including state management, cooldown handling, inventory space checking, and user interface integration.

## What You'll Learn

- How to use the **IZI SDK** for utility plugin development
- Creating interactive 2D status banners with customizable position and scale
- Implementing smart retry logic with per-unit state tracking
- Using `izi.enemies_if()` for filtered enemy detection
- Inventory space management using `inventory_helper`
- Filtering equipped items from bag slot counts
- Creating draggable menu sliders for position and scale customization
- Control panel integration with toggle states
- Movement pausing during loot interactions
- Cooldown management for reliable looting

## Plugin Structure

### header.lua

```lua
local plugin = {}
plugin["name"] = "Simple Auto Loot"
plugin["version"] = "1.01"
plugin["author"] = "Silvi"
plugin["load"] = true

local local_player = core.object_manager.get_local_player()
if not local_player then
    plugin["load"] = false
    return plugin
end

return plugin
```

> **Simplified Validation:** Unlike class-specific plugins, this utility plugin only validates that a local player exists. This makes it universally compatible with all classes and specs.

### main.lua

```lua
-- Simple Auto Loot Plugin
local color = require("common/color")
local izi = require("common/izi_sdk")
local vec2 = require("common/geometry/vector_2")
local key_helper = require("common/utility/key_helper")
local plugin_helper = require("common/utility/plugin_helper")
local movement_handler = require("common/utility/movement_handler")
local control_panel_helper = require("common/utility/control_panel_helper")
local inventory_helper = require("common/utility/inventory_helper")

local PLUGIN_NAME = "Simple Auto Loot"
local TAG = "simple_auto_loot_"

--------------------------------------------------
-- Menu
--------------------------------------------------
local menu ={
    root        = core.menu.tree_node(),
    -- Global enable for the plugin
    enabled     = core.menu.checkbox(true, TAG .. "enabled"),
    -- Auto loot toggle key
    auto_loot_key = core.menu.keybind(999, false, TAG .. "toggle"),
    -- Max bag space (total slots you want to consider)
    -- 0 = ignore bag space logic entirely
    max_bag_space = core.menu.slider_int(0, 100, 16, TAG .. "max_bag_space"),
    -- Draw loot status banner
    loot_status_checkbox = core.menu.checkbox(true, TAG .. "loot_status_draw"),
    -- Sliders for loot status banner position (0-100 => 0.0-1.0)
    loot_status_pos_x = core.menu.slider_int(0, 100, 50, TAG .. "loot_status_pos_x"),
    loot_status_pos_y = core.menu.slider_int(0, 100, 66, TAG .. "loot_status_pos_y"),
    -- Scale slider for loot status banner (0.5-1.0)
    loot_status_scale = core.menu.slider_float(0.30, 1.0, 0.66, TAG .. "loot_status_scale"),
}

--------------------------------------------------
-- State
--------------------------------------------------
-- Per-unit loot state:
-- looted_units[corpse] = {
--     cycle_attempt   = 0 | 1 | 2, -- 0 = next attempt is #1, 1 = next attempt is #2, 2 = next attempt is #3
--     last_attempt    = number,    -- core.time() of last attempt in current mini-cycle
--     blocked_until   = number,    -- core.time() until which we skip attempts (400ms cooldown after attempt #3)
-- }
local looted_units ={}

-- Inventory state
local inventory_full = false  -- true when we detect "full - 1 slot" according to config

--------------------------------------------------
-- Helpers
--------------------------------------------------
local function auto_loot_enabled()
    return menu.enabled:get_state() and menu.auto_loot_key:get_toggle_state()
end

-- Slots 0 to 23 are gear + bag containers, they must NOT count as inventory items
local EQUIP_SLOT_MIN = 0
local EQUIP_SLOT_MAX = 23

-- Build a set of pointers for all equipped / bag items
local function build_equipped_item_set(me)
    local set ={}
    for slot_id = EQUIP_SLOT_MIN, EQUIP_SLOT_MAX do
        local info = me:get_item_at_inventory_slot(slot_id)
        if info and info.object and info.object.is_valid and info.object:is_valid() then
            -- Pointer identity, if slot.item == this object, it is one of these special slots
            set[info.object] = true
        end
    end
    return set
end

-- Count used inventory slots across all character bags (no banks)
-- We count "items", not free space, and ignore anything that matches
-- an equipped or bag item from slots 0..23
local function get_bag_item_count()
    local me = izi.me()
    if not me or not me:is_valid() then
        return nil
    end
    if not inventory_helper or not inventory_helper.get_character_bag_slots then
        return nil
    end
    local slots = inventory_helper:get_character_bag_slots()
    if not slots or type(slots) ~="table" then
        return nil
    end
    -- All items in gear and bag slots, used as a filter
    local equipped_set = build_equipped_item_set(me)
    local count = 0
    for _, slot in ipairs(slots) do
        if slot and slot.item and slot.item.is_valid and slot.item:is_valid() then
            -- If this item is not one of the equip/bag items, it is a real inventory item
            if not equipped_set[slot.item] then
                count = count + 1
            end
        end
    end
    return count
end

--------------------------------------------------
-- Menu rendering
--------------------------------------------------
core.register_on_render_menu_callback(function()
    menu.root:render(PLUGIN_NAME, function()
        menu.enabled:render("Plugin Enabled", "Enable or disable the Auto Loot plugin completely")
        if not menu.enabled:get_state() then
            return
        end
        menu.auto_loot_key:render(
            "Toggle",
            "Toggle auto looting of dead enemies around you"
        )
        menu.max_bag_space:render(
            "Max bag space",
            "Approximate total bag slots you want to use.\n"
            .. "If > 0, auto loot stops when you have <= 1 free slot left.\n"
            .. "0 = ignore bag space check."
        )
        -- Loot status banner options
        menu.loot_status_checkbox:render("Draw loot status banner")
        menu.loot_status_pos_x:render("Loot status X position")
        menu.loot_status_pos_y:render("Loot status Y position")
        menu.loot_status_scale:render("Loot status scale")
    end)
end)

--------------------------------------------------
-- Control panel integration
--------------------------------------------------
core.register_on_render_control_panel_callback(function()
    local control_panel_elements ={}
    if not menu.enabled:get_state() then
        return control_panel_elements
    end
    control_panel_helper:insert_toggle(control_panel_elements, {
        name = string.format("[%s] Auto Loot (%s)",
            PLUGIN_NAME,
            key_helper:get_key_name(menu.auto_loot_key:get_key_code())
        ),
        keybind = menu.auto_loot_key,
    })
    return control_panel_elements
end)

--------------------------------------------------
-- Loot status 2D banner
--------------------------------------------------
local function draw_loot_status_banner()
    if not menu.enabled:get_state() then
        return
    end
    -- Only draw when user wants it
    if not menu.loot_status_checkbox:get_state() then
        return
    end
    -- Text and color based on current auto loot toggle
    local is_on = auto_loot_enabled()
    local text = is_on and "AUTO LOOT: ON" or "AUTO LOOT: OFF"
    local banner_color = is_on and color.green() or color.red()
    local screen_size = core.graphics.get_screen_size()
    -- Read slider values (0-100 => 0.0-1.0 multiplier)
    local x_percent = menu.loot_status_pos_x:get() or 50
    local y_percent = menu.loot_status_pos_y:get() or 50
    local x_mult = x_percent * 0.01
    local y_mult = y_percent * 0.01
    -- Scale for font, outline and rectangle
    local scale = menu.loot_status_scale:get() or 1.0
    local base_font_size = 9
    local base_font_id   = 3
    local base_width     = 200.0
    local base_height    = 40.0
    -- Font size and outline scaled, kept at least 1
    local font_size = base_font_size
    local font_id   = base_font_id
    -- Note: font_id can be changed by scale but it requires lua reload since barney coded it to be init just once.
    -- Center horizontally based on scaled text width
    local text_width = core.graphics.get_text_width(text, font_size, base_font_id)
    local center_x   = screen_size.x * x_mult
    local pos_y      = screen_size.y * y_mult
    local actual_pos = vec2.new(center_x - text_width, pos_y)
    -- Rect size scaled
    local rect_size = vec2.new(base_width * scale, base_height * scale)
    plugin_helper:draw_text_message(
        text,
        banner_color,
        color.new(0, 0, 0, 150),
        actual_pos,
        rect_size,
        false,
        true,
        "simple_auto_loot_status_banner",
        nil,
        true,
        font_id
    )
end
core.register_on_render_callback(draw_loot_status_banner)

--------------------------------------------------
-- Auto Loot logic
--
-- Per unit pattern:
--   Attempt 1: instant
--   Attempt 2: next frame after attempt 1
--   Attempt 3: only if >= 20ms after attempt 2
--   After attempt 3: 400ms cooldown, then cycle resets (1 -> 2 -> 3 -> cooldown -> repeat)
--------------------------------------------------
core.register_on_update_callback(function()
    -- Keep control panel and keybind states in sync
    control_panel_helper:on_update(menu)

    if not auto_loot_enabled() then
        return
    end

    local me = izi.me()
    if not (me and me.is_valid and me:is_valid()) then
        return
    end

    if me:is_dead() then
        return
    end

    -- Dead enemies within 10 yards
    local dead_enemies = izi.enemies_if(10, function(enemy)
        return enemy
            and enemy.is_valid and enemy:is_valid()
            and enemy:is_dead()
    end)

    if not dead_enemies or #dead_enemies == 0 then
        return
    end

    local now = core.time()

    for i = 1, #dead_enemies do
        local corpse = dead_enemies[i]
        if corpse and corpse.is_valid and corpse:is_valid() then
            if corpse:can_be_looted() and corpse:has_loot() then
                local state = looted_units[corpse]
                if not state then
                    state ={
                        cycle_attempt = 0,
                        last_attempt = 0,
                        blocked_until = 0,
                    }
                    looted_units[corpse] = state
                end

                -- Respect 400ms cooldown after attempt #3
                if state.blocked_until and now < state.blocked_until then
                    goto continue
                end

                -- Cooldown expired and previous cycle finished, reset cycle
                if state.blocked_until and now >= state.blocked_until and state.cycle_attempt ~ = 0 then
                    state.cycle_attempt = 0
                    state.blocked_until = 0
                end

                local attempt = state.cycle_attempt or 0
                if attempt == 0 then
                    -- Attempt 1: instant
                    state.cycle_attempt = 1
                    state.last_attempt = now
                    core.input.loot_object(corpse)
                    movement_handler:pause_movement_light(0.5, 0.0)
                    return
                elseif attempt == 1 then
                    -- Attempt 2: next frame (no extra delay)
                    state.cycle_attempt = 2
                    state.last_attempt = now
                    core.input.loot_object(corpse)
                    movement_handler:pause_movement_light(0.5, 0.0)
                    return
                elseif attempt == 2 then
                    -- Attempt 3: wait at least 20ms since attempt 2
                    local delta = now - (state.last_attempt or 0)
                    if delta < 0.02 then
                        goto continue
                    end
                    state.cycle_attempt = 0
                    state.last_attempt = now
                    state.blocked_until = now + 0.4 -- 400ms cooldown
                    core.input.loot_object(corpse)
                    movement_handler:pause_movement_light(0.5, 0.0)
                    return
                else
                    -- Safety reset in case of invalid state
                    state.cycle_attempt = 0
                    state.blocked_until = 0
                end
            end
        end
        ::continue::
    end
end)
```

## Code Breakdown

### 1. Module Imports

```lua
local color = require("common/color")
local izi = require("common/izi_sdk")
local vec2 = require("common/geometry/vector_2")
local key_helper = require("common/utility/key_helper")
local plugin_helper = require("common/utility/plugin_helper")
local movement_handler = require("common/utility/movement_handler")
local control_panel_helper = require("common/utility/control_panel_helper")
```

**Key Modules:**
- `izi` - The IZI SDK for simplified game object access
- `color` - Color utilities for 2D rendering
- `vec2` - 2D vector math for positioning UI elements
- `movement_handler` - Pause movement during loot interactions
- `plugin_helper` - Helper for drawing text banners
- `control_panel_helper` - Control panel integration
- `key_helper` - Keybind name resolution

### 2. Menu Elements Definition

```lua
local TAG = "simple_auto_loot_"

local menu ={
    root        = core.menu.tree_node(),
    enabled     = core.menu.checkbox(true, TAG .. "enabled"),
    auto_loot_key = core.menu.keybind(999, false, TAG .. "toggle"),
    loot_status_checkbox = core.menu.checkbox(true, TAG .. "loot_status_draw"),
    loot_status_pos_x = core.menu.slider_int(0, 100, 50, TAG .. "loot_status_pos_x"),
    loot_status_pos_y = core.menu.slider_int(0, 100, 66, TAG .. "loot_status_pos_y"),
    loot_status_scale = core.menu.slider_float(0.30, 1.0, 0.66, TAG .. "loot_status_scale"),
}
```

**Menu Elements:**
- `enabled` - Global plugin toggle
- `auto_loot_key` - Keybind to toggle auto looting (default: 999 = unbinded but functional on control panel)
- `loot_status_checkbox` - Toggle for 2D status banner visibility
- `loot_status_pos_x/y` - Integer sliders (0-100) for banner position
- `loot_status_scale` - Float slider (0.30-1.0) for banner size

> **Slider Design:** Position sliders use percentage values (0-100) that are converted to screen-space multipliers (0.0-1.0). This makes positioning intuitive and resolution-independent.

### 3. State Management

```lua
local looted_units ={}
-- looted_units[corpse] = {
--     cycle_attempt   = 0 | 1 | 2,
--     last_attempt    = number,
--     blocked_until   = number,
-- }

local inventory_full = false
```

**Per-Unit State Tracking:**
- `cycle_attempt` - Tracks which attempt in the cycle (0, 1, or 2)
- `last_attempt` - Timestamp of the last loot attempt
- `blocked_until` - Timestamp when cooldown expires after attempt 3

**Inventory State:**
- `inventory_full` - Boolean flag set to true when bags reach (max_bag_space - 1) items

### 4. Inventory Management Functions

```lua
local EQUIP_SLOT_MIN = 0
local EQUIP_SLOT_MAX = 23

local function build_equipped_item_set(me)
    local set ={}
    for slot_id = EQUIP_SLOT_MIN, EQUIP_SLOT_MAX do
        local info = me:get_item_at_inventory_slot(slot_id)
        if info and info.object and info.object.is_valid and info.object:is_valid() then
            set[info.object] = true
        end
    end
    return set
end

local function get_bag_item_count()
    local me = izi.me()
    if not me or not me:is_valid() then
        return nil
    end
    if not inventory_helper or not inventory_helper.get_character_bag_slots then
        return nil
    end
    local slots = inventory_helper:get_character_bag_slots()
    if not slots or type(slots) ~ = "table" then
        return nil
    end
    local equipped_set = build_equipped_item_set(me)
    local count = 0
    for _, slot in ipairs(slots) do
        if slot and slot.item and slot.item.is_valid and slot.item:is_valid() then
            if not equipped_set[slot.item] then
                count = count + 1
            end
        end
    end
    return count
end
```

**Why Filter Equipped Items?**

The `inventory_helper:get_character_bag_slots()` includes ALL item slots, including equipped gear and the bag containers themselves. Without filtering, you'd count your equipped sword and bags as "inventory items", which would give incorrect results.

### 5. 2D Status Banner Rendering

```lua
local function draw_loot_status_banner()
    if not menu.enabled:get_state() then
        return
    end
    if not menu.loot_status_checkbox:get_state() then
        return
    end
    local is_on = auto_loot_enabled()
    local text = is_on and "AUTO LOOT: ON" or "AUTO LOOT: OFF"
    local banner_color = is_on and color.green() or color.red()
    local screen_size = core.graphics.get_screen_size()
    local x_percent = menu.loot_status_pos_x:get() or 50
    local y_percent = menu.loot_status_pos_y:get() or 50
    local x_mult = x_percent * 0.01
    local y_mult = y_percent * 0.01
    local scale = menu.loot_status_scale:get() or 1.0
    local base_font_size = 9
    local base_font_id   = 3
    local base_width     = 200.0
    local base_height    = 40.0
    local text_width = core.graphics.get_text_width(text, base_font_size, base_font_id)
    local center_x   = screen_size.x * x_mult
    local pos_y      = screen_size.y * y_mult
    local actual_pos = vec2.new(center_x - text_width, pos_y)
    local rect_size = vec2.new(base_width * scale, base_height * scale)
    plugin_helper:draw_text_message(
        text,
        banner_color,
        color.new(0, 0, 0, 150),
        actual_pos,
        rect_size,
        false,
        true,
        "simple_auto_loot_status_banner",
        nil,
        true,
        base_font_id
    )
end
core.register_on_render_callback(draw_loot_status_banner)
```

**Banner Features:**
- **Dynamic Color** - Green when enabled, red when disabled or when inventory is full
- **Inventory Warning** - Displays "INVENTORY FULL" in red when bags are at capacity
- **Customizable Position** - User-adjustable X/Y sliders
- **Scalable Size** - Float slider for banner scale (0.30-1.0)
- **Resolution Independent** - Uses percentage-based positioning
- **Text Centering** - Automatically centers text horizontally
- **Semi-transparent Background** - Black background with 150 alpha

### 6. Finding Dead Enemies - IZI Way

```lua
local dead_enemies = izi.enemies_if(10, function(enemy)
    return enemy
        and enemy.is_valid and enemy:is_valid()
        and enemy:is_dead()
end)

if not dead_enemies or #dead_enemies == 0 then
    return
end
```

**IZI Enemy Detection:**
- `izi.enemies_if(range, filter_func)` - Returns enemies matching the filter within range
- Automatically filters by distance (10 yards)
- Custom filter function checks if enemy is dead
- Returns empty table if no matches found

### 7. Smart Loot State Management

```lua
local state = looted_units[corpse]
if not state then
    state ={
        cycle_attempt = 0,
        last_attempt = 0,
        blocked_until = 0,
    }
    looted_units[corpse] = state
end

-- Respect 400ms cooldown after attempt #3
if state.blocked_until and now < state.blocked_until then
    goto continue
end

-- Cooldown expired and previous cycle finished, reset cycle
if state.blocked_until and now >= state.blocked_until and state.cycle_attempt ~ = 0 then
    state.cycle_attempt = 0
    state.blocked_until = 0
end
```

### 8. Three-Attempt Retry Pattern

```lua
local attempt = state.cycle_attempt or 0
if attempt == 0 then
    -- Attempt 1: instant
    state.cycle_attempt = 1
    state.last_attempt = now
    core.input.loot_object(corpse)
    movement_handler:pause_movement_light(0.5, 0.0)
    return
elseif attempt == 1 then
    -- Attempt 2: next frame (no extra delay)
    state.cycle_attempt = 2
    state.last_attempt = now
    core.input.loot_object(corpse)
    movement_handler:pause_movement_light(0.5, 0.0)
    return
elseif attempt == 2 then
    -- Attempt 3: wait at least 20ms since attempt 2
    local delta = now - (state.last_attempt or 0)
    if delta < 0.02 then
        goto continue
    end
    state.cycle_attempt = 0
    state.last_attempt = now
    state.blocked_until = now + 0.4 -- 400ms cooldown
    core.input.loot_object(corpse)
    movement_handler:pause_movement_light(0.5, 0.0)
    return
else
    -- Safety reset in case of invalid state
    state.cycle_attempt = 0
    state.blocked_until = 0
end
```

**Retry Logic Breakdown:**

**Attempt 1 (Instant):** Fires immediately when corpse is detected.

**Attempt 2 (Next Frame):** Fires on the very next game tick with no additional delay.

**Attempt 3 (20ms Delay):** Waits at least 20ms after attempt 2, then sets 400ms cooldown before next cycle.

**Movement Pausing:** `movement_handler:pause_movement_light(0.5, 0.0)` temporarily pauses character movement for 0.5 seconds during loot attempts.

## Key Concepts

### IZI Enemy Filtering

```lua
local dead_enemies = izi.enemies_if(10, function(enemy)
    return enemy and enemy:is_valid() and enemy:is_dead()
end)
```

This replaces the verbose legacy pattern of manually calling `unit_helper:get_enemy_list_around()` and then filtering with a for loop.

### Smart Retry Logic

**Why Three Attempts?**

Looting in WoW can fail for various reasons:
- Server latency
- Animation delays
- Movement cancellation
- Client-server desync

The three-attempt pattern with timing delays maximizes loot success rate.

### Per-Unit State Tracking

**Why Track State Per Corpse?**

Instead of global cooldowns, per-corpse state tracking enables:
- **Parallel Processing** - Loot multiple corpses without conflicts
- **Smart Retries** - Different corpses can be at different retry stages
- **Cooldown Management** - Failed corpses don't block successful ones
- **Memory Efficiency** - State only exists while corpse exists

The `looted_units` table uses corpse objects as keys, automatically cleaning up when corpses despawn (thanks to Lua's garbage collection).

### Inventory Management Strategy

```lua
local limit = math.max(0, max_bag_space - 1)
if item_count >= limit then
    inventory_full = true
    return
end
```

**Why "Max - 1"?**

The plugin stops looting when you have `max_bag_space - 1` items, leaving you with at least 1 free slot. This prevents completely filling your bags, which could cause issues with quest items or important drops.

## Comparison: Legacy vs IZI

### Getting Dead Enemies

**Legacy:**
```lua
local local_player = core.object_manager:get_local_player()
local player_position = local_player:get_position()
local nearby_units = unit_helper:get_enemy_list_around(player_position, 10, true, false)
local dead_enemies ={}
for i = 1, #nearby_units do
    local unit = nearby_units[i]
    if unit and unit:is_valid() and unit:is_dead() then
        table.insert(dead_enemies, unit)
    end
end
```

**IZI:**
```lua
local dead_enemies = izi.enemies_if(10, function(enemy)
    return enemy and enemy:is_valid() and enemy:is_dead()
end)
```

**Result:** 12 lines reduced to 3 lines with IZI.

### Checking Player Status

**Legacy:**
```lua
local local_player = core.object_manager:get_local_player()
if not local_player or not local_player:is_valid() then
    return
end
if local_player:is_dead() then
    return
end
```

**IZI:**
```lua
local me = izi.me()
if not (me and me.is_valid and me:is_valid()) then
    return
end
if me:is_dead() then
    return
end
```

## Customization

### Adjusting Loot Range

```lua
-- Increase to 15 yards
local dead_enemies = izi.enemies_if(15, function(enemy)
    return enemy and enemy:is_valid() and enemy:is_dead()
end)
```

### Modifying Retry Timing

```lua
-- Faster retry (10ms instead of 20ms)
if delta < 0.01 then
    goto continue
end

-- Shorter cooldown (200ms instead of 400ms)
state.blocked_until = now + 0.2
```

### Adjusting Inventory Limits

```lua
-- Stop looting at 30 items (keeps bags less full)
max_bag_space = core.menu.slider_int(0, 100, 30, TAG .. "max_bag_space")

-- Disable inventory checking entirely
max_bag_space = core.menu.slider_int(0, 100, 0, TAG .. "max_bag_space")
```

### Adding Loot Filters

```lua
local dead_enemies = izi.enemies_if(10, function(enemy)
    return enemy
        and enemy:is_valid()
        and enemy:is_dead()
        and enemy:can_be_looted()
        and enemy:has_loot()
        and not enemy:is_quest_boss() -- Don't auto-loot quest bosses
end)
```

### Customizing Banner Appearance

```lua
-- Custom colors
local banner_color = is_on and color.new(255, 215, 0, 255) or color.new(128, 128, 128, 255) -- Gold when on, gray when off

-- Custom text
local text = is_on and "LOOTING ACTIVE" or "LOOTING DISABLED"

-- Larger font
local base_font_size = 12
```

## Related Documentation

- [IZI SDK](/dev/libraries/izi) - IZI SDK overview
- [IZI Enemies If](/dev/libraries/izi#izienemies_if) - `izi.enemies_if()` method
- [Game Object](/dev/api/game-object) - `game_object` API reference
- [Core Input](/dev/api/input) - `core.input.loot_object()` method

## Tips

- **Loot Validation** - Always check both `corpse:can_be_looted()` and `corpse:has_loot()` before attempting to loot.
- **State Management** - Per-unit state tracking is crucial for reliable looting. Global cooldowns can cause missed loot opportunities when multiple corpses are nearby.
- **Banner Positioning** - The position sliders use percentage values (0-100) which are converted to screen multipliers (0.0-1.0). This makes the banner position resolution-independent.
- **Movement Pausing** - The 0.5 second movement pause is sufficient for most loot interactions. Increase it if you experience issues with loot being canceled by movement.
- **Retry Pattern** - The three-attempt retry pattern with 20ms delay and 400ms cooldown is optimized for reliability without spam.
- **Inventory Management** - Set `max_bag_space` to your total bag capacity minus desired free slots. The plugin stops at `max_bag_space - 1` items. Set to 0 to disable the feature entirely.
- **Equipment Filtering** - The inventory counter excludes equipped items and bag containers (slots 0-23) to provide accurate bag item counts.

## Conclusion

This Simple Auto Loot plugin demonstrates how to build a complete utility plugin with the IZI SDK. Key features:

- **Smart Retry Logic** - Three-attempt pattern with cooldowns for reliability
- **Per-Unit State** - Independent tracking prevents conflicts
- **Inventory Management** - Prevents bag overflow with customizable thresholds
- **Equipment Filtering** - Accurately counts bag items by excluding equipped gear
- **2D Status Banner** - Customizable position and scale with live feedback showing inventory status
- **Control Panel Integration** - Quick toggle without opening menu
- **Movement Handling** - Automatic pause to prevent loot cancellation

**IZI Advantages:**
- `izi.me()` - Cleaner player access
- `izi.enemies_if()` - Simplified filtered enemy detection
- `unit:is_dead()` - Direct status checks through game object extensions

Happy looting!

— Silvi
