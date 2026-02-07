# Rotation Settings UI Library Guide

This guide is for people with little or no UI experience. It explains how to use the shared library
`shared/rotation_settings_ui.lua` to build a custom settings window (with tabs, sliders, checkboxes, and keybinds)
for your own rotation.

## What this library does (in simple words)

- Creates a custom **window** you can show/hide.
- Renders a **tab bar** across the top.
- Inside each tab, you can render common widgets:
  - **Keybind rows** (bind a key, toggle ON/OFF, clear)
  - **Checkbox grids**
  - **Slider lists**
  - **Combobox lists**
- Saves window position/size/tab selection using “ghost” menu elements (so it persists across injections).

You still need to:
- Create your menu elements (checkboxes/sliders/combos/keybinds) in your rotation file.
- Call `ui:on_menu_render()` and `ui:on_render()` from your rotation callbacks.

## Quick start (minimal steps)

1) **Create menu elements** (normal `core.menu.*` elements) in your rotation.
2) **Create a window** via `rotation_settings_ui.new({ ... })`.
3) **Define tabs and content** using `ui:add_tab(...)` (recommended) or `ui:register_section(...)` (legacy).
4) **Hook it into callbacks**:
   - call `ui:on_menu_render()` in `on_menu_render`
   - call `ui:on_render()` in `on_render`

## Full minimal example (copy/paste template)

This is a complete working structure you can adapt.

```lua
local my_rotation = {}
local rotation_settings_ui = require("shared/rotation_settings_ui")

-- 1) Create menu elements (these store settings + persist automatically)
local menu_elements = {
  main_tree = core.menu.tree_node(),

  enable_script_check = core.menu.checkbox(true, "my_rotation_enable_script"),

  -- Keybinds
  enable_toggle = core.menu.keybind(999, true, "my_rotation_enable_toggle"),
  cooldowns_toggle = core.menu.keybind(999, true, "my_rotation_cooldowns_toggle"),

  -- Checkboxes + sliders + combos
  auto_pot_enabled = core.menu.checkbox(true, "my_rotation_auto_pot"),
  auto_pot_threshold = core.menu.slider_int(0, 100, 25, "my_rotation_auto_pot_hp"),

  burst_mode = core.menu.combobox(1, "my_rotation_burst_mode")
}

-- 2) Create the custom UI window
local ui = rotation_settings_ui.new({
  id = "my_rotation",
  title = "My Rotation Settings",
  default_x = 700,
  default_y = 200,
  default_w = 520,
  default_h = 650,
  theme = "neutral" -- "rogue", "hunter", ...
})

-- 3) Define tabs and content (recommended API)
local function auto_pot_enabled()
  return menu_elements.auto_pot_enabled:get_state() == true
end

ui:add_tab({ id = "core", label = "Core" }, function(t)
  t:keybind_grid({
    elements = { menu_elements.enable_toggle, menu_elements.cooldowns_toggle },
    labels = { "Enable Rotation", "Burst Cooldowns" }
  })
end)

ui:add_tab({ id = "survival", label = "Survival" }, function(t)
  t:checkbox_grid({
    label = "Consumables",
    columns = 2,
    elements = {
      { element = menu_elements.auto_pot_enabled, label = "Auto Potion" }
    }
  })

  t:slider_list({
    label = "Thresholds",
    elements = {
      { element = menu_elements.auto_pot_threshold, label = "Potion HP%", suffix = "%", visible_when = auto_pot_enabled }
    }
  })

  t:combo_list({
    label = "Modes",
    elements = {
      { element = menu_elements.burst_mode, label = "Burst Mode", options = { "Smart", "Always" } }
    }
  })
end)

-- 4) Hook into your rotation callbacks
function my_rotation:on_menu_render()
  -- Lets the user toggle the custom window from the normal menu
  ui:on_menu_render()

  menu_elements.main_tree:render("My Rotation", function()
    menu_elements.enable_script_check:render("Enable Script")
    if ui and ui.menu and ui.menu.enable then
      ui.menu.enable:render("Show Custom UI Window")
    end
  end)
end

function my_rotation:on_render()
  -- Draw the custom window every frame (it only shows if enabled)
  ui:on_render()
end

return my_rotation
```

## Building tabs with the Builder API (recommended)

Use `ui:add_tab({ ... }, function(t) ... end)`.
Inside the callback, `t` is a tab builder.

Supported builder methods:

- `t:keybind_grid({ elements = {keybind1, keybind2, ...}, labels = {"Label1", ...} })`
- `t:checkbox_grid({ label?, columns?, elements = { {element=checkbox, label="..."}, ... } })`
- `t:slider_list({ label?, elements = { {element=slider, label="...", suffix?, visible_when?}, ... } })`
- `t:combo_list({ label?, elements = { {element=combobox, label="...", options={...}, suffix?, visible_when?}, ... } })`

### What “elements” look like

#### Checkbox grid entry

```lua
{ element = menu_elements.auto_pot_enabled, label = "Auto Potion", visible_when = function() return true end }
```

#### Slider list entry

```lua
{ element = menu_elements.auto_pot_threshold, label = "Potion HP%", suffix = "%", visible_when = auto_pot_enabled }
```

#### Combobox list entry

```lua
{ element = menu_elements.burst_mode, label = "Burst Mode", options = { "Smart", "Always" } }
```

## Conditional visibility (`visible_when`)

You can hide:
- a full **tab** (`ui:add_tab({ ..., visible_when = fn }, ...)`)
- a **group** (pass `visible_when` to `checkbox_grid` / `slider_list` / …)
- a single **entry** in a group (each entry can contain `visible_when`)

Rules:
- `visible_when` must be a function that returns `true` or `false`.
- Keep it quick and safe: don’t do heavy work inside it.

Example:

```lua
local function advanced_enabled()
  return menu_elements.show_advanced:get_state() == true
end

ui:add_tab({ id="advanced", label="Advanced", visible_when = advanced_enabled }, function(t)
  t:slider_list({ elements = { { element = menu_elements.some_slider, label = "Extra" } } })
end)
```

## Themes and window identity

### Theme
`theme` only affects colors. Available themes are defined in `shared/rotation_settings_ui.lua` (e.g. `neutral`, `rogue`, `hunter`).

### `id` (important)
`id` must be unique per window. It is used for persistence menu element IDs:
- window position / size
- active tab
- enable checkbox (show/hide window)

If two windows share the same `id`, they will fight over saved state.

## Interaction notes (keybinds and sliders)

### Keybind capture
- Click the key badge to start capture, then press a key.
- Supports keyboard + mouse buttons (except LMB/RMB).
- `Del` clears the bind, `Esc` cancels.

### Sliders
- Click the bar to start dragging and hold left mouse button.
- Dragging clamps at min/max.

If a slider “jumps”, it usually means the backend provides mouse position in a different coordinate space.
This library already tries to normalize that, but if you find a backend where it still jumps, report:
- which slider it happens on
- where the window is on screen (left/right/top/bottom)

## Legacy API (still supported)

You can still build the UI with `register_section(...)` if you prefer:

```lua
ui:register_section({
  id = "combat",
  label = "Combat",
  type = "tab",
  groups = {
    {
      label = "Thresholds",
      type = "slider_list",
      elements = {
        { element = menu_elements.auto_pot_threshold, label = "Potion HP%", suffix = "%" }
      }
    }
  }
})
```

## Troubleshooting (common mistakes)

### “Nothing shows up”
- Make sure you call `ui:on_render()` inside your rotation `on_render` callback.
- Enable the window: either call `ui:on_menu_render()` and toggle “Show Custom UI Window”, or set `ui.menu.enable:set(true)` once for debugging.

### “Tab is empty”
- Ensure you added groups inside the `add_tab` callback.
- Check `visible_when` isn’t returning false.

### “My widgets don’t change values”
- Ensure your menu elements are real `core.menu.*` objects (checkbox/slider/combobox/keybind), not plain Lua values.
- For sliders: keep min/max sensible (min <= max).

