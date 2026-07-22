---
title: "Fire Mage Rotation (IZI SDK)"
source: "https://docs.project-sylvanas.net/examples/izi/fire-mage"
crawled: "2026-07-14"
---

# Fire Mage Rotation Example (IZI SDK)

This example demonstrates how to create a complete combat rotation plugin for a Fire Mage using the **IZI SDK**. This is a comprehensive example that showcases the modern, simplified approach to building rotations with IZI's high-level abstractions.

> **Simplified Example:** This is an intentionally simplified code example ported from the legacy Fire Mage rotation. All logic shown here is for demonstration purposes only and only covers casting fireball for single target and flamestrike for AoE.

## What You'll Learn

- How to use the **IZI SDK** for simplified rotation development
- Creating `izi_spell` objects for streamlined spell management
- Using IZI's smart casting methods with prediction options
- Implementing AoE detection with splash range calculations
- Creating menu elements with checkboxes, keybinds, and tree nodes
- Control panel integration with keybinds
- Defensive checks (damage immunity, CC-weak states)
- Basic rotation priority (Flamestrike for AoE, Fireball for single target)

## IZI SDK vs Legacy API

The IZI SDK provides a higher-level abstraction over the core API, making rotation development faster and more intuitive:

> **Note:** In the table below, `unit` refers to a `game_object` instance (player, enemy, NPC, etc.).

| Feature | Legacy API | IZI SDK |
|---------|-----------|---------|
| Spell Casting | Manual queue + validation | `izi_spell:cast_safe()` |
| AoE Detection | `unit_helper:get_enemy_list_around(pos, range)` | `unit:get_enemies_in_splash_range(radius)` |
| Buff Checking | `buff_manager:get_buff_data(unit).is_active` | `unit:buff_up(buff_id)` |
| Target Selection | `target_selector:get_targets()` | `izi.get_ts_targets()` |
| Local Player | `core.object_manager:get_local_player()` | `izi.me()` |
| Spell Prediction | Manual `spell_prediction` setup | Built-in with `cast_safe()` |

**IZI SDK Benefits:** The IZI SDK reduces boilerplate code significantly. What takes 20-30 lines in legacy API often takes 5-10 lines with IZI, while providing the same functionality with sensible defaults.

## Plugin Structure

### header.lua

The header file validates the player's class and specialization before loading:

```lua
--Setup our plugin info
local plugin = {}
plugin.name = "IZI Fire Mage Example"
plugin.version = "0.0.1"
plugin.author = "Voltz"
plugin.load = true

--Ensure the local player is valid, if not we should not load the plugin
local local_player = core.object_manager:get_local_player()
if not local_player or not local_player:is_valid() then
    plugin.load = false
    return plugin
end

--Import enums for class and spec IDs
local enums = require("common/enums")

--Get the local player's class
local player_class = local_player:get_class()

--Are we a mage?
local is_valid_class = player_class == enums.class_id.MAGE

--If we are not a mage then dont load the plugin
if not is_valid_class then
    plugin.load = false
    return plugin
end

--Get spec ID enum
local spec_id = enums.class_spec_id

--Get the local player's spec ID
local player_spec_id = local_player:get_specialization_id()

--Are we a Fire Mage?
local is_valid_spec = player_spec_id == spec_id.get_spec_id_from_enum(spec_id.spec_enum.FIRE_MAGE)

-- If we are not Fire Mage then dont load the plugin
if not is_valid_spec then
    plugin.load = false
    return plugin
end

return plugin
```

> **Multi-Layer Validation:** This header demonstrates multi-layer validation:
> 1. Check if local player exists (prevents load screen errors)
> 2. Validate player class matches (only load for Mages)
> 3. Validate specialization matches (only load for Fire spec)
>
> This ensures the plugin only loads in the exact scenario it's designed for.

### main.lua

The main file contains the complete rotation logic using IZI SDK:

```lua
--[[
    Legacy Fire Mage rotation ported to IZI SDK

    This example demonstrates:
    - AoE detection and splash range calculations
    - Defensive checks (damage immunity, CC-weak states)
    - Menu element creation and rendering
    - Control panel integration with keybinds
    - Basic rotation logic (Flamestrike for AoE, Fireball for single target)

    Author: Voltz
]]--

--Import libraries
local izi = require("common/izi_sdk")
local enums = require("common/enums")
local key_helper = require("common/utility/key_helper")
local control_panel_helper = require("common/utility/control_panel_helper")

--Lets create our own variable for buffs as we will typically access buff enums frequently
local buffs = enums.buff_db

--Constants
local AOE_RADIUS = 8 --The distance to scan around the target for AoE check

--Create a table containing all of our spells
local SPELLS ={
    FIREBALL = izi.spell(133),    --Create our izi_spell object for fireball
    FLAMESTRIKE = izi.spell(2120) --Create our izi_spell object for flamestrike
}

--Settings prefix so we do not conflict with other plugins
local TAG = "izi_fire_mage_example_"

--Create our menu elements
local menu ={
    --The tree for our menu elements
    root            = core.menu.tree_node(),
    --The global plugin enabled toggle
    enabled         = core.menu.checkbox(false, TAG .. "enabled"),
    --Hotkey to toggle the rotation on and off
    -- 7 "Undefined"
    -- 999 "Unbinded" but functional on control panel (allows people to click it without key bound)
    toggle_key      = core.menu.keybind(999, false, TAG .. "toggle"),
    --Toggle to only cast flamestrike when we can instant cast it
    fs_only_instant = core.menu.checkbox(false, TAG .. "fs_only_instant"),
}

--Checks to see if the plugin AND rotation is enabled
---@return boolean enabled
local function rotation_enabled()
    --We use get_toggle_state instead of get_state for the hotkey
    --because otherwise it will only be true if the key is held
    return menu.enabled:get_state() and menu.toggle_key:get_toggle_state()
end

--Register Callbacks

--Our menu render callback
core.register_on_render_menu_callback(function()
    --Draw our menu tree and the children inside it
    menu.root:render("Fire Mage (IZI Demo)", function()
        --Draw our plugin enabled checkbox
        menu.enabled:render("Enabled Plugin")
        --No need to render the rest of our items if we have the plugin disabled entirely
        if not menu.enabled:get_state() then
            return
        end
        --Draw our toggle rotation hotkey
        menu.toggle_key:render("Toggle Rotation")
        --Draw our flamestrike only when instant checkbox
        menu.fs_only_instant:render("Cast flamestrike only when instant")
    end)
end)

--Our control panel render callback
core.register_on_render_control_panel_callback(function()
    --Create our control_panel_elements
    local control_panel_elements = {}
    --Check that the plugin is enabled
    if not menu.enabled:get_state() then
        --We return the empty table because there is no reason to draw anything
        --in the control panel if the plugin is not enabled
        return control_panel_elements
    end
    --Insert our rotation toggle into the control panel
    control_panel_helper:insert_toggle(control_panel_elements,
        {
            --Name is the name of the toggle in the control panel
            --We format it to display the current keybind
            name = string.format("[IZI Fire Mage] Enabled (%s)",
                key_helper:get_key_name(menu.toggle_key:get_key_code())
            ),
            --The menu element for the hotkey
            keybind = menu.toggle_key
        })
    return control_panel_elements --Return our elements to tell the control panel what to draw
end)

--Our main loop, this is executed every game tick
core.register_on_update_callback(function()
    --Fire control_panel_helper update to keep our control panel updated
    control_panel_helper:on_update(menu)

    --Rotation is not toggled no need to execute the rotation logic
    if not rotation_enabled() then
        return
    end

    --Get the local player
    local me = izi.me()

    --If the local player is nil (not in the world, etc), we will abort execution
    if not me then
        return
    end

    --Grab the targets from the target selector
    local targets = izi.get_ts_targets()

    --Loop through all targets and run our logic on each one
    --We do this because targets[1] will always be the best target
    --But in case we can't cast anything on the primary target it will fall back to the next target
    for i = 1, #targets do
        local target = targets[i]

        --Check if the target is valid otherwise skip it
        if not (target and target.is_valid and target:is_valid()) then
            goto continue
        end

        --If the target is immune to magical damage, skip it
        if target:is_damage_immune(target.DMG.MAGICAL) then
            goto continue
        end

        --If the target is in a CC that breaks from damage, skip it
        if target:is_cc_weak() then
            goto continue
        end

        --Get number of enemies that are within splash range (radius + bounding) of the target in AOE_RADIUS
        --If you need more advanced logic and need access the enemies
        --you can use get_enemies_in_splash_range_count instead
        local total_enemies_around_target = target:get_enemies_in_splash_range_count(AOE_RADIUS)

        --Check for AoE scenarios and do AoE rotation
        if total_enemies_around_target > 1 then
            --Check if flamestrike is instant by getting if the player has hot streak or hyperthermia buff
            local is_flamestrike_instant = me:buff_up(buffs.HOT_STREAK) or me:buff_up(buffs.HYPERTHERMIA)

            --Check if the user only wants to cast flamestrike when it is instant
            local should_cast_flamestrike = not menu.fs_only_instant:get_state() or is_flamestrike_instant

            if should_cast_flamestrike then
                --Cast flamestrike at the most hits location
                if SPELLS.FLAMESTRIKE:cast_safe(target, "AoE: Flamestrike",
                        {
                            --Spell prediction is used by default for ground spells
                            --I am manually setting options to show that you can tweak the default behavior
                            --IZI should have default prediction options for most AoE spells, however,
                            --to get the most of your class you should tweak these values to fit your usage
                            --Use spell prediction (Default: True)
                            use_prediction  = true,
                            --Spell prediction type
                            prediction_type = "MOST_HITS",
                            --Geometry type (shape of the ground spell)
                            geometry        = "CIRCLE",
                            --Radius of the circle
                            aoe_radius      = 8,
                            --Minimum number of hits required for the spell to be cast
                            --(You could make this more advanced and calculate a min % of total enemies)
                            min_hits        = 2,
                            --Cast time is instant if we have hot streak otherwise izi will look it up
                            cast_time       = is_flamestrike_instant and 0 or nil,
                            --Cast while moving if we have hot streak up
                            skip_moving     = is_flamestrike_instant,
                            --Ensure we have LoS
                            --(changing to false as at the time of writing this it was not working)
                            check_los       = false,
                        })
                then
                    --We have queued / casted a spell we should now return
                    --to rerun the logic to get the next priority spell
                    return
                end
            end
            --...Add more AoE logic
            --(above and below flamestrike depending on order / priority of your class rotation)
        end

        --Single target logic

        --Cast fireball
        if SPELLS.FIREBALL:cast_safe(target, "Single Target: Fireball") then
            --We have queued / casted a spell we should now return
            --to rerun the logic to get the next priority spell
            return
        end

        --...Add more single target logic
        --(above and below fireball depending on order / priority of your class rotation)

        --Define our continue label for continuing to the next target
        ::continue::
    end
end)
```

## Code Breakdown

### 1. Module Imports

```lua
local izi = require("common/izi_sdk")
local enums = require("common/enums")
local key_helper = require("common/utility/key_helper")
local control_panel_helper = require("common/utility/control_panel_helper")
```

**Key Modules:**
- `izi` - The IZI SDK providing high-level abstractions
- `enums` - Constants for classes, specs, buffs, and more
- `key_helper` - Keybind name resolution for control panel display
- `control_panel_helper` - Control panel drag & drop interface

### 2. Constants and Spell Definitions

```lua
local buffs = enums.buff_db
local AOE_RADIUS = 8

local SPELLS ={
    FIREBALL = izi.spell(133),
    FLAMESTRIKE = izi.spell(2120)
}
```

**IZI Spell Objects:**
- `izi.spell(spell_id)` creates an `izi_spell` object
- These objects have smart methods like `cast_safe()` that handle validation, queueing, and prediction
- Store spells in a table for organized access

### 3. Menu Elements Definition

```lua
local TAG = "izi_fire_mage_example_"

local menu ={
    root            = core.menu.tree_node(),
    enabled         = core.menu.checkbox(false, TAG .. "enabled"),
    toggle_key      = core.menu.keybind(999, false, TAG .. "toggle"),
    fs_only_instant = core.menu.checkbox(false, TAG .. "fs_only_instant"),
}
```

**Best Practices:**
- Use a unique `TAG` prefix to avoid conflicts with other plugins
- Default the keybind to 999 when you want users to be able to click your toggle without a key bound
- Default the keybind to 7 when you do not want to display the toggle without a key bound
- Keep menu structure simple and organized

### 4. Rotation Enabled Check

```lua
local function rotation_enabled()
    return menu.enabled:get_state() and menu.toggle_key:get_toggle_state()
end
```

**Key Difference:**
- Use `get_toggle_state()` for keybinds (toggle mode)
- Use `get_state()` for keybinds (keybind down state)
- Use `get_state()` for checkboxes (on/off state)

### 5. Menu Rendering

```lua
core.register_on_render_menu_callback(function()
    menu.root:render("Fire Mage (IZI Demo)", function()
        menu.enabled:render("Enabled Plugin")
        if not menu.enabled:get_state() then
            return
        end
        menu.toggle_key:render("Toggle Rotation")
        menu.fs_only_instant:render("Cast flamestrike only when instant")
    end)
end)
```

**Menu Structure:**
- Root tree node contains all elements in our menu tree
- Early return if disabled (hides options when plugin is off)
- Clear, descriptive labels for each element

### 6. Control Panel Integration

```lua
core.register_on_render_control_panel_callback(function()
    local control_panel_elements = {}
    if not menu.enabled:get_state() then
        return control_panel_elements
    end
    control_panel_helper:insert_toggle(control_panel_elements,
        {
            name = string.format("[IZI Fire Mage] Enabled (%s)",
                key_helper:get_key_name(menu.toggle_key:get_key_code())),
            keybind = menu.toggle_key
        })
    return control_panel_elements
end)
```

**Control Panel:**
- Returns empty table if plugin is disabled
- Displays toggle with keybind name in the control panel
- Allows users to quickly enable/disable without opening full menu

### 7. Main Update Loop - IZI Way

```lua
core.register_on_update_callback(function()
    control_panel_helper:on_update(menu)
    if not rotation_enabled() then
        return
    end
    local me = izi.me()
    if not me then
        return
    end
    local targets = izi.get_ts_targets()
    for i = 1, #targets do
        local target = targets[i]
        if not (target and target.is_valid and target:is_valid()) then
            goto continue
        end
        if target:is_damage_immune(target.DMG.MAGICAL) then
            goto continue
        end
        if target:is_cc_weak() then
            goto continue
        end
        -- Rotation logic...
        ::continue::
    end
end)
```

**IZI Simplifications:**
- `izi.me()` - Get local player (simpler than `core.object_manager:get_local_player()`)
- `izi.get_ts_targets()` - Get target selector targets (replaces `target_selector:get_targets()`)
- `target:is_damage_immune()` - Checks if the unit is immune to damage (replaces `pvp_helper`)
- `target:is_cc_weak()` - Check if target is in breakable CC

### 8. AoE Detection - IZI Way

```lua
local total_enemies_around_target = target:get_enemies_in_splash_range_count(AOE_RADIUS)
if total_enemies_around_target > 1 then
    -- AoE rotation
end
```

**IZI AoE Methods:**
- `target:get_enemies_in_splash_range_count(radius)` - Returns count of enemies
- Automatically accounts for target bounding radius (hitbox size)
- Much simpler than manual `unit_helper:get_enemy_list_around(pos, range)`

### 9. Buff Checking - IZI Way

```lua
local is_flamestrike_instant = me:buff_up(buffs.HOT_STREAK) or me:buff_up(buffs.HYPERTHERMIA)
```

**IZI Buff Methods:**
- `me:buff_up(buff_id)` - Simple boolean check if buff is active
- Replaces verbose `buff_manager:get_buff_data().is_active` pattern
- Also available: `unit:buff_down()`, `unit:debuff_up()`, `unit:debuff_down()`

### 10. Smart Spell Casting - IZI Way

#### Flamestrike with Prediction

```lua
if SPELLS.FLAMESTRIKE:cast_safe(target, "AoE: Flamestrike",
        {
            use_prediction  = true,
            prediction_type = "MOST_HITS",
            geometry        = "CIRCLE",
            aoe_radius      = 8,
            min_hits        = 2,
            cast_time       = is_flamestrike_instant and 0 or nil,
            skip_moving     = is_flamestrike_instant,
            check_los       = false,
        })
then
    return
end
```

**Position Cast Options:**
- `use_prediction` - Enable spell prediction for ground spells (default: true)
- `prediction_type` - `"MOST_HITS"` finds position hitting most enemies
- `geometry` - `"CIRCLE"` for circular AoE (also supports `"RECTANGLE"`)
- `aoe_radius` - Radius of the AoE spell
- `min_hits` - Minimum enemies required to cast
- `cast_time` - Override cast time (0 for instant, nil for auto-detect)
- `skip_moving` - Allow casting while moving
- `check_los` - Verify line of sight

IZI's `cast_safe()` method automatically handles spell prediction for ground-targeted spells. You just pass options and it does all the heavy lifting: calculating positions, validating targets, checking cooldowns, and queueing the spell.

#### Fireball (Simple Cast)

```lua
if SPELLS.FIREBALL:cast_safe(target, "Single Target: Fireball") then
    return
end
```

**For simple targeted spells:**
- Just call `cast_safe(target)`
- IZI handles all validation, range checking, cooldown checking, and queueing
- Returns `true` if spell was queued successfully

### 11. Complete Rotation Logic

```lua
for i = 1, #targets do
    local target = targets[i]
    if not (target and target.is_valid and target:is_valid()) then
        goto continue
    end
    if target:is_damage_immune(target.DMG.MAGICAL) then
        goto continue
    end
    if target:is_cc_weak() then
        goto continue
    end

    local total_enemies_around_target = target:get_enemies_in_splash_range_count(AOE_RADIUS)
    if total_enemies_around_target > 1 then
        local is_flamestrike_instant = me:buff_up(buffs.HOT_STREAK) or me:buff_up(buffs.HYPERTHERMIA)
        local should_cast_flamestrike = not menu.fs_only_instant:get_state() or is_flamestrike_instant
        if should_cast_flamestrike then
            if SPELLS.FLAMESTRIKE:cast_safe(target, "AoE: Flamestrike",
                    {
                        use_prediction  = true,
                        prediction_type = "MOST_HITS",
                        geometry        = "CIRCLE",
                        aoe_radius      = 8,
                        min_hits        = 2,
                        cast_time       = is_flamestrike_instant and 0 or nil,
                        skip_moving     = is_flamestrike_instant,
                        check_los       = false,
                    })
            then
                return
            end
        end
    end

    if SPELLS.FIREBALL:cast_safe(target, "Single Target: Fireball") then
        return
    end
    ::continue::
end
```

**Rotation Priority:**
1. **Validate Target** - Check if valid and accessible
2. **Check Immunity** - Skip immune targets
3. **Check CC** - Skip targets in breakable crowd control
4. **AoE Detection** - Count enemies in splash range
5. **AoE Rotation** - Cast Flamestrike if 2+ enemies
6. **Single Target** - Cast Fireball as filler
7. **Early Return** - Exit after successful cast to re-evaluate priority

## Key Concepts

### IZI Spell Objects

IZI spell objects take the headache out of spell casting by handling complex logic automatically. When you call `cast_safe()`, it:

- **Validates castability** - Checks cooldowns, range, facing, line of sight, and resource costs
- **Handles ground spells** - Automatically configures spell prediction for optimal AoE placement
- **Prevents double casting** - Built-in throttling ensures spells aren't queued multiple times
- **Manages spell queue** - Automatically queues spells with proper priority and timing
- **Customizable** - Allows you to customize every part of the castable check and spell prediction

Instead of writing 15-20 lines of validation, queue management, and prediction setup with the legacy API, you call one method with optional configuration.

### IZI Game Object Extensions

**Simplified Combat Logic:**

IZI provides countless powerful `game_object` extensions that dramatically speed up your development. These extensions replace verbose legacy API calls with intuitive, single-method solutions that handle edge cases automatically.

Instead of calling multiple helper modules (`buff_manager`, `unit_helper`, `pvp_helper`) and manually parsing their results, IZI extends `game_object` directly with methods like `buff_up()`, `is_damage_immune()`, and `get_enemies_in_splash_range_count()`. These methods:

- **Simplify buff checking** - `unit:buff_up(buff_id)` returns a simple boolean instead of requiring `buff_manager:get_buff_data().is_active`
- **Handle combat states** - Check damage immunity, CC status, combat state, and threat with single method calls
- **Calculate AoE scenarios** - Automatically account for bounding radius and splash range for accurate multi-target detection
- **Improve readability** - Code reads naturally: `if me:buff_up(hot_streak) then` vs verbose helper module chains

## Comparison: Legacy vs IZI

### Getting the Local Player

**Legacy:**
```lua
local local_player = core.object_manager:get_local_player()
```

**IZI:**
```lua
local me = izi.me()
```

### Checking Buffs

**Legacy:**
```lua
local hot_streak_data = buff_manager:get_buff_data(local_player, buffs.HOT_STREAK)
if hot_streak_data.is_active then
    -- has buff
end
```

**IZI:**
```lua
if me:buff_up(buffs.HOT_STREAK) then
    -- has buff
end
```

### Casting Spells

**Legacy:**
```lua
local last_fireball_cast_time = 0.0

---@param local_player game_object
---@param target game_object
---@return boolean
local function cast_fireball(local_player, target)
    local time = core.time()
    if time - last_fireball_cast_time < 0.20 then
        return false
    end
    local is_spell_ready_to_be_casted = spell_helper:is_spell_castable(fireball_spell_data.id, local_player, target,
        false, false)
    if not is_spell_ready_to_be_casted then
        return false
    end
    if local_player:is_moving() then
        return false
    end
    spell_queue:queue_spell_target(fireball_spell_data.id, target, 1, "Casting Fireball")
    last_fireball_cast_time = time
    return true --spell queued
end
```

**IZI:**
```lua
if SPELLS.FIREBALL:cast_safe(target, "Casting Fireball") then
    return true --Spell queued
end
```

### Spell Prediction

**Legacy:**
```lua
local last_flamestrike_cast_time = 0.0

---@param local_player game_object
---@param target game_object
---@return boolean
local function cast_flamestrike(local_player, target)
    local time = core.time()
    if time - last_flamestrike_cast_time < 0.20 then
        return false
    end
    local is_instant = is_flamestrike_instant(local_player)
    local is_only_casting_if_instant = menu_elements.cast_flamestrike_only_when_instant:get_state()
    if is_only_casting_if_instant then
        if not is_instant then
            return false
        end
    end
    if not is_flamestrike_instant then
        if local_player:is_moving() then
            return false
        end
    end
    local is_spell_ready_to_be_casted = spell_helper:is_spell_castable(flamestrike_spell_data.id, local_player, target,
        false, false)
    if not is_spell_ready_to_be_casted then
        return false
    end
    local flamestrike_radius = 8.0
    local flamestrike_radius_safe = flamestrike_radius * 0.90
    local flamestrike_range = 40
    local flamestrike_range_safe = flamestrike_range * 0.95
    local flamestrike_cast_time = 2.5
    local flamestrike_cast_time_safe = flamestrike_cast_time + 0.1
    local player_position = local_player:get_position()
    local prediction_spell_data = spell_prediction:new_spell_data(
        flamestrike_spell_data.id,
        flamestrike_range_safe,
        flamestrike_radius_safe,
        flamestrike_cast_time_safe,
        0.0,
        spell_prediction.prediction_type.MOST_HITS,
        spell_prediction.geometry_type.CIRCLE,
        player_position
    )
    local prediction_result = spell_prediction:get_cast_position(target, prediction_spell_data)
    if prediction_result.amount_of_hits <= 0 then
        return false
    end
    local cast_position = prediction_result.cast_position
    local cast_distance = cast_position:squared_dist_to(player_position)
    if cast_distance >= flamestrike_range then
        return false
    end
    spell_queue:queue_spell_position(flamestrike_spell_data.id, cast_position, 1,
        "Casting Flamestrike To " .. target:get_name())
    last_flamestrike_cast_time = time
    return true -- spell queued
end
```

**IZI:**
```lua
if SPELLS.FLAMESTRIKE:cast_safe(target, "Casting Flamestrike") then
    return true --Spell queued with default builtin prediction data
end
```

## Customization

### Adding More Spells

Create new spell objects:

```lua
local SPELLS ={
    FIREBALL = izi.spell(133),
    FLAMESTRIKE = izi.spell(2120),
    SCORCH = izi.spell(2948),      -- Add Scorch
    PYROBLAST = izi.spell(11366),  -- Add Pyroblast
}
```

Add to rotation:

```lua
-- Cast Pyroblast with Hot Streak
if me:buff_up(buffs.HOT_STREAK) then
    if SPELLS.PYROBLAST:cast_safe(target, "Hot Streak: Pyroblast", { skip_moving = true }) then
        return
    end
end

-- Cast Scorch while moving
if me:is_moving() then
    if SPELLS.SCORCH:cast_safe(target, "Moving: Scorch", { skip_moving = true }) then
        return
    end
end
```

### Adjusting AoE Threshold

Change the AoE detection logic:

```lua
local AOE_RADIUS = 10  -- Increase radius

-- Require more enemies for AoE
if total_enemies_around_target >= 3 then
    -- Cast AoE spells
end
```

### Adding Defensive Spells

```lua
-- Before offensive rotation
--Can also use me:get_health_percentage_inc(deadline_time_in_seconds) to get future health
--Just as a warning this is not 100% accurate and you should not rely solely on get_health_percentage_inc
if me:health_percentage() < 30  then
    if SPELLS.ICE_BLOCK:cast_safe(me, "Emergency: Ice Block") then
        return
    end
end
```

## Related Documentation

- [IZI SDK](/dev/libraries/izi) - IZI SDK overview
- [IZI Spell](/dev/libraries/izi/izi-spells) - `izi_spell` object and methods
- [IZI Game Object Extensions](/dev/libraries/izi/izi-object-extensions) - `game_object` extensions

## Tips

- **Start with IZI** - If you're new to rotation development, start with the IZI SDK. It handles most of the complexity for you while still allowing fine-tuned control when needed. You can always combine it with the legacy API for specific edge cases.
- **IZI Defaults** - IZI's `cast_safe()` method has sensible defaults for most ground spells. For maximum ground spell performance you should consider tweaking the `pos_cast_opts` parameter to optimize spell casting.
- **CC Awareness** - Use `target:is_cc_weak()` to avoid breaking crowd control effects. This IZI method checks for Polymorph, Sap, Incapacitate, and other breakable CC effects.
- **Damage Immunity** - Always check `target:is_damage_immune(dmg_type)` before casting to prevent wasting spells on a target that cannot take damage.
- **Return After Cast** - Always `return` after a successful cast, this allows the rotation to re-evaluate priorities on the next game tick with updated game state.

## Conclusion

The IZI SDK dramatically simplifies rotation development while maintaining full flexibility. What took 300+ lines in the legacy example takes about 150 lines with IZI, with clearer code that's easier to maintain and extend.

**Key IZI Advantages:**
- **Less headache** - `cast_safe()` handles validation, queueing, and prediction so you don't have to
- **Less boilerplate** - IZI provides you with a large collection of helper methods to simplify your code and work with game objects easier through the game object extensions

The IZI SDK is the recommended approach for new rotation and plugin development going forward. Feel free to adapt and expand upon this code for your own projects.

— Voltz
