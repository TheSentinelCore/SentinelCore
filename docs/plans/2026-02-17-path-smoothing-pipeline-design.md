# Path-Smoothing Pipeline Upgrade Design

## Problem

The path-smoothing crate provided standalone algorithms (Chaikin, uniform Catmull-Rom, Bezier) that the server orchestrated manually: smooth, then project heights, then validate against walls. This split architecture had several issues:

1. **Uniform Catmull-Rom** produces cusps and self-intersections on unevenly-spaced waypoints
2. **No outlier rejection** — sharp glitch points passed through to smoothing
3. **Reprojection and validation** lived in server code, not reusable by other consumers
4. **No terrain awareness** — stairs, ramps, and spiral towers got the same interpolation density as flat ground

## Solution

A self-contained 4-stage `SmootherPipeline` inside the `path-smoothing` crate:

```
Input waypoints
    │
    ▼
┌─────────────────────────────────────┐
│ Stage 1: Chaikin Corner-Cutting     │
│  - Outlier rejection (angle < 90°)  │
│  - Angle-aware smoothing            │
│  - 2 iterations, ratio=0.75         │
└──────────────┬──────────────────────┘
               ▼
┌─────────────────────────────────────┐
│ Stage 2: Centripetal Catmull-Rom    │
│  - Barry-Goldman algorithm (α=0.5) │
│  - Adaptive density on stairs      │
│  - Mirror endpoint boundaries      │
└──────────────┬──────────────────────┘
               ▼
┌─────────────────────────────────────┐
│ Stage 3: Height Reprojection       │
│  - get_poly_height() per waypoint  │
│  - Two-tier fallback extents       │
│  - Graceful degradation            │
└──────────────┬──────────────────────┘
               ▼
┌─────────────────────────────────────┐
│ Stage 4: Raycast Validation        │
│  - Wall intersection detection     │
│  - Max deviation check (3 yards)   │
│  - Original-path fallback          │
└──────────────┬──────────────────────┘
               ▼
Output smoothed path
```

## Key Design Decisions

### Centripetal Catmull-Rom (α=0.5)

The Barry-Goldman recursive algorithm with α=0.5 guarantees:
- No cusps or self-intersections (proven by Yuksel et al., 2011)
- No overshoot at sharp turns
- Natural behavior with unevenly-spaced waypoints (common in navmesh pathfinding)

Knot spacing uses `t_i = t_{i-1} + |P_i - P_{i-1}|^0.5`, which adapts to point density automatically.

### Adaptive Density

`TerrainAnalysis` measures slope ratio (|Δz| / horizontal distance) per segment. Steep segments (ratio > 0.3) get 2x interpolation density, capped at 32 points. This handles:
- Stairs: many small Z changes over short horizontal distance
- Ramps: gradual but significant height change
- Spiral towers: detected via cumulative heading change

### Two-Tier Reprojection

Height reprojection uses tight search extents first ([2, 4, 2] yards) to avoid wrong-floor snapping in multi-level structures (Undercity, Karazhan). Falls back to 2x extents at tile boundaries.

### Pipeline Infallibility

Every stage degrades gracefully — failed `find_nearest_poly`, `get_poly_height`, or `raycast` calls keep the previous stage's output. The pipeline never returns an error.

## Module Structure

```
path-smoothing/src/
├── config.rs       SmootherConfig (15 fields, builder pattern)
├── pipeline.rs     SmootherPipeline (4-stage orchestrator)
├── chaikin.rs       Corner-cutting + outlier rejection
├── catmull_rom.rs  Centripetal Barry-Goldman
├── terrain.rs      Slope analysis, spiral detection
├── reprojection.rs Height snapping via get_poly_height
├── validation.rs   Raycast + deviation checking
├── metrics.rs      PathMetrics diagnostics
├── bezier.rs       Quadratic Bezier (standalone, unchanged)
└── lib.rs          Re-exports + deprecated compat shims
```

## Migration

Server's `pipeline.rs`, `routes/path.rs`, and `routes/tactical.rs` replaced 3 separate calls (smooth + project + validate) with:

```rust
let smoother = SmootherPipeline::with_default_config();
let smoothed = smoother.smooth(&waypoints, query, filter);
```

Old `SmoothingAlgorithm` and `SmoothingConfig` types are preserved as deprecated compat shims.
