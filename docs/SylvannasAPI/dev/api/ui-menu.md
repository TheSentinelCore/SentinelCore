---
title: "Menu"
source: "https://docs.project-sylvanas.net/dev/api/ui/"
crawled: "2026-07-14"
---

# Menu

### Overview

This module is one of the most important ones, since it is the one that will allow you to add customization options to your plugins. You could always design your own menu for your scripts using our Custom UI, in a way that makes your plugins very unique and different from the rest. However, **this would add a level of complexity that might not be necessary** in most cases. So, for most devs, we offer the option to add your own menu to the main menu directly. (You can still use the menu elements in your custom menu, if desired, as stated in the Custom UI guide).

## Menu Elements Basics

There are a two things that you have to keep in mind when working with menu elements. The first one is that you can only render them in 2 specific callbacks. The other information that you should know is menu elements are, and therefore, must be treated as, objects. This implies that you must not declare the menu elements inside the render callback, since you would be generating a new different menu element with each iteration. This will cause issues, specially if done with tree nodes.

> **tip**: There is one exception to the previous rule, and that is, headers. You can render a header (a plain text in the menu) as follows:

```lua
core.menu.header():render("Header Test", color.green(200))
```

And it would be valid, since headers are a very light-weight object and don't need of an unique ID, unlike the other menu elements.

An example of an invalid code:

```lua
-- The state of the checkbox is not saved into the variable "bad_code_example", since core.menu.checkbox doesn't return a boolean, but rather the checkbox object.
-- A new checkbox is being generated every frame, generating performance issues.
core.register_on_render_menu_callback(function()
    local bad_code_example = core.menu.checkbox(true, "testing_1"):render("AA")
end)
```

An example of code following best practices:

```lua
-- first, we generate a table containing all the menu elements that we are going to use OUTSIDE the callback
---@type color
local color = require("common/color")

local menu_elements ={
    my_test_node = core.menu.tree_node(),
    my_checkbox_1 = core.menu.checkbox(true, "my_checkbox_test"),
    my_test_keybind = core.menu.keybind(7, false, "my_test_keybind")
}

core.register_on_render_menu_callback(function()
    menu_elements.my_test_node:render("Hi From Lua - Testing Menu Elements!", function()
        menu_elements.my_checkbox_1:render("Testing The Checkbox!", "This is a tooltip!")
        core.menu.header():render("Testing The Headers!", color.green(200))
        menu_elements.my_test_keybind:render("Testing The Keybind!")
    end)
end)
```

This is the result of the previous code:

![](../../images/1727206014677-menu_test1.png)

---

### Register Menu Callback

> **warning**: Menu elements can only be rendered inside the register_on_render_menu_callback OR register_on_render_window_callback callbacks. The first one is reserved for menu elements that will be rendered within the main menu, and the second one for menu elements that will be rendered within one of your custom-made windows. See Custom UI Guide

`core.menu.register_on_render_menu_callback(callback: function)`

- This function registers the menu for interaction. Same like with other callbacks, you can also pass an anonymous function. This is how you would call the callback:

```lua
core.menu.register_on_render_menu_callback(function()
     -- your pre-defined menu elements render function code here
end)
```

Or:

```lua
local function my_render_menu_function()
    -- your pre-defined menu elements render function code here
end

core.menu.register_on_render_menu_callback(my_render_menu_function)
```

---

## Available Menu Elements

## Tree Node

### Constructor

### `tree_node()`

Creates a new tree node instance.

Returns: *tree_node* — A new `tree_node` object.

---

### `render(header, callback)`

Renders the tree node with content.

Parameters:
- **`header`** (*string*) — The header text of the tree node.
- **`callback`** (*function*) — The content to render inside the node.

#### Example

```lua
-- Anonymous function approach
main_node:render("Debug Plugin", function()
    -- content inside the node
end)

-- Alternative
local function debug_plugin_node()
    -- content inside the node
    -- note: declare outside menu callback
end

-- Inside menu callback
main_node:render("Debug Plugin", debug_plugin_node)
```

---

### `is_open()`

Checks if the tree node is open.

Returns: *boolean* — `true` if the tree node is open; otherwise, `false`.

---

## Checkbox

### Constructor

### `checkbox(default_state, id)`

Creates a new checkbox instance.

Parameters:
- **`default_state`** (*boolean*) — The default state of the checkbox.
- **`id`** (*string*) — The unique identifier for the checkbox.

Returns: *checkbox* — A new `checkbox` object.

---

### `render(label, tooltip(optional))`

Renders the checkbox with the specified label and optional tooltip.

Parameters:
- **`label`** (*string*) — The label text of the checkbox.
- **`tooltip`** (*string*, optional) — The tooltip text for the checkbox.

> **tip**: Checkbox `render` supports `\n` to write multiple lines.

---

### `get_state()`

Retrieves the current state of the checkbox.

Returns: *boolean* — `true` if checked; otherwise, `false`.

---

### `set(new_state)`

Sets a new state for the checkbox.

Parameters:
- **`new_state`** (*boolean*) — The new state to set.

Returns: *nil*

---

## Slider Int

### Constructor

### `slider_int(min_value, max_value, default_value, id)`

Creates a new slider with integer values.

Parameters:
- **`min_value`** (*number*) — The minimum value of the slider.
- **`max_value`** (*number*) — The maximum value of the slider.
- **`default_value`** (*number*) — The default value of the slider.
- **`id`** (*string*) — The unique identifier for the slider.

Returns: *slider_int* — A new `slider_int` object.

---

### `render(label, tooltip(optional))`

Renders the slider with the specified label and optional tooltip.

Parameters:
- **`label`** (*string*) — The label text of the slider.
- **`tooltip`** (*string*, optional) — The tooltip text for the slider.

> **tip**: Slider `render` supports `\n` to write multiple lines.

---

### `get()`

Retrieves the current value of the slider.

Returns: *number* — The current value.

---

### `set(new_value)`

Sets a new value for the slider.

Parameters:
- **`new_value`** (*number*) — The new value to set.

Returns: *nil*

---

## Slider Float

### Constructor

### `slider_float(min_value, max_value, default_value, id)`

Creates a new slider with floating-point values.

Parameters:
- **`min_value`** (*number*) — The minimum value of the slider.
- **`max_value`** (*number*) — The maximum value of the slider.
- **`default_value`** (*number*) — The default value of the slider.
- **`id`** (*string*) — The unique identifier for the slider.

Returns: *slider_float* — A new `slider_float` object.

---

### `render(label, tooltip (optional))`

Renders the slider with the specified label and optional tooltip.

Parameters:
- **`label`** (*string*) — The label text of the slider.
- **`tooltip`** (*string*, optional) — The tooltip text for the slider.

> **tip**: Slider `render` supports `\n` to write multiple lines.

---

### `get()`

Retrieves the current value of the slider.

Returns: *number* — The current value.

---

### `set(new_value)`

Sets a new value for the slider.

Parameters:
- **`new_value`** (*number*) — The new value to set.

Returns: *nil*

---

## Combobox

### Constructor

### `combobox(default_index, id)`

Creates a new combobox.

Parameters:
- **`default_index`** (*number*) — The default index of the combobox options (1-based).
- **`id`** (*string*) — The unique identifier for the combobox.

Returns: *combobox* — A new `combobox` object.

---

### `render(label, options, tooltip (optional))`

Renders the combobox with the specified label, options, and optional tooltip.

Parameters:
- **`label`** (*string*) — The label text of the combobox.
- **`options`** (*table*) — A table of strings containing the options for the combobox.
- **`tooltip`** (*string*, optional) — The tooltip text for the combobox.

> **tip**: Combobox `render` supports `\n` to write multiple lines.

---

### `get()`

Retrieves the index of the currently selected option (1-based).

Returns: *number* — The index of the selected option.

---

### `set(new_value)`

Sets a new selected index for the combobox.

Parameters:
- **`new_value`** (*number*) — The new index to select.

Returns: *nil*

> **tip**: You could use a combo box to let the user decide script behaviours in a more graphical way. Below, an example using 3 possible modes:

```lua
local combat_mode_enum ={
    AUTO    = 1,
    AOE     = 2,
    SINGLE  = 3,
}

local combat_mode_options ={
    "Auto",
    "AoE",
    "Single"
}

local main_tree = core.menu.tree_node()
local combat_mode = core.menu.combobox(combat_mode_enum.AUTO, "combat_mode_auto_aoe_single")

core.register_on_render_menu_callback(function()
    main_tree:render("Combo - Test", function()
        combat_mode:render("Testing Combo Boxes - Combat Modes", combat_mode_options)
    end)
end)

core.register_on_update_callback(function()
    local current_combat_mode = combat_mode:get()
    local current_combat_mode_str = combat_mode_options[current_combat_mode]
    local is_current_combat_mode_auto = current_combat_mode == combat_mode_enum.AUTO
    local is_current_combat_mode_aoe = current_combat_mode == combat_mode_enum.AOE
    local is_current_combat_mode_single = current_combat_mode == combat_mode_enum.SINGLE

    core.log("Current Combat Mode Is: " .. current_combat_mode_str)
    core.log("Is Current Combat Mode Auto: " .. tostring(is_current_combat_mode_auto))
    core.log("Is Current Combat Mode AOE: " .. tostring(is_current_combat_mode_aoe))
    core.log("Is Current Combat Mode Single: " .. tostring(is_current_combat_mode_single))
end)
```

This should be the result of running that code:

![](../../images/1727699662195-combobox_test.png)

---

## Keybind

### Constructor

### `keybind(default_value, initial_toggle_state, id)`

Creates a new keybind.

Parameters:
- **`default_value`** (*number*) — The default key code for the keybind.
- **`initial_toggle_state`** (*boolean*) — The initial toggle state.
- **`id`** (*string*) — The unique identifier for the keybind.

Returns: *keybind* — A new `keybind` object.

---

### `render(label, tooltip (optional), add_separator(optional))`

Renders the keybind with the specified label and optional tooltip.

Parameters:
- **`label`** (*string*) — The label text of the keybind.
- **`tooltip`** (*string*, optional) — The tooltip text for the keybind.
- **`add_separator`** (*boolean*, optional) — A flag to add a separator below the keybind. True by default.

---

### `get_state()`

Retrieves the state of the keybind.

Returns: *boolean* — The state of the keybind.

---

### `get_toggle_state()`

Retrieves the toggle state of the keybind.

Returns: *boolean* — The toggle state.

---

### `get_key_code()`

Retrieves the key code assigned to the keybind.

Returns: *integer* — The key code.

---

### `set_toggle_state(new_state)`

Sets a new toggle state for the keybind.

Parameters:
- **`new_state`** (*boolean*) — The new toggle state.

Returns: *nil*

---

### `set_key_code(new_key_code)`

Sets a new key code for the keybind.

Parameters:
- **`new_key_code`** (*integer*) — The new key code.

Returns: *nil*

---

## Button

### Constructor

### `button()`

Creates a new button.

Returns: *button* — A new `button` object.

---

### `render(label, tooltip (optional))`

Renders the button with the specified label and optional tooltip.

Parameters:
- **`label`** (*string*) — The label text of the button.
- **`tooltip`** (*string*, optional) — The tooltip text for the button.

Returns: *boolean* — `true` if the button was clicked; otherwise, `false`.

---

## Color Picker

### Constructor

### `color_picker(default_color, id)`

Creates a new color picker.

Parameters:
- **`default_color`** (*number*) — The default color value.
- **`id`** (*string*) — The unique identifier for the color picker.

Returns: *color_picker* — A new `color_picker` object.

---

### `render(label, tooltip (optional))`

Renders the color picker with the specified label and optional tooltip.

Parameters:
- **`label`** (*string*) — The label text of the color picker.
- **`tooltip`** (*string*, optional) — The tooltip text for the color picker.

---

### `get()`

Retrieves the selected color value.

Returns: *number* — The selected color value.

---

## Key Checkbox

> **note**: This is a special menu element that allows the user full customization over a keybind. Using this menu element might be overkill in most cases, but there are circumstances where you would want to add full costumization to a certain keybind, so all kinds of users are happy with the customization options. This is what it would look like:

![](../../images/1730289461618-key_checkbox.png)

Explanation of the menu element:
1 -> First, we have a checkbox. If this checkbox is disabled, the logic should be disabled completely.
2 -> Secondly, we have a keyboard icon. Upon pressing this icon, a new popup will appear.
3 -> > This popup contains 3 elements:
    3.1 -> Mode: This is the behaviour that the keybind has.
        3.1.1 -> Available modes:
            3.1.1.1 -- (0) Hold
            3.1.1.2 -- (1) Toggle
            3.1.1.3 -- (2) Always
        3.1.2 -> Modes explanation:
            3.1.2.1 -- Hold means that the keybind state will only return true when the user is pressing it. False otherwise.
            3.1.2.2 -- Toggle means that the keybind wil behave as a toggle.
            3.1.2.3 -- Always means that the keybind will always return true (acts as a checkbox, essentially)

### Constructor

### `key_checkbox(default_key, initial_toggle_state, default_state, show_in_binds, default_mode_state, id)`

```lua
--- Creates a new checkbox instance.
---@param default_key integer The default state of the checkbox.
---@param initial_toggle_state boolean The initial toggle state of the keybind
---@param default_state boolean The default state of the checkbox
---@param show_in_binds boolean The default show in binds state of the checkbox
---@param default_mode_state integer The default show in binds state of the checkbox  -> 0 is hold, 1 is toggle, 2 is always
---@param id string The unique identifier for the checkbox.
---@return key_checkbox
```

---

### `render(label, tooltip (optional))`

Renders the key checkbox with the specified label and optional tooltip.

Parameters:
- **`label`** (*string*) — The label text of the button.
- **`tooltip`** (*string*, optional) — The tooltip text for the button.

Returns: *boolean* — `true` if the button was clicked; otherwise, `false`.

---

## Code Examples

```lua
-- Define a unique developer ID to prevent ID collisions with other plugins
local dev_id = "unique_developer_id_here"

-- Create a table to store all menu elements
local menu_elements = {}

-- Create the main node for the menu
menu_elements.main_node = core.menu.tree_node()

-- Create checkboxes with unique IDs
menu_elements.checkbox_one = core.menu.checkbox(true, dev_id .. "checkbox_example_one")
menu_elements.checkbox_two = core.menu.checkbox(false, dev_id .. "checkbox_example_two")

-- Create slider int and float with unique IDs
menu_elements.slider_int = core.menu.slider_int(0, 100, 50, dev_id .. "slider_int")
menu_elements.slider_float = core.menu.slider_float(0, 100, 50, dev_id .. "slider_float")

-- Create the sub menu node inside the main node
menu_elements.sub_menu_node = core.menu.tree_node()

-- Create combobox, keybind, button, and color picker with unique IDs
menu_elements.combobox = core.menu.combobox(1, dev_id .. "combobox")
menu_elements.keybind = core.menu.keybind(46, false, dev_id .. "keybind")
menu_elements.button = core.menu.button()
menu_elements.colorpicker = core.menu.color_picker(-65536, dev_id .. "colorpicker")

-- Register the menu rendering callback
core.menu.register_on_render_menu_callback(function()
    -- Render the main node
    menu_elements.main_node:render("Menu Example", function()
        -- Render checkboxes
        menu_elements.checkbox_one:render("Checkbox Example One", "")
        menu_elements.checkbox_two:render("Checkbox Example Two", "")

        -- Render slider int and float
        menu_elements.slider_int:render("Slider Int", "")
        menu_elements.slider_float:render("Slider Float", "")

        -- Render the sub menu node
        menu_elements.sub_menu_node:render("More Elements", function()
            -- Render combobox
            menu_elements.combobox:render("ComboBox", {"Option A", "Option B", "Option C"}, "")

            -- Render keybind
            menu_elements.keybind:render("Keybind", "")

            -- Render button
            if menu_elements.button:render("Button", "") then
                core.log("Button was clicked!")
            end

            -- Render color picker
            menu_elements.colorpicker:render("ColorPicker", "")
        end)
    end)
end)
```

---

## Notes

- Always declare your menu elements **outside** of the render callback to prevent creating new instances each frame.
- Use unique IDs for your menu elements to avoid conflicts with other menu elements within your plugin.
- Menu elements can only be rendered inside the `register_on_render_menu_callback` or `register_on_render_window_callback` callbacks.
