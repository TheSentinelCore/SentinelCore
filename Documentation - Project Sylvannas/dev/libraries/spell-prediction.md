---
title: "Spell Prediction"
source: "https://docs.project-sylvanas.net/dev/libraries/modules/spell-prediction"
crawled: "2026-07-14"
---

# Spell Prediction

## Overview

The `spell_prediction` module provides functions and utilities for predicting spell cast positions and determining optimal targets based on different prediction methods and geometries. This is a module that we provide to you, however we are basically using the geometry library and some math, so you could always try to make your own prediction and differentiate yourself from others.

## Importing The Module

> **Warning:** This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the `require` function and store it in a local variable.

Here is an example of how to do it:

```lua
-- recomended "spell_prediction" name for consistency
---@type spell_prediction
local spell_prediction = require("common/modules/spell_prediction")
```

## Using the Prediction Playground

In the main menu you will see that there is a "Prediction Playground" tree node. This plugin is multi-purpose. Firstly, it offers a visual way to see how prediction works, and on the other hand it will allow you to determine the accurate spell data of some spells.

This is what you should be seeing upon opening the tree node:

![Prediction Playground](../../images/1727865806647-pred_playground_1.png)

Available Options - Brief Explanation

1- Source: Where the spell will be launched from.
2- Target: Where the spell will arrive.
3- Type: The prediction mode. The position output will be either the best possible position to hit the main target, if type is "Accuracy" or the best possible position to hit the most targets, if type is "Most Hits".
4- Geometry: The geometry type.
5- Radius: The radius of the debug spell.
6- Range: The range of the debug spell.
7- Angle: The angle of the cone. *(Make sure the spell geometry is set to "Cone")*
8- Cast Time: The cast time of the debug spell.
9- Projectile Speed: The projectile speed. Leave to 0 since Blizzard doesn't care about projectiles apparently.
10- Override Hit Time: Option to override the calculated hit time. If 0.0, no override happens.
11- Override Hitbox Min: Option to override the hitbox min radius of the target. If 0.0, no override happens.
12- Draw Hits Amount: Option to draw the calculated amount of hits, with the given spell data. *(Red text)*
13- Draw Hits Amount: Option to draw a circle on the calculated hits positions, with the given spell data. *(Blue circle)*
14- Cache Slider: The refresh rate of the spell result cache.

As you can see, this is a powerful tool to retrieve the correct spell datas too, since you can check when you are hitting the targets with accuracy, at the given spell data.

> **Note:** This plugin will be open source, for anyone to check its code and play with it.

## Enums

### `prediction_type`

Defines the prediction mode for the spell.

-   **`ACCURACY`**: Accuracy-based prediction.
-   **`MOST_HITS`**: Prediction to hit the maximum number of targets.

### `geometry_type`

Defines the geometry type of the spell's area of effect.

-   **`CIRCLE`**: Circular area.
-   **`RECTANGLE`**: Rectangular area.
-   **`CONE`**: Conical area.

---

## Data Types

### `spell_data`

A table containing the following fields:

-   **`spell_id`** (*number*) — The ID of the spell.
-   **`max_range`** (*number*) — The maximum range of the spell.
-   **`radius`** (*number*) — The radius of the spell's area of effect.
-   **`cast_time`** (*number*) — The cast time of the spell.
-   **`projectile_speed`** (*number*) — The speed of the spell's projectile.
-   **`prediction_mode`** (*prediction_type*) — The prediction mode for the spell.
-   **`geometry_type`** (*geometry_type*) — The geometry type of the spell's area of effect.
-   **`source_position`** ([vec3](/dev/api/vector-3)) — The source position of the spell.
-   **`intersection_factor`** (*number*) — The intersection factor for the spell.
-   **`angle`** (*number*) — The angle of the spell's area of effect (for cones).
-   **`exception_is_heal`** (*boolean*) — Whether the spell is a healing spell.
-   **`exception_player_included`** (*boolean*) — Whether to include the player in the spell's effect.
-   **`hitbox_min`** (*number*) — The minimum hitbox radius.
-   **`hitbox_max`** (*number*) — The maximum hitbox radius.
-   **`hitbox_mult`** (*number*) — The hitbox multiplier.
-   **`time_to_hit_override`** (*number*) — The override value for time to hit.

---

### `hit_data`

A table containing the following fields:

-   **`obj`** (*game_object*) — The [game_object](/dev/api/game-object) of the unit.
-   **`center_position`** ([vec3](/dev/api/vector-3)) — The center position of the unit.
-   **`intersection_position`** ([vec3](/dev/api/vector-3)) — The intersection position of the unit.

---

### `skillshot_result`

A table containing the following fields:

-   **`hit_list`** (*table(hit_data)*) — A list of `hit_data` tables for the units hit.
-   **`amount_of_hits`** (*number*) — The number of units hit.
-   **`cast_position`** ([vec3](/dev/api/vector-3)) — The cast position for the spell.

---

## Functions

### `new_spell_data(spell_id, max_range, radius, cast_time, projectile_speed, prediction_mode, geometry, source_position, intersection_factor, angle, exception_is_heal, exception_player_included)`

Creates new spell data with default or specified values.

Parameters:

-   **`spell_id`** (*number*) — The ID of the spell.
-   **`max_range`** (*number*, optional) — The maximum range of the spell.
-   **`radius`** (*number*, optional) — The radius of the spell's area of effect.
-   **`cast_time`** (*number*, optional) — The cast time of the spell.
-   **`projectile_speed`** (*number*, optional) — The speed of the spell's projectile.
-   **`prediction_mode`** (*prediction_type*, optional) — The prediction mode for the spell.
-   **`geometry`** (*geometry_type*, optional) — The geometry type of the spell's area of effect.
-   **`source_position`** ([vec3](/dev/api/vector-3), optional) — The source position of the spell.
-   **`intersection_factor`** (*number*, optional) — The interception factor for the spell.
-   **`angle`** (*number*, optional) — The angle of the spell's area of effect (for cones).
-   **`exception_is_heal`** (*boolean*, optional) — Whether the spell is a healing spell.
-   **`exception_player_included`** (*boolean*, optional) — Whether to include the player in the spell's effect.

Returns: *spell_data* — A table containing the spell data.

---

### `get_center_position(target, spell_data)`

Gets the center position of a target.

Parameters:

-   **`target`** (*game_object*) — The target [game_object](/dev/api/game-object).
-   **`spell_data`** (*spell_data*) — The spell data.

Returns: [vec3](/dev/api/vector-3) — The center position of the target.

---

### `get_intersection_position(target, center_position, circle_radius, interception_percentage)`

Gets the intersection position for casting the spell.

Parameters:

-   **`target`** (*game_object*) — The target [game_object](/dev/api/game-object).
-   **`center_position`** ([vec3](/dev/api/vector-3)) — The center position of the target.
-   **`circle_radius`** (*number*) — The radius of the spell's area of effect.
-   **`interception_percentage`** (*number*) — The interception factor for the spell.

Returns: [vec3](/dev/api/vector-3) — The intersection position for casting the spell.

---

### `get_unit_list(position, range, is_heal)`

Gets the list of units around a position.

Parameters:

-   **`position`** ([vec3](/dev/api/vector-3)) — The position to check around.
-   **`range`** (*number*) — The range to check within.
-   **`is_heal`** (*boolean*, optional) — Whether the spell is a healing spell.

Returns: *table(hit_data)* — A list of units around the position.

---

### `get_circle_list(target_position, spell_data, is_heal)`

Gets the list of units inside a circle.

Parameters:

-   **`target_position`** ([vec3](/dev/api/vector-3)) — The center position of the circle.
-   **`spell_data`** (*spell_data*) — The spell data.
-   **`is_heal`** (*boolean*, optional) — Whether the spell is a healing spell.

Returns: *table(hit_data)* — A list of units inside the circle.

---

### `get_rectangle_list(target_position, spell_data, is_heal)`

Gets the list of units inside a rectangle.

Parameters:

-   **`target_position`** ([vec3](/dev/api/vector-3)) — The center position of the rectangle.
-   **`spell_data`** (*spell_data*) — The spell data.
-   **`is_heal`** (*boolean*, optional) — Whether the spell is a healing spell.

Returns: *table(hit_data)* — A list of units inside the rectangle.

---

### `get_cone_list(target_position, spell_data, is_heal)`

Gets the list of units inside a cone.

Parameters:

-   **`target_position`** ([vec3](/dev/api/vector-3)) — The center position of the cone.
-   **`spell_data`** (*spell_data*) — The spell data.
-   **`is_heal`** (*boolean*, optional) — Whether the spell is a healing spell.

Returns: *table(hit_data)* — A list of units inside the cone.

---

### `get_unit_geometry_list(position, spell_data)`

Gets the list of units inside a specified geometry.

Parameters:

-   **`position`** ([vec3](/dev/api/vector-3)) — The center position of the geometry.
-   **`spell_data`** (*spell_data*) — The spell data.

Returns: *table(hit_data)* — A list of units inside the geometry.

---

### `get_most_hits_position(main_position, spell_data)`

Gets the best position to hit the most units.

Parameters:

-   **`main_position`** ([vec3](/dev/api/vector-3)) — The center position to check from.
-   **`spell_data`** (*spell_data*) — The spell data.

Returns: *skillshot_result* — A table containing the best cast position and list of units hit.

---

### `get_cast_position(target, spell_data)`

Gets the cast position based on the prediction mode.

Parameters:

-   **`target`** (*game_object*) — The target [game_object](/dev/api/game-object).
-   **`spell_data`** (*spell_data*) — The spell data.

Returns: *skillshot_result* — A table containing the cast position and list of units hit.

---

### `get_cast_position_(position_override, spell_data)`

Gets the cast position based on the prediction mode with a position override.

Parameters:

-   **`position_override`** ([vec3](/dev/api/vector-3)) — The overridden position to check from.
-   **`spell_data`** (*spell_data*) — The spell data.

Returns: *skillshot_result* — A table containing the cast position and list of units hit.

---

## Example Usage

### Using the Spell Prediction to Cast Blizzard

```lua
---@type spell_queue
local spell_queue = require("common/modules/spell_queue")

---@type spell_helper
local spell_helper = require("common/utility/spell_helper")

---@type spell_prediction
local spell_prediction = require("common/modules/spell_prediction")

local function cast_blizzard_to_hud_target()
    local local_player = core.object_manager.get_local_player()
    if local_player then
        local hud_target = local_player:get_target()
        if hud_target then
            local blizzard_id = 10
            local player_position = local_player:get_position()

            local prediction_spell_data = spell_prediction:new_spell_data(
                blizzard_id,                                    -- spell_id
                30,                                             -- range
                6,                                              -- radius
                0.2,                                            -- cast_time
                0.0,                                            -- projectile_speed
                spell_prediction.prediction_type.MOST_HITS,     -- prediction_type
                spell_prediction.geometry_type.CIRCLE,          -- geometry_type
                player_position                                 -- source_position
            )

            if spell_helper:is_spell_castable(blizzard_id, local_player, hud_target, false, false) then
                local prediction_result = spell_prediction:get_cast_position(hud_target, prediction_spell_data)

                if prediction_result and prediction_result.amount_of_hits > 0 then
                    spell_queue:queue_spell_position(blizzard_id, prediction_result.cast_position, 1, "Queueing Blizzard at optimal position")
                end
            end
        end
    end
end
```

This code:

1.  Sets up a Blizzard spell with prediction data
2.  Uses `MOST_HITS` prediction type to maximize the spell's impact
3.  Queues the Blizzard at the optimal position if targets are predicted to be hit

### Priest Death and Decay - Functionality Showcase

![Priest Death and Decay](../../images/1726863254744-docs_input_prediction_most_hits.png)

> **Note:** As you can see, we call `prediction_type.MOST_HITS` to fire Death and Decay on the Priest. Instead of casting on the center, it strategically places the spell slightly to the left to hit extra dummies aswell.

> **Tip:** Test with the `prediction_type.ACCURACY` values for pinpointing situations where the cast should be avoided

---

## Advanced Tips

-   Intersection Factor: Adjust `intersection_factor` in `spell_data` to control how the spell prediction accounts for moving targets. A higher value can anticipate where the target will be in the future.

-   Angle for Cones: When using `geometry_type.CONE`, ensure you set the `angle` parameter in `spell_data` to define the cone's spread.

-   Healing Spells: Set `exception_is_heal` to `true` if you're working with healing spells to target friendly units instead of enemies.

-   Prediction Modes: Use `prediction_type.ACCURACY` for single-target precision or `prediction_type.MOST_HITS` to maximize the number of targets hit.

-   Geometry Types: Choose the appropriate `geometry_type` based on your spell's area of effect shape.

-   Customizing Spell Data: When creating `spell_data`, you can override default values to fine-tune the prediction to match your spell's characteristics.

-   Exceptions: Use `exception_is_heal` and `exception_player_included` to adjust the prediction logic for healing spells or whether to include the player character.

---

## Common Use Cases

-   Area of Effect Spells: Use `prediction_type.MOST_HITS` with `geometry_type.CIRCLE` or `RECTANGLE` to maximize damage or healing.
-   Skill Shots: For spells that require precise targeting, use `prediction_type.ACCURACY` to predict the best cast position based on the target's movement.
-   Crowd Control: Combine prediction with geometry calculations to immobilize or debuff multiple enemies effectively.

---

## Troubleshooting

-   Incorrect Cast Position: Verify that your `spell_data` parameters accurately reflect the spell's actual in-game properties.
-   No Targets Hit: Ensure that the `get_unit_list` function is correctly identifying units within range and that `exception_is_heal` is set appropriately.
-   Performance Issues: Limit the frequency of prediction calculations to prevent performance degradation, especially in scripts that run every frame.
