---
title: "Target Selector"
source: "https://docs.project-sylvanas.net/dev/libraries/modules/target-selector"
crawled: "2026-07-14"
---

# Target Selector

## Overview

The Target Selector module gives you the tools to effectively retrieve the best targets for your logics. Its basic usage is very simple, so we encourage you to use this module in all your damage or healing-related plugins.

## Importing The Module

As with all other LUA modules developed by us, you will need to **import** the Target Selector module into your project. To do so, you can use the following lines:

```lua
---@type target_selector
local target_selector = require("common/modules/target_selector")
```

> **Warning:** To access the module's functions, you **must** use `:` instead of `.`

For example, this code is **not correct**:

```lua
---@type target_selector
local target_selector = require("common/modules/target_selector")

local function get_targets()
    return target_selector.get_targets()
end
```

And this would be the **corrected code**:

```lua
---@type target_selector
local target_selector = require("common/modules/target_selector")

local function get_targets()
    return target_selector:get_targets()
end
```

## Functions

### `get_targets(limit: integer (optional)) -> table<game_object>`

-   Retrieves the table containing the best targets possible, according to the current Target Selector settings.
-   The max number of targets it returns is 3 , but you can limit it to less by specifying the limit parameter.

### `get_targets_heal(limit: integer (optional)) -> table<game_object>`

-   Retrieves the table containing the best targets to heal possible, according to the current Target Selector settings.
-   The max number of targets it returns is 3 , but you can limit it to less by specifying the limit parameter.

### Manually Modifying the Settings

Altough the TS config should be good to go by default, you can manually set them inside your plugin. To do so, you have to access the target selector's menu elements and modify them. For example:

```lua
---@type target_selector
local target_selector = require("common/modules/target_selector")

-- this function is a simple one, not necessarily the best one for mage fires. This is just an example.
local is_ts_overriden = false

local function override_ts_settings()
    if is_ts_overriden then
        return
    end

    target_selector.menu_elements.damage.weight_multiple_hits:set(true)
    target_selector.menu_elements.damage.slider_weight_multiple_hits:set(4)
    target_selector.menu_elements.damage.slider_weight_multiple_hits_radius:set(8)
    target_selector.menu_elements.settings.max_range_damage:set(40)

    is_ts_overriden = true
end
```

In the previous example, we are manually setting the weight to multiple hits, and the max range of the TS. You can do this for all the parameters.

> **Warning:** In general, you will never need to modify the settings. If you have to modify them, we suggest that you add a menu element to give the user the power to disable your custom TS. For example:

```lua
---@type target_selector
local target_selector = require("common/modules/target_selector")

local is_ts_overriden = false

local function override_ts_settings()
    if is_ts_overriden then
        return
    end

    -- define this menu element elsewhere in your code, and render it
    local is_override_allowed = menu_elements.ts_custom_logic_override:get_state()

    if not is_override_allowed then
        return
    end

    target_selector.menu_elements.damage.is_damage_enabled:set(true)
    target_selector.menu_elements.damage.is_damage_enabled:set(true)
    target_selector.menu_elements.damage.weight_multiple_hits:set(true)
    target_selector.menu_elements.damage.slider_weight_multiple_hits:set(4)
    target_selector.menu_elements.damage.slider_weight_multiple_hits_radius:set(8)
    target_selector.menu_elements.settings.max_range_damage:set(40)

    is_ts_overriden = true
end
```
