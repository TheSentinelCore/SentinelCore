---
title: Helpers
layout: default
parent: Reference
nav_order: 3
---

# Helpers Reference
{: .no_toc }

Utility functions provided by `_G.SentinelNavClient.Helpers`. Pure functions with no side effects.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## Accessing Helpers

```lua
local Helpers = _G.SentinelNavClient.Helpers
```

---

## Distance & Geometry

### distance_3d

```lua
Helpers.distance_3d(a, b) -> number
```

3D Euclidean distance between two vec3 positions.

| Param | Type | Description |
|:------|:-----|:------------|
| `a` | vec3 | Position `{x, y, z}` |
| `b` | vec3 | Position `{x, y, z}` |

---

### distance_2d

```lua
Helpers.distance_2d(a, b) -> number
```

2D Euclidean distance (ignores Z) between two positions.

---

### point_to_segment_distance

```lua
Helpers.point_to_segment_distance(px, py, pz, ax, ay, az, bx, by, bz) -> distance, t
```

Compute the shortest 3D distance from a point to a line segment.

| Param | Type | Description |
|:------|:-----|:------------|
| `px, py, pz` | number | Point coordinates |
| `ax, ay, az` | number | Segment start coordinates |
| `bx, by, bz` | number | Segment end coordinates |

**Returns:**

| Return | Type | Description |
|:-------|:-----|:------------|
| `distance` | number | Shortest distance from point to segment |
| `t` | number | Parameter [0, 1] along the segment for the closest point |

Used internally by Movement's deviation monitoring to find the nearest path segment.

---

### is_within_radius

```lua
Helpers.is_within_radius(pos_a, pos_b, radius) -> boolean
```

Check if two positions are within a given radius (3D distance).

---

### angle_to

```lua
Helpers.angle_to(from, to) -> number
```

Compute the angle in radians from one position to another (2D, ignoring Z).

---

### normalize_angle

```lua
Helpers.normalize_angle(radians) -> number
```

Normalize an angle to the range [-&pi;, &pi;].

---

## Interpolation

### lerp

```lua
Helpers.lerp(a, b, t) -> number
```

Linear interpolation between two numbers.

| Param | Type | Description |
|:------|:-----|:------------|
| `a` | number | Start value |
| `b` | number | End value |
| `t` | number | Interpolation factor [0, 1] |

---

### lerp_vec3

```lua
Helpers.lerp_vec3(v1, v2, t) -> vec3
```

Linear interpolation between two vec3 positions. Returns `{x, y, z}`.

---

### clamp

```lua
Helpers.clamp(min, max, value) -> number
```

Clamp a value to the range [min, max].

{: .note }
Parameter order is `(min, max, value)`, not `(value, min, max)`.

---

## Randomization

### gaussian_random

```lua
Helpers.gaussian_random(min, max) -> number
```

Generate a random number with Gaussian (normal) distribution using the Box-Muller transform. Values are centered around the midpoint of [min, max] with standard deviation of `(max - min) / 6`.

---

### add_variance

```lua
Helpers.add_variance(base, percent) -> number
```

Add Gaussian random variance to a base value. Returns `base` &plusmn; `percent`% with Gaussian distribution.

| Param | Type | Description |
|:------|:-----|:------------|
| `base` | number | Base value |
| `percent` | number | Variance percentage (e.g., 10 for &plusmn;10%) |

---

## Table Utilities

### deep_copy

```lua
Helpers.deep_copy(original) -> table
```

Deep copy a table, handling circular references. Returns a new table with the same structure and values.

---

### table_contains

```lua
Helpers.table_contains(tbl, value) -> boolean
```

Check if a table contains a specific value (linear search).

---

### table_has_key

```lua
Helpers.table_has_key(tbl, key) -> boolean
```

Check if a table has a specific key.

---

### table_count

```lua
Helpers.table_count(tbl) -> number
```

Count the number of key-value pairs in a table (works for non-array tables).

---

### table_merge

```lua
Helpers.table_merge(base, overrides) -> table
```

Merge two tables. Values from `overrides` take precedence. Returns a new table.

---

### table_keys

```lua
Helpers.table_keys(tbl) -> table
```

Return an array of all keys in the table.

---

### table_values

```lua
Helpers.table_values(tbl) -> table
```

Return an array of all values in the table.

---

### shuffle

```lua
Helpers.shuffle(tbl) -> table
```

Randomly shuffle an array in place (Fisher-Yates). Returns the same table.

---

## Nested Table Access

### get_nested

```lua
Helpers.get_nested(tbl, path, default) -> any
```

Get a deeply nested value using dot-separated path notation.

| Param | Type | Description |
|:------|:-----|:------------|
| `tbl` | table | Source table |
| `path` | string | Dot-separated path (e.g., `"a.b.c"`) |
| `default` | any | Default value if path doesn't exist |

```lua
local val = Helpers.get_nested(config, "movement.stuck.max_attempts", 5)
```

---

### set_nested

```lua
Helpers.set_nested(tbl, path, value)
```

Set a deeply nested value using dot-separated path notation. Creates intermediate tables as needed.

```lua
Helpers.set_nested(config, "movement.stuck.max_attempts", 10)
```

---

## Formatting

### format_time

```lua
Helpers.format_time(seconds) -> string
```

Format seconds into a human-readable time string.

```lua
Helpers.format_time(3661)  -- "1h 1m 1s"
Helpers.format_time(65)    -- "1m 5s"
Helpers.format_time(30)    -- "30s"
```

---

### format_number

```lua
Helpers.format_number(num) -> string
```

Format a number with comma separators.

```lua
Helpers.format_number(12345)    -- "12,345"
Helpers.format_number(1234567)  -- "1,234,567"
```

---

## ID Generation

### generate_id

```lua
Helpers.generate_id() -> string
```

Generate a UUID v4 format string. Useful for unique identifiers.

```lua
local id = Helpers.generate_id()  -- e.g., "a1b2c3d4-e5f6-4a7b-8c9d-e0f1a2b3c4d5"
```
