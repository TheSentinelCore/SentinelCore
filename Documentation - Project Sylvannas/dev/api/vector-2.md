---
title: "Vector 2D"
source: "https://docs.project-sylvanas.net/dev/api/vector-2"
crawled: "2026-07-14"
---

# Vector 2D

## Overview

The `vec2` module provides functions for working with 2D vectors in Lua scripts. These functions include vector creation, arithmetic operations, normalization, length calculation, dot product calculation, interpolation, randomization, rotation, and more.

tip

If you are new and don't know what a vec2 is and want a deep understanding of this class, and specially, the vec3 data structure, you might want to study some Linear Algebra. This information is basic and it will be usefull for any game-related project that you might work on in the future.

## Importing the Module

warning

This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the `require` function and store it in a local variable.

Here is an example of how to do it:

```
---@type vec2local vec2 = require("common/geometry/vector_2")
```

## Functions

### Vector Creation and Cloning

### `new(x, y)`

Creates a new 2D vector with the specified x and y components.

Parameters:

-   **`x`** (*number*) — The x component of the vector.
-   **`y`** (*number*) — The y component of the vector.

Returns: *vec2* — A new vector instance.

---

### `clone()`

Clones the current vector.

Returns: *vec2* — A new vector instance that is a copy of the original.

---

### Arithmetic Operations

### `__add(other)`

Overloads the addition operator (`+`) for vector addition.

Parameters:

-   **`other`** (*vec2*) — The vector to add.

Returns: *vec2* — The result of the addition.

warning

Do not use this function directly. Instead, just use the operator `+`. For example:

```
---@type vec2local vec2 = require("common/geometry/vector_2")local v1 = vec2.new(1, 1)local v2 = vec2.new(2, 2)--- Bad code:-- local v3 = v1:__add(v2)--- Correct code:local v3 = v1 + v2
```

---

### `__sub(other)`

Overloads the subtraction operator (`-`) for vector subtraction.

Parameters:

-   **`other`** (*vec2*) — The vector to subtract.

Returns: *vec2* — The result of the subtraction.

warning

Do not use this function directly. Instead, just use the operator `-`. For example:

```
---@type vec2local vec2 = require("common/geometry/vector_2")local v1 = vec2.new(1, 1)local v2 = vec2.new(2, 2)--- Bad code:-- local v3 = v1:__sub(v2)--- Correct code:local v3 = v1 - v2
```

---

### `__mul(value)`

Overloads the multiplication operator (`*`) for scalar multiplication or element-wise multiplication.

Parameters:

-   **`value`** (*number* or *vec2*) — The scalar or vector to multiply with.

Returns: *vec2* — The result of the multiplication.

warning

Do not use this function directly. Instead, just use the operator `*`. For example:

```
---@type vec2local vec2 = require("common/geometry/vector_2")local v1 = vec2.new(1, 1)local v2 = vec2.new(2, 2)--- Bad code:-- local v3 = v1:__mul(v2)--- Correct code:local v3 = v1 * v2
```

---

### `__div(value)`

Overloads the division operator (`/`) for scalar division or element-wise division.

Parameters:

-   **`value`** (*number* or *vec2*) — The scalar or vector to divide by.

Returns: *vec2* — The result of the division.

warning

Do not use this function directly. Instead, just use the operator `/`. For example:

```
---@type vec2local vec2 = require("common/geometry/vector_2")local v1 = vec2.new(1, 1)local v2 = vec2.new(2, 2)--- Bad code:-- local v3 = v1:__div(v2)--- Correct code:local v3 = v1 / v2
```

---

### Vector Properties and Methods

### `normalize()`

Returns the normalized vector (unit vector) of the current vector.

Returns: *vec2* — The normalized vector.

---

### `length()`

Returns the length (magnitude) of the vector.

Returns: *number* — The length of the vector.

---

### `dot(other)`

Calculates the dot product of two vectors.

Parameters:

-   **`other`** (*vec2*) — The other vector.

Returns: *number* — The dot product.

---

### `lerp(target, t)`

Performs linear interpolation between two vectors.

Parameters:

-   **`target`** (*vec2*) — The target vector.
-   **`t`** (*number*) — The interpolation factor (between 0.0 and 1.0).

Returns: *vec2* — The interpolated vector.

---

### Advanced Operations

### `randomize_xy(margin)`

Randomizes the x and y components of the vector within a specified margin.

Parameters:

-   **`margin`** (*number*) — The maximum value to add or subtract from each component.

Returns: *vec2* — The randomized vector.

---

### `rotate_around(origin, angle_degrees)`

Rotates the vector around a specified origin point by a given angle in degrees.

Parameters:

-   **`origin`** (*vec2*) — The origin point to rotate around.
-   **`angle_degrees`** (*number*) — The angle in degrees.

Returns: *vec2* — The rotated vector.

---

### `dist_to(other)`

Calculates the distance to another vector.

Parameters:

-   **`other`** (*vec2*) — The other vector.

Returns: *number* — The distance between the vectors.

---

### `get_angle(origin)`

Calculates the angle between the vector and the x-axis, relative to a specified origin point.

Parameters:

-   **`origin`** (*vec2*) — The origin point.

Returns: *number* — The angle in degrees.

---

### `intersects(p1, p2)`

Checks if the vector (as a point) intersects with a line segment defined by two vectors.

Parameters:

-   **`p1`** (*vec2*) — The first point of the line segment.
-   **`p2`** (*vec2*) — The second point of the line segment.

Returns: *boolean* — `true` if the point intersects the line segment; otherwise, `false`.

---

### `get_perp_left(origin)`

Returns the left perpendicular vector of the current vector relative to a specified origin point.

Parameters:

-   **`origin`** (*vec2*) — The origin point.

Returns: *vec2* — The left perpendicular vector.

---

### `get_perp_left_factor(origin, factor)`

Returns the left perpendicular vector of the vec2 instance with a factor applied.

Parameters:

-   **`origin`** (*vec2*) — The origin point.
-   **`factor`** (*number*) — The factor to apply.

Returns: *vec2* — The left perpendicular vector.

---

### `get_perp_right(origin)`

Returns the right perpendicular vector of the current vector relative to a specified origin point.

Parameters:

-   **`origin`** (*vec2*) — The origin point.

Returns: *vec2* — The right perpendicular vector.

---

### `get_perp_right_factor(origin, factor)`

Returns the right perpendicular vector of the vec2 instance with a factor applied.

Parameters:

-   **`origin`** (*vec2*) — The origin point.
-   **`factor`** (*number*) — The factor to apply.

Returns: *vec2* — The right perpendicular vector.

---

### Additional Functions

### `dot_product(other)`

An alternative method to calculate the dot product of two vectors.

Parameters:

-   **`other`** (*vec2*) — The other vector.

Returns: *number* — The dot product.

---

### `is_nan()`

Checks if the vector is not a number.

Returns: *boolean* — True if the vector_2 is not a number, false otherwise.

---

### `is_zero()`

Checks if the vector is zero.

Returns: *boolean* — True if the vector_2 is the vector(0,0), false otherwise.

tip

Saying that a vector is_zero is the same as saying that the said vector equals the vec2.new(0,0)

---

## Code Examples

### Example 1: Vector Addition

```
---@type vec2local vec2 = require("common/geometry/vector_2")core.register_on_render_callback(function()    local local_player = core.object_manager.get_local_player()    if not local_player then        return    end    -- example vectors    local v1 = vec2.new(500.0, 350.0)    local v2 = vec2.new(100.0, 100.0)    local v3 = v1 + v2 -- (this is the result of adding v2 to v1)    -- this is the blue line in the picture (a line from v1 to v3)    core.graphics.line_2d(v1, v3, color.cyan(255))    -- red circle at v1 position    core.graphics.circle_2d(v1, 20.0, color.red(255))    -- we adjust the text position by substracting a new vector    local v1_text_position = v1 - vec2.new(10.0, 15.0)    -- and finally draw the "v1" text at the position that we just calculated    core.graphics.text_2d("v1", v1_text_position, 20, color.red(255))    -- green circle at v3 position    core.graphics.circle_2d(v3, 20.0, color.green_pale(255))    -- we adjust the text position by substracting a new vector    local v3_text_position = v3 - vec2.new(10.0, 10.0)    -- and finally draw the "v3" text at the position that we just calculated    core.graphics.text_2d("v3", v3_text_position, 20, color.green(255))end)
```

This should be the result after running that piece of code:

![vector_add](../../images/1727780263019-vector_add.png)

### Example 2: Vector Dot Product

```
---@type vec2local vec2 = require("common/geometry/vector_2")-- Create two vectorslocal v1 = vec2.new(3, 5)local v2 = vec2.new(2, 8)-- Calculate the dot productlocal dot_product = v1:dot(v2)-- Print the dot productcore.log("Dot product of the vectors: " .. dot_product)
```

### Example 3: Vector Normalization

```
---@type vec2local vec2 = require("common/geometry/vector_2")-- Create a vectorlocal v = vec2.new(3, 4)-- Normalize the vectorlocal normalized = v:normalize()-- Print the normalized vectorcore.log("Normalized vector: (" .. normalized.x .. ", " .. normalized.y .. ")")
```

### Example 4: Vector Rotation

```
---@type vec2local vec2 = require("common/geometry/vector_2")core.register_on_render_callback(function()    local local_player = core.object_manager.get_local_player()    if not local_player then        return    end    -- example vectors    local v1 = vec2.new(500.0, 350.0)    -- local v2 = vec2.new(100.0, 100.0)    -- rotate the vector 90 degrees around the origin    local v2 = v1:rotate_around(vec2.new(0, 0), 90)    -- extend the starting position to the rotated position by 100    local v3 = v1:get_extended(v2, 100.0)    -- this is the blue line in the picture (a line from v1 to v3)    core.graphics.line_2d(v1, v3, color.cyan(255))    -- red circle at v1 position    core.graphics.circle_2d(v1, 20.0, color.red(255))    -- we adjust the text position by substracting a new vector    local v1_text_position = v1 - vec2.new(10.0, 15.0)    -- and finally draw the "v1" text at the position that we just calculated    core.graphics.text_2d("v1", v1_text_position, 20, color.red(255))    -- green circle at v3 position    core.graphics.circle_2d(v3, 20.0, color.green_pale(255))    -- we adjust the text position by substracting a new vector    local v3_text_position = v3 - vec2.new(10.0, 10.0)    -- and finally draw the "v3" text at the position that we just calculated    core.graphics.text_2d("v3", v3_text_position, 20, color.green(255))end)
```

This is the expected result after running that code:

![v2_rotation_1](../../images/1727781068572-v2_rotation_1.png)

If we rotate it by -90 degrees instead of 90, this is what we should be seeing now:

![v2_rotation_2](../../images/1727781072508-v2_rotation_2.png)