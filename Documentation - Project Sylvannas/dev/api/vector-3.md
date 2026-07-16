---
title: "Vector 3D"
source: "https://docs.project-sylvanas.net/dev/api/vector-3"
crawled: "2026-07-14"
---

# Vector 3D

## Overview

The `vec3` module provides functions for working with 3D vectors in Lua scripts. These functions include vector creation, arithmetic operations, normalization, length calculation, dot and cross product calculation, interpolation, randomization, rotation, distance calculation, angle calculation, intersection checking, and more.

tip

If you are new and don't know what a `vec3` is and want a deep understanding of this class, or the vec2 data structure, you might want to study some Linear Algebra. This information is basic and it will be useful for any game-related project that you might work on in the future. Since vec3 has 1 more coordinate in the space, working with vec3 is a little bit more complex. Therefore, if you are new, we recommend you to study vec2 first.

## Importing the Module

warning

This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the `require` function and store it in a local variable.

Here is an example of how to do it:

```
---@type vec3local vec3 = require("common/geometry/vector_3")
```

## Functions

### Vector Creation and Cloning

### `new(x, y, z)`

Creates a new 3D vector with the specified x, y, and z components.

Parameters:

-   **`x`** (*number*) — The x component of the vector.
-   **`y`** (*number*) — The y component of the vector.
-   **`z`** (*number*) — The z component of the vector.

Returns: *vec3* — A new vector instance.

note

If no number is passed as parameter (you construct the vector by using vec3.new()) then, a vector_3 is constructed with the values (0,0,0). So, :is_zero will be true.

---

### `clone()`

Clones the current vector.

Returns: *vec3* — A new vector instance that is a copy of the original.

---

### Arithmetic Operations

### `__add(other)`

Overloads the addition operator (`+`) for vector addition.

Parameters:

-   **`other`** (*vec3*) — The vector to add.

Returns: *vec3* — The result of the addition.

warning

Do not use this function directly. Instead, just use the operator `+`. For example:

```
---@type vec3local vec3 = require("common/geometry/vector_3")local v1 = vec3.new(1, 1, 0)local v2 = vec3.new(2, 2, 2)--- Bad code:-- local v3 = v1:__add(v2)--- Correct code:local v3 = v1 + v2
```

---

### `__sub(other)`

Overloads the subtraction operator (`-`) for vector subtraction.

Parameters:

-   **`other`** (*vec3*) — The vector to subtract.

Returns: *vec3* — The result of the subtraction.

warning

Do not use this function directly. Instead, just use the operator `-`. For example:

```
---@type vec3local vec3 = require("common/geometry/vector_3")local v1 = vec3.new(1, 1, 0)local v2 = vec3.new(2, 2, 2)--- Bad code:-- local v3 = v1:__sub(v2)--- Correct code:local v3 = v1 - v2
```

---

### `__mul(value)`

Overloads the multiplication operator (`*`) for scalar multiplication or element-wise multiplication.

Parameters:

-   **`value`** (*number* or *vec3*) — The scalar or vector to multiply with.

Returns: *vec3* — The result of the multiplication.

warning

Do not use this function directly. Instead, just use the operator `*`. For example:

```
---@type vec3local vec3 = require("common/geometry/vector_3")local v1 = vec3.new(1, 1, 0)local v2 = vec3.new(2, 2, 2)--- Bad code:-- local v3 = v1:__mul(v2)--- Correct code:local v3 = v1 * v2
```

---

### `__div(value)`

Overloads the division operator (`/`) for scalar division or element-wise division.

Parameters:

-   **`value`** (*number* or *vec3*) — The scalar or vector to divide by.

Returns: *vec3* — The result of the division.

warning

Do not use this function directly. Instead, just use the operator `/`. For example:

```
---@type vec3local vec3 = require("common/geometry/vector_3")local v1 = vec3.new(1, 1, 0)local v2 = vec3.new(2, 2, 2)--- Bad code:-- local v3 = v1:__div(v2)--- Correct code:local v3 = v1 / v2
```

---

### `__eq(value)`

Overloads the equals operator (`==`).

Parameters:

-   **`value`** (*vec3*) — The vector 3 to check if it's equal.

Returns: *boolean* — True if both vectors are equal, false otherwise.

warning

Do not use this function directly. Instead, just use the operator `==`. For example:

```
---@type vec3local vec3 = require("common/geometry/vector_3")local v1 = vec3.new(1, 1, 0)local v2 = vec3.new(2, 2, 2)--- Bad code:-- local are_v1_and_v2_the_same = v1:__eq(v2)--- Correct code:local are_v1_and_v2_the_same = v1 == (v2)
```

---

### Vector Properties and Methods

### `normalize()`

Returns the normalized vector (unit vector) of the current vector.

Returns: *vec3* — The normalized vector.

---

### `length()`

Returns the length (magnitude) of the vector.

Returns: *number* — The length of the vector.

---

### `dot(other)`

Calculates the dot product of two vectors.

Parameters:

-   **`other`** (*vec3*) — The other vector.

Returns: *number* — The dot product.

---

### `cross(other)`

Calculates the cross product of two vectors.

Parameters:

-   **`other`** (*vec3*) — The other vector.

Returns: *vec3* — The cross product vector.

---

### `lerp(target, t)`

Performs linear interpolation between two vectors.

Parameters:

-   **`target`** (*vec3*) — The target vector.
-   **`t`** (*number*) — The interpolation factor (between 0.0 and 1.0).

Returns: *vec3* — The interpolated vector.

---

### Advanced Operations

### `rotate_around(origin, angle_degrees)`

Rotates the vector around a specified origin point by a given angle in degrees.

Parameters:

-   **`origin`** (*vec3*) — The origin point to rotate around.
-   **`angle_degrees`** (*number*) — The angle in degrees.

Returns: *vec3* — The rotated vector.

---

### `dist_to(other)`

Calculates the Euclidean distance to another vector.

Parameters:

-   **`other`** (*vec3*) — The other vector.

Returns: *number* — The distance between the vectors.

tip

Usually, you would want to use dist_to_ignore_z, since for most cases you don't really care about the Z component of the vector (height differences). We recommend using squared_dist_to_ignore_z, instead of dist_to_ignore_z or squared_dist_to instead of dist_to. If you check the mathematical formula to calculate a distance between 2 vectors, you will see there is a square root operation there. This is computationally expensive, so, for performance reasons, we advise you to just use the square function and then compare it to the value you want to compare it, but squared. For example:

```
-- check if the distance between v1 and v2 is > 10.0---@type vec3local vec3 = require("common/geometry/vector_3")local v1 = vec3.new(5.0, 5.0, 5.0)local v2 = vec3.new(10.0, 10.0, 10.0)local distance_check = 10.0local distance_check_squared = distance_check * distance_check-- method 1: BADlocal distance = v1:dist_to(v2)local is_dist_superior_to_10_method1 = distance > distance_checkcore.log("Method 1 result: " .. tostring(is_dist_superior_to_10_method1))-- method 2: GOODlocal distance_squared = v1:squared_dist_to(v2)local is_dist_superior_to_10_method2 = distance_squared > distance_check_squaredcore.log("Method 2 result: " .. tostring(is_dist_superior_to_10_method2))
```

If you run the previous code, you will notice that the result from the first method is the same as the result from the second method. However, the second one is much more efficient. This will make no difference in a low scale, but if you have multiple distance checks in your code it will end up being very noticeable in the user's FPS counter.

---

### `squared_dist_to(other)`

Calculates the Euclidean squared distance to another vector.

Parameters:

-   **`other`** (*vec3*) — The other vector.

Returns: *number* — The squared distance between the vectors.

note

This function is recommended over dist_to(other), for the reasons previously explained.

---

### `squared_dist_to_ignore_z(other)`

Calculates the Euclidean squared distance to another vector, ignoring the Z component of the vectors.

Parameters:

-   **`other`** (*vec3*) — The other vector.

Returns: *number* — The squared distance between the vectors, without taking into account the Z component of the vectors.

note

This function is recommended over dist_to_ignore_z(other), for the reasons previously explained.

---

### `dist_to_line_segment(line_segment_start, line_segment_end)`

Calculates the distance from self to a given line segment.

Parameters:

-   **`other`** (*vec3*) — The other vector.

Returns: *number* — The distance between self and a line segment.

---

### `squared_dist_to_line_segment(line_segment_start, line_segment_end)`

Calculates the distance from self to a given line segment.

Parameters:

-   **`other`** (*vec3*) — The other vector.

Returns: *number* — The squared distance between self and a line segment.

note

This function is recommended over dist_to_line_segment(), for the reasons previously explained.

---

### `squared_dist_to_ignore_z_line_segment(line_segment_start, line_segment_end)`

Calculates the distance from self to a given line segment, ignoring the Z component of the vector.

Parameters:

-   **`other`** (*vec3*) — The other vector.

Returns: *number* — The squared distance between self and a line segment, ignoring the Z component of the vector.

---

### `get_angle(origin)`

Calculates the angle between the vector and a target vector, relative to a specified origin point.

Parameters:

-   **`origin`** (*vec3*) — The origin point.

Returns: *number* — The angle in degrees.

---

### `intersects(p1, p2)`

Checks if the vector (as a point) intersects with a line segment defined by two points.

Parameters:

-   **`p1`** (*vec3*) — The first point of the line segment.
-   **`p2`** (*vec3*) — The second point of the line segment.

Returns: *boolean* — `true` if the point intersects the line segment; otherwise, `false`.

---

### `get_perp_left(origin)`

Returns the left perpendicular vector of the current vector relative to a specified origin point.

Parameters:

-   **`origin`** (*vec3*) — The origin point.

Returns: *vec3* — The left perpendicular vector.

---

### `get_perp_right(origin)`

Returns the right perpendicular vector of the current vector relative to a specified origin point.

Parameters:

-   **`origin`** (*vec3*) — The origin point.

Returns: *vec3* — The right perpendicular vector.

---

### Additional Functions

### `dot_product(other)`

An alternative method to calculate the dot product of two vectors.

Parameters:

-   **`other`** (*vec3*) — The other vector.

Returns: *number* — The dot product.

---

### `is_nan()`

Checks if the vector is not a number.

Returns: *boolean* — True if the vector_3 is not a number, false otherwise.

---

### `is_zero()`

Checks if the vector is zero.

Returns: *boolean* — True if the vector_3 is the vector(0,0,0), false otherwise.

tip

Saying that a vector is_zero is the same as saying that the said vector equals the vec3.new(0,0,0)

---

## Code Examples

```
---@type vec3local vec3 = require("common/geometry/vector_3")local v1 = vec3.new(1, 2, 3)local v2 = vec3.new(4, 5, 6)local v3 = v1:clone() -- Clone v1-- Adding vectorslocal v_add = v1 + v2core.log("Vector addition result: " .. v_add.x .. ", " .. v_add.y .. ", " .. v_add.z)-- Subtracting vectorslocal v_sub = v1 - v2core.log("Vector subtraction result: " .. v_sub.x .. ", " .. v_sub.y .. ", " .. v_sub.z)-- Normalizing a vectorlocal v_norm = v1:normalize()core.log("Normalized vector: " .. v_norm.x .. ", " .. v_norm.y .. ", " .. v_norm.z)-- Finding the distance between two vectors, ignoring zlocal dist_ignore_z = v1:dist_to_ignore_z(v2)core.log("Distance ignoring Z: " .. dist_ignore_z)-- Finding the squared length for efficiencylocal dist_squared = v1:length_squared()core.log("Squared length: " .. dist_squared)
```