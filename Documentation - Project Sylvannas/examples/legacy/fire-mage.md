---
title: "Fire Mage Rotation (Legacy)"
source: "https://docs.project-sylvanas.net/examples/legacy/fire-mage"
crawled: "2026-07-14"
---

# Fire Mage Rotation Example

This example demonstrates how to create a complete combat rotation plugin for a Fire Mage using the Project Sylvanas API. This is a comprehensive example that covers menu creation, spell casting, target selection, buff tracking, spell prediction, and defensive/offensive logic flow.

> **Simplified Example:** This is an intentionally simplified code example. All logic shown here is for demonstration purposes only and may not cover all scenarios. Use these examples as a starting point and adapt as needed for real implementations.

## What You'll Learn

- How to validate player class and specialization before loading
- Creating interactive menu elements with checkboxes, keybinds, and tree nodes
- Importing and using core helper libraries and modules
- Implementing spell casting logic with cooldown checks
- Tracking and checking player buffs
- Using spell prediction for AoE placement
- Implementing target selection and filtering
- Creating defensive and offensive rotation flows
- Handling crowd control and immunity checks
- Drawing plugin state feedback
- Creating control panel integrations

## Plugin Structure

### header.lua

```lua
local plugin = {}
plugin["name"] = "Placeholder Script"
plugin["version"] = "0.10"
plugin["author"] = "Author Name"
plugin["load"] = true

local local_player = core.object_manager.get_local_player()
if not local_player then
    plugin["load"] = false
    return plugin
end

local enums = require("common/enums")
local player_class = local_player:get_class()
local is_valid_class = player_class == enums.class_id.MAGE

if not is_valid_class then
    plugin["load"] = false
    return plugin
end

local player_spec_id = core.spell_book.get_specialization_id()
local fire_mage = enums.class_spec_id.get_spec_id_from_enum(enums.class_spec_id.spec_enum.FIRE_MAGE)

if player_spec_id ~ = fire_mage then
    plugin["load"] = false
    return plugin
end

return plugin
```

### main.lua

```lua
-- Note: This is an intentionally simplified code example.

local enums = require("common/enums")
local pvp_utility = require("common/utility/pvp_helper")
local spell_queue = require("common/modules/spell_queue")
local unit_helper = require("common/utility/unit_helper")
local spell_helper = require("common/utility/spell_helper")
local buff_manager = require("common/modules/buff_manager")
local plugin_helper = require("common/utility/plugin_helper")
local spell_prediction = require("common/modules/spell_prediction")
local control_panel_helper = require("common/utility/control_panel_helper")

-- Menu elements
local menu_elements ={
    main_tree = core.menu.tree_node(),
    keybinds_tree_node = core.menu.tree_node(),
    enable_script_check = core.menu.checkbox(false, "enable_script_check"),
    cast_flamestrike_only_when_instant = core.menu.checkbox(false, "cast_flamestrike_only_when_instant"),
    enable_toggle = core.menu.keybind(999, false, "toggle_script_check"),
    draw_plugin_state = core.menu.checkbox(true, "draw_plugin_state"),
    ts_custom_logic_override = core.menu.checkbox(true, "override_ts_logic"),
}

-- Menu rendering
local function my_menu_render()
    menu_elements.main_tree:render("Fire Mage Example", function()
        menu_elements.enable_script_check:render("Enable Script")
        if not menu_elements.enable_script_check:get_state() then
            return false
        end
        menu_elements.keybinds_tree_node:render("Keybinds", function()
            menu_elements.enable_toggle:render("Enable Script Toggle")
        end)
        menu_elements.ts_custom_logic_override:render("Enable TS Custom Settings Override")
        menu_elements.cast_flamestrike_only_when_instant:render("Only Allow Flamestrike Cast When Empowered")
        menu_elements.draw_plugin_state:render("Draw Plugin State")
    end)
end

-- Spell data
local fireball_spell_data ={ id = 133, name = "Fireball" }
local flamestrike_spell_data ={ id = 2120, name = "Flamestrike" }

-- Fireball casting
local last_fireball_cast_time = 0.0

---@param local_player game_object
---@param target game_object
---@return boolean
local function cast_fireball(local_player, target)
    local time = core.time()
    if time - last_fireball_cast_time < 0.20 then
        return false
    end
    local is_spell_ready_to_be_casted = spell_helper:is_spell_castable(fireball_spell_data.id, local_player, target, false, false)
    if not is_spell_ready_to_be_casted then
        return false
    end
    if local_player:is_moving() then
        return false
    end
    spell_queue:queue_spell_target(fireball_spell_data.id, target, 1, "Casting Fireball To " .. target:get_name())
    last_fireball_cast_time = time
    return true
end

-- Buff checking for instant Flamestrike
---@param local_player game_object
---@return boolean
local function is_flamestrike_instant(local_player)
    local hot_streak_data = buff_manager:get_buff_data(local_player, enums.buff_db.HOT_STREAK)
    if hot_streak_data.is_active then
        return true
    end
    local hyperthermia_data = buff_manager:get_buff_data(local_player, enums.buff_db.HYPERTHERMIA)
    if hyperthermia_data.is_active then
        return true
    end
    return false
end

-- Flamestrike with spell prediction
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
    local is_spell_ready_to_be_casted = spell_helper:is_spell_castable(flamestrike_spell_data.id, local_player, target, false, false)
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

    spell_queue:queue_spell_position(flamestrike_spell_data.id, cast_position, 1, "Casting Flamestrike To " .. target:get_name())
    last_flamestrike_cast_time = time
    return true
end

-- AoE detection
---@param target game_object
---@return boolean
local function is_aoe(target)
    local units_around_target = unit_helper:get_enemy_list_around(target:get_position(), 15.0)
    return #units_around_target > 1
end

-- Complete cast logic
local function complete_cast_logic(local_player, target)
    if is_aoe(target) then
        if cast_flamestrike(local_player, target) then
            return true
        end
    end
    return cast_fireball(local_player, target)
end

-- Target selector override
local target_selector = require("common/modules/target_selector")
local is_ts_overriden = false

local function override_ts_settings()
    if is_ts_overriden then return end
    local is_override_allowed = menu_elements.ts_custom_logic_override:get_state()
    if not is_override_allowed then return end
    target_selector.menu_elements.settings.max_range_damage:set(40)
    target_selector.menu_elements.damage.weight_multiple_hits:set(true)
    target_selector.menu_elements.damage.slider_weight_multiple_hits:set(4)
    target_selector.menu_elements.damage.slider_weight_multiple_hits_radius:set(8)
    is_ts_overriden = true
end

-- Main update loop
local function my_on_update()
    control_panel_helper:on_update(menu_elements)
    local local_player = core.object_manager.get_local_player()
    if not local_player then return end
    if not menu_elements.enable_script_check:get_state() then return end
    if not plugin_helper:is_toggle_enabled(menu_elements.enable_toggle) then return end

    local cast_end_time = local_player:get_active_spell_cast_end_time()
    if cast_end_time > 0.0 then return false end
    local channel_end_time = local_player:get_active_channel_cast_end_time()
    if channel_end_time > 0.0 then return false end
    if local_player:is_mounted() then return end

    override_ts_settings()
    local targets_list = target_selector:get_targets()
    local is_defensive_allowed = plugin_helper:is_defensive_allowed()

    -- Defensive logic
    for index, target in ipairs(targets_list) do
        if is_defensive_allowed then
            -- Add defensive spells here
        end
    end

    -- Healing targets
    local heal_targets_list = target_selector:get_targets_heal()
    for index, heal_target in ipairs(heal_targets_list) do
        if pvp_utility:is_crowd_controlled(heal_target, pvp_utility.cc_flags.combine("CYCLONE"), 100) then
            goto continue
        end
        ::continue::
    end

    -- Offensive rotation
    for index, target in ipairs(targets_list) do
        local is_target_in_combat = unit_helper:is_in_combat(target)
        if not is_target_in_combat then goto continue end
        if pvp_utility:is_damage_immune(target, pvp_utility.damage_type_flags.MAGICAL) then goto continue end
        if pvp_utility:is_crowd_controlled(target, pvp_utility.cc_flags.combine("DISORIENT", "INCAPACITATE", "SAP"), 1000) then goto continue end
        if complete_cast_logic(local_player, target) then return true end
        ::continue::
    end
end

-- Render callback
local function my_on_render()
    local local_player = core.object_manager.get_local_player()
    if not local_player then return end
    if not menu_elements.enable_script_check:get_state() then return end
    if not plugin_helper:is_toggle_enabled(menu_elements.enable_toggle) then
        if menu_elements.draw_plugin_state:get_state() then
            plugin_helper:draw_text_character_center("DISABLED")
        end
    end
end

-- Control panel
local key_helper = require("common/utility/key_helper")
local function on_control_panel_render()
    local control_panel_elements = {}
    if not menu_elements.enable_script_check:get_state() then
        return control_panel_elements
    end
    control_panel_helper:insert_toggle(control_panel_elements,{
        name = "[" .. "MageTest" .. "] Enable (" .. key_helper:get_key_name(menu_elements.enable_toggle:get_key_code()) .. ") ",
        keybind = menu_elements.enable_toggle,
    })
    return control_panel_elements
end

-- Register callbacks
core.register_on_update_callback(my_on_update)
core.register_on_render_callback(my_on_render)
core.register_on_render_menu_callback(my_menu_render)
core.register_on_render_control_panel_callback(on_control_panel_render)
```

## Code Breakdown

### 1. Module Imports

```lua
local enums = require("common/enums")
local pvp_utility = require("common/utility/pvp_helper")
local spell_queue = require("common/modules/spell_queue")
local unit_helper = require("common/utility/unit_helper")
local spell_helper = require("common/utility/spell_helper")
local buff_manager = require("common/modules/buff_manager")
local plugin_helper = require("common/utility/plugin_helper")
local spell_prediction = require("common/modules/spell_prediction")
local control_panel_helper = require("common/utility/control_panel_helper")
```

**Key Modules:**
- `enums` - Constants for classes, specs, buffs, and more
- `pvp_utility` - PvP-specific helpers (CC checks, immunity checks)
- `spell_queue` - Queues spells for casting
- `unit_helper` - Unit-related utilities (combat checks, enemy lists)
- `spell_helper` - Spell casting validation
- `buff_manager` - Buff and debuff tracking
- `plugin_helper` - Plugin state management and helpers
- `spell_prediction` - AoE spell positioning predictions
- `control_panel_helper` - Control panel drag & drop interface

### 2. Spell Casting Flow

1. **Throttle Check** - Prevent rapid re-casting (200ms cooldown)
2. **Spell Validation** - Use `spell_helper:is_spell_castable()` to verify the spell can be cast
3. **Movement Check** - Don't cast while moving (Fireball requires standing still)
4. **Queue Spell** - Use `spell_queue:queue_spell_target()` to execute the cast
5. **Update Timestamp** - Track last cast time
6. **Return Success** - Return `true` to signal successful cast

### 3. Spell Prediction Flow

1. **Instant Cast Check** - Check if player has Hot Streak or Hyperthermia
2. **Menu Option Check** - Respect user preference for instant-only casts
3. **Movement Check** - Only prevent cast if not instant
4. **Define Spell Parameters** - Set radius, range, cast time with safety margins (90-95%)
5. **Create Prediction Data** - Use `spell_prediction:new_spell_data()` with `MOST_HITS` and `CIRCLE`
6. **Get Cast Position** - `spell_prediction:get_cast_position()` calculates optimal placement
7. **Validate Result** - Check if prediction found valid targets
8. **Range Check** - Ensure position is in range
9. **Queue Position Spell** - Use `spell_queue:queue_spell_position()` for ground-targeted spell

### 4. Target Filtering

```lua
-- Skip out-of-combat
if not unit_helper:is_in_combat(target) then goto continue end

-- Skip immune targets
if pvp_utility:is_damage_immune(target, pvp_utility.damage_type_flags.MAGICAL) then goto continue end

-- Skip CC'd targets (avoid breaking)
if pvp_utility:is_crowd_controlled(target, pvp_utility.cc_flags.combine("DISORIENT", "INCAPACITATE", "SAP"), 1000) then goto continue end
```

### 5. Main Update Loop Flow

1. **Control Panel Update** - Handle drag & drop state
2. **Validation Checks** - Local player exists, script enabled, toggle keybind enabled, not currently casting, not currently channeling, not mounted
3. **Target Selector Override** - Apply custom settings once
4. **Defensive Phase** - Cast defensive spells before offense
5. **Healing Phase** - Support friendly targets
6. **Offensive Phase** - Main rotation with filtering

## Key Concepts

### Spell Casting Best Practices

1. **Throttle Rapid Calls** - Use timestamps to prevent function spam
2. **Validate Before Casting** - Use `spell_helper:is_spell_castable()`
3. **Check Movement** - Hard-cast spells require standing still
4. **Queue Spells** - Use `spell_queue` for proper execution
5. **Return Early** - Exit rotation after successful cast

### Performance Optimizations

1. **Early Returns** - Exit functions as soon as conditions aren't met
2. **Ordered Checks** - Check cheap conditions before expensive ones
3. **Buff Caching** - `buff_manager` caches buff data
4. **Target Selection** - Let `target_selector` handle complex filtering

## Related Documentation

- [Target Selector](/dev/libraries/modules/target-selector)
- [Buff Manager](/dev/api/buffs#2---buff-manager-module-)
- [Spell Helper](/dev/api/spellbook/helper)
- [Unit Helper](/dev/libraries/mini-libs/unit-helper)
- [PvP Helper](/dev/libraries/mini-libs/pvp-helper)
- [Spell Prediction](/dev/libraries/modules/spell-prediction)

## Tips

- **Defensive Priority** - Always run defensive logic before offensive logic
- **Crowd Control** - Use `pvp_utility:is_crowd_controlled()` to avoid breaking important CC effects
- **Spell Prediction** - For AoE spells, use `spell_prediction` to calculate optimal placement
- **Menu Organization** - Organize your menu logically with tree nodes for related options
- **Immunity Checks** - Always check for damage immunity before casting

## Conclusion

This legacy Fire Mage rotation example demonstrates the foundational concepts needed to build complete combat rotations using the Project Sylvanas core API. While this approach requires more manual implementation compared to modern solutions like the IZI SDK, it provides full control and deep understanding of the underlying systems.

**Key Takeaways:**
- Manual Control - Direct access to core systems gives you maximum flexibility
- Module Integration - Learn how to combine multiple helper modules
- Target Selection - Implement custom target selector configurations optimized for your rotation
- Spell Prediction - Manually configure AoE spell positioning for optimal damage
- Defensive Logic - Separate defensive and offensive phases for proper priority handling

**Consider IZI SDK Instead:** If you're building a new rotation from scratch, consider the IZI SDK Fire Mage Example which provides the same functionality with significantly less code.

— Barney
