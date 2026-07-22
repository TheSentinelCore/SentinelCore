---
title: "Control Panel"
source: "https://docs.project-sylvanas.net/dev/api/ui/control-panel"
crawled: "2026-07-14"
---

# Control Panel

## Overview

The `control_panel` module is essentially a separate unique graphical window that allows the user to track and easily modify the state of specific menu elements whose values are of special importance or are designed to be modified constantly, so the user doesn't have to open the main menu every time. This is usually how the Control Panel might look like for an average user:

![Control Panel Example](../../images/1727786559336-control_panel_pala.png)  

## How it Works - Basic Explanation

To add elements to the Control Panel, we need to use a specific callback. The core is expecting a table containing some information on the menu elements that are going to be shown in the Control Panel window to return from that callback. When this information is correct, the menu elements can be displayed in the Control Panel window, allowing them to be modified by clicking on them.

note

Drag & Drop is also supported, although this approach requires a special handling that will be covered later.

### How to Make it Work - Step by Step (With an Example)

1- Include the Necessary Plugins

```
---@type key_helperlocal key_helper = require("common/utility/key_helper")---@type control_panel_helperlocal control_panel_utility = require("common/utility/control_panel_helper")
```

2- Define your menu elements:  

```
    local combat_mode_enum =    {        AUTO    = 1,        AOE     = 2,        SINGLE  = 3,    }    local combat_mode_options =    {        "Auto",        "AoE",        "Single"    }    local test_tree_node = core.menu.tree_node()    local menu =    {        -- note that we are initializing the keybinds with the value "7". This value corresponds to "Unbinded".        -- We do this so the user has to manually set the key they want. Otherwise, this menu element won't appear        -- in the Control Panel, and will be treated as if its value were true.        enable_toggle = core.menu.keybind(7, false, "enable_toggle"),        switch_combat_mode = core.menu.keybind(7, false, "switch_combat_mode"),        soft_cooldown_toggle = core.menu.keybind(7, false, "soft_cooldown_toggle"),        heavy_cooldown_toggle = core.menu.keybind(7, false, "heavy_cooldown_toggle"),        combat_mode = core.menu.combobox(combat_mode_enum.AUTO, "combat_mode_auto_aoe_single"),    }
```

3- Define the Function to Render your Menu Elements:  

```
local function on_render_menu_elements()    test_tree_node:render("Testing Control Panel Elements", function()        menu.enable_toggle:render("Enable Toggle")        menu.switch_combat_mode:render("Switch Combat Mode")        menu.soft_cooldown_toggle:render("Soft Cooldowns Toggle")        menu.combat_mode:render("Combat Mode", combat_mode_options)    end)end
```

4- Define the Callback Function  

```
local function on_control_panel_render()    -- this is how we build the toggle table that we return from the callback, as previously discussed:    local enable_toggle_key = menu.enable_toggle:get_key_code()    -- toggle table -> must have:    -- member 1: .name    -- member 2: .keybind (the menu element itself)    local enable_toggle =    {        name = "[My Plugin] Enable (" .. key_helper:get_key_name(enable_toggle_key) .. ") ",        keybind = menu.enable_toggle    }    local soft_toggle_key = menu.soft_cooldown_toggle:get_key_code()    local soft_cooldowns_toggle =    {        name = "[My Plugin] Soft Cooldowns (" .. key_helper:get_key_name(soft_toggle_key) .. ") ",        keybind = menu.soft_cooldown_toggle    }    -- combo table -> must have:    -- member 1: .name    -- member 2: .combobox (the menu element itself)    -- member 3: .preview_value (the current value that the combobox has, in string format)    -- member 4: .max_items (the amount of items that the combobox has)    local combat_mode_key = menu.switch_combat_mode:get_key_code()    local combat_mode = {        name = "[My Plugin] Combat Mode (" .. key_helper:get_key_name(combat_mode_key) .. ") ",        combobox = menu.combat_mode,        preview_value = combat_mode_options[menu.combat_mode:get()],        max_items = combat_mode_options    }    local hard_toggle_key = menu.heavy_cooldown_toggle:get_key_code()    local hard_cooldowns_toggle =    {        name = "[My Plugin] Hard Cooldowns (" .. key_helper:get_key_name(hard_toggle_key) .. ") ",        keybind = menu.heavy_cooldown_toggle    }    -- finally, we define the table that we are going to return from the callback    local control_panel_elements = {}    -- we use the Control Panel utility to insert this menu element in the table that we are going to return. This function has    -- code that internally handles stuff related to Drag & Drop, so if you want to enable this functionality you must insert the    -- menu elements by using this table. Otherwise, you could just return the elements without using the ccontrol_panel_helper plugin,    -- but this way is recommended anyways for scalability reasons.    control_panel_utility:insert_toggle_(control_panel_elements, enable_toggle.name, enable_toggle.keybind, false)    control_panel_utility:insert_toggle_(control_panel_elements, soft_cooldowns_toggle.name, soft_cooldowns_toggle.keybind, false)    control_panel_utility:insert_toggle_(control_panel_elements, hard_cooldowns_toggle.name, hard_cooldowns_toggle.keybind, false)    control_panel_utility:insert_combo_(control_panel_elements, combat_mode.name, combat_mode.combobox,    combat_mode.preview_value, combat_mode.max_items, main_menu.switch_combat_mode, false)    return control_panel_elementsend
```

5- Use the Callbacks  

```
-- finally, we just need to implement the callbacks. If we want drag and drop, we must also call on_update.core.register_on_update_callback(function()    control_panel_utility:on_update(menu)end)core.register_on_render_control_panel_callback(on_control_panel_render)core.register_on_render_menu_callback(on_render_menu_elements)
```

5- Summary  

So far, this is all the code that we created:

```
---@type key_helperlocal key_helper = require("common/utility/key_helper")---@type control_panel_helperlocal control_panel_utility = require("common/utility/control_panel_helper")local combat_mode_enum ={    AUTO    = 1,    AOE     = 2,    SINGLE  = 3,}local combat_mode_options ={    "Auto",    "AoE",    "Single"}local test_tree_node = core.menu.tree_node()local menu ={    -- note that we are initializing the keybinds with the value "7". This value corresponds to "Unbinded".    -- We do this so the user has to manually set the key they want. Otherwise, this menu element won't appear    -- in the Control Panel, and will be treated as if its value were true.    enable_toggle = core.menu.keybind(7, false, "enable_toggle"),    switch_combat_mode = core.menu.keybind(7, false, "switch_combat_mode"),    soft_cooldown_toggle = core.menu.keybind(7, false, "soft_cooldown_toggle"),    heavy_cooldown_toggle = core.menu.keybind(7, false, "heavy_cooldown_toggle"),    combat_mode = core.menu.combobox(combat_mode_enum.AUTO, "combat_mode_auto_aoe_single"),}local function on_render_menu_elements()    test_tree_node:render("Testing Control Panel Elements", function()        menu.enable_toggle:render("Enable Toggle")        menu.switch_combat_mode:render("Switch Combat Mode")        menu.soft_cooldown_toggle:render("Soft Cooldowns Toggle")        menu.heavy_cooldown_toggle:render("Heavy Cooldowns Toggle")        menu.combat_mode:render("Combat Mode", combat_mode_options)    end)endlocal function on_control_panel_render()    -- this is how we build the toggle table that we return from the callback, as previously discussed:    local enable_toggle_key = menu.enable_toggle:get_key_code()    -- toggle table -> must have:    -- member 1: .name    -- member 2: .keybind (the menu element itself)    local enable_toggle =    {        name = "[My Plugin] Enable (" .. key_helper:get_key_name(enable_toggle_key) .. ") ",        keybind = menu.enable_toggle    }    local soft_toggle_key = menu.soft_cooldown_toggle:get_key_code()    local soft_cooldowns_toggle =    {        name = "[My Plugin] Soft Cooldowns (" .. key_helper:get_key_name(soft_toggle_key) .. ") ",        keybind = menu.soft_cooldown_toggle    }    -- combo table -> must have:    -- member 1: .name    -- member 2: .combobox (the menu element itself)    -- member 3: .preview_value (the current value that the combobox has, in string format)    -- member 4: .max_items (the amount of items that the combobox has)    local combat_mode_key = menu.switch_combat_mode:get_key_code()    local combat_mode = {        name = "[My Plugin] Combat Mode (" .. key_helper:get_key_name(combat_mode_key) .. ") ",        combobox = menu.combat_mode,        preview_value = combat_mode_options[menu.combat_mode:get()],        max_items = combat_mode_options    }    local hard_toggle_key = menu.heavy_cooldown_toggle:get_key_code()    local hard_cooldowns_toggle =    {        name = "[My Plugin] Hard Cooldowns (" .. key_helper:get_key_name(hard_toggle_key) .. ") ",        keybind = menu.heavy_cooldown_toggle    }    -- finally, we define the table that we are going to return from the callback    local control_panel_elements = {}    -- we use the Control Panel utility to insert this menu element in the table that we are going to return. This function has    -- code that internally handles stuff related to Drag & Drop, so if you want to enable this functionality you must insert the    -- menu elements by using this table. Otherwise, you could just return the elements without using the ccontrol_panel_helper plugin,    -- but this way is recommended anyways for scalability reasons.    control_panel_utility:insert_toggle_(control_panel_elements, enable_toggle.name, enable_toggle.keybind, false)    control_panel_utility:insert_toggle_(control_panel_elements, soft_cooldowns_toggle.name, soft_cooldowns_toggle.keybind, false)    control_panel_utility:insert_toggle_(control_panel_elements, hard_cooldowns_toggle.name, hard_cooldowns_toggle.keybind, false)    control_panel_utility:insert_combo_(control_panel_elements, combat_mode.name, combat_mode.combobox,    combat_mode.preview_value, combat_mode.max_items, menu.switch_combat_mode, false)    return control_panel_elementsend-- finally, we just need to implement the callbacks. If we want drag and drop, we must also call on_update.core.register_on_update_callback(function()    control_panel_utility:on_update(menu)end)core.register_on_render_control_panel_callback(on_control_panel_render)core.register_on_render_menu_callback(on_render_menu_elements)
```

If you run that code, you will see the following result:

### Control Panel Behaviour Explanation

As you can see in the previous video, the user can remove and add elements from the Control Panel manually. There are 2 ways to do this:  
  
1- The menu element was dragged and dropped: In this case, the user can remove the element from the Control Panel by double-clicking with the right-mouse button on its hitbox.  
  
2- The menu element keybind was set: The user can also make the menu elements appear just by changing the keybind to another key different than the "Unbinded" one. In the same way, a user can remove an element from the Control Panel by setting its key value to "Unbinded" again (right clicking sets the value to default, which in the code example is "Unbinded" or "7").

note

To drag a menu element that has Drag & Drop enabled, you have to press SHIFT and then click. When the Drag & Drop is ready, you will see a box with the menu element name appear. Then, you can drag the said box to the Control Panel. When the Control Panel is higlighted in green, you can drop the box there. After that, you will see that the menu element is now successfully binded to the Control Panel.

warning

If a menu element was dragged and dropped in the Control Panel, setting its value to "Unbinded" won't remove it from the Control Panel. Instead, RMB double-click is mandatory.  
  
Likewise, if a menu element was introduced to the Control Panel by setting its value to one different than "Unbinded", RMB double-click won't remove it from the Control Panel.

## Tables Expected By The Callback

`1 - Toggle table` This table is reserved for toggle keybinds.  
  
**Its members must be the following:**  
  
1\. name: The label that will appear in the Control Panel (string)  
2\. keybind: The keybind itself ([menu_element](/dev/api/ui/))

`2 - Combobox table` This table is reserved for comboboxes.  
  
**Its members must be the following:**  
  
1\. name: The label that will appear in the Control Panel (string)  
2\. combobox: The combobox itself ([menu_element](/dev/api/ui/))  
3\. preview\_value\`: The current value that the combobox currently has, in string format. (string)  
4\. max\_items: The items that the combobox has (integer)  

## Registering the Callback

The procedure is the same as with all other callbacks:

warning

Keep in mind that this callback expects a table as a return value. This is the only callback that expects a return value.

```
core.register_on_render_control_panel_callback(function()    local menu_elements_table = {}    -- your control panel code here    return menu_elementsend)
```

Or:

```
local function on_render_control_panel()    local menu_elements_table = {}    -- your control panel code here    return menu_elementsendcore.register_on_render_control_panel_callback(on_render_control_panel)
```

note

To use the following functions, you will need to include the Control Panel Helper module. To do this, you can just copy these lines:

```
---@type control_panel_helperlocal control_panel_utility = require("common/utility/control_panel_helper")
```

## Functions - Control Panel Helper

### `on_update(menu)`

Updates the Control Panel elements by setting drag-and-drop flags based on the current Control Panel label.

Parameters:

-   **`menu`** (*table*) — The menu containing Control Panel elements to be updated.

Returns: *nil*

warning

You must call this function inside the on_update callback for Drag & Drop functionality to work for your menu elements. Ideally, call this function the first thing on your on_update function.  
If this function is not called, Drag & Drop will not work.

---

### `insert_toggle(control_panel_table, toggle_table, only_drag_drop)`

Inserts a toggle into the Control Panel table if it is not already inserted and meets the specified criteria.

Parameters:

-   **`control_panel_table`** (*table*) — The Control Panel table where the toggle will be inserted.
-   **`toggle_table`** (*table*) — The table containing the toggle element details.
-   **`only_drag_drop`** (*boolean*, optional) — Flag to indicate if the insertion should only occur during drag-and-drop.

Returns: *boolean* — `true` if the toggle was inserted successfully; otherwise, `false`.

---

### `insert_toggle_(control_panel_table, display_name, keybind_element, only_drag_drop)`

Inserts a toggle into the Control Panel table if it is not already inserted and meets the specified criteria.

Parameters:

-   **`control_panel_table`** (*table*) — The Control Panel table where the toggle will be inserted.
-   **`display_name`** (*string*) — The name to be displayed for the toggle element.
-   **`keybind_element`** (*userdata*) — The keybind menu element.
-   **`only_drag_drop`** (*boolean*, optional) — Flag to indicate if the insertion should only occur during drag-and-drop.

Returns: *boolean* — `true` if the toggle was inserted successfully; otherwise, `false`.

---

### `insert_combo(control_panel_table, combo_table, increase_index_key, only_drag_drop)`

Inserts a combobox into the Control Panel table if it is not already inserted and meets the specified criteria.

Parameters:

-   **`control_panel_table`** (*table*) — The Control Panel table where the combo will be inserted.
-   **`combo_table`** (*table*) — The table containing the combo element details.
-   **`increase_index_key`** (*userdata*, optional) — The keybind to increase the index, if applicable.
-   **`only_drag_drop`** (*boolean*, optional) — Flag to indicate if the insertion should only occur during drag-and-drop.

Returns: *boolean* — `true` if the combo was inserted successfully; otherwise, `false`.

---

### `insert_combo_(control_panel_table, display_name, combobox_element, preview_value, max_items, increase_index_key, only_drag_drop)`

Inserts a combobox into the Control Panel table if it is not already inserted and meets the specified criteria.

Parameters:

-   **`control_panel_table`** (*table*) — The Control Panel table where the combo will be inserted.
-   **`display_name`** (*string*) — The name to be displayed for the combo element.
-   **`combobox_element`** (*userdata*) — The combobox menu element.
-   **`preview_value`** (*any*) — The preview value to be shown for the combobox.
-   **`max_items`** (*number*) — The maximum number of items in the combobox.
-   **`increase_index_key`** (*userdata*, optional) — The keybind to increase the index, if applicable.
-   **`only_drag_drop`** (*boolean*, optional) — Flag to indicate if the insertion should only occur during drag-and-drop.

Returns: *boolean* — `true` if the combo was inserted successfully; otherwise, `false`.
