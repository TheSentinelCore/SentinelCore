# ADR-0002: Extract Geometry module for nil-safe distance calculations

## Status

Accepted

## Context

The `distance_3d` function appears in multiple files:
- `modules/grind/threat_map.lua` — used in `get_heat()` to check proximity to threats
- `modules/grind/phases/safety.lua` — used to compute flee positions and check arrival

Both use the same pattern: nil-safety check returning `math.huge` to avoid crashes on stale userdata, then computing Euclidean distance. The safety.lua has the additional `away_from` logic duplicated.

## Decision

Extract `core/geometry.lua` with:
- `Geometry.distance(a, b)` — nil-safe 3D distance returning `math.huge` on invalid input
- `Geometry.away_from(center, position, distance)` — compute a flee point away from danger center

## Consequences

**Positive:**
- Single source of truth for distance calculations
- Nil-safety semantics documented in one place
- `safety.lua` can use `away_from()` instead of inline geometry
- `threat_map.lua` can use `Geometry.distance()`

**Negative:**
- Additional module to load (minimal overhead)

**Neutral:**
- No change to behavior