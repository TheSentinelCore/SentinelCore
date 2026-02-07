# CLAUDE.md - NavBuddy

> **Purpose**: This file provides Claude with essential context for working on this codebase.

## Project Overview

NavBuddy is a high-performance Rust HTTP server that provides pathfinding and spatial intelligence services for World of Warcraft bots using TrinityCore navigation mesh (mmap) files. It wraps the Recast/Detour C++ library via FFI and exposes a GET-only HTTP API compatible with Lua's `core.http_get`.

## Quick Reference

```bash
# Build
cargo build --release

# Test
cargo test

# Run
cargo run --release -- --config config.toml

# Lint
cargo clippy

# Check FFI bindings
cargo build -p detour-sys

# Generate docs
cargo doc --open
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      HTTP Layer (Axum)                       │
│  18 GET endpoints across 5 route modules                    │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│               Application Layer                              │
│  AppState, Config, PathCache, Request Routing, JSON Serde   │
└─────────┬─────────────────┬──────────────────┬──────────────┘
          │                 │                  │
┌─────────▼────────┐ ┌─────▼──────────┐ ┌────▼───────────────┐
│  Intelligence    │ │   Tactical     │ │   Spatial          │
│  path-multi      │ │   flee         │ │   move, raycast    │
│  path-tsp        │ │   los cover    │ │   random, height   │
│  path-avoid      │ │   kite         │ │   explore          │
│  check, corridor │ │                │ │                    │
│  explore-route   │ │                │ │                    │
└─────────┬────────┘ └─────┬──────────┘ └────┬───────────────┘
          │                │                  │
┌─────────▼────────────────▼──────────────────▼───────────────┐
│              Pipeline (pipeline.rs)                           │
│  execute_pathfind → string_pull → smooth → project → validate│
│  PathCache (DashMap + 5-yard spatial quantization)           │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                  Navigation Layer                            │
│  tc-mmap (loader) ←→ detour (safe wrappers) ←→ path-smoothing│
│                        polygon-sampling                      │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                    FFI Layer (detour-sys)                    │
│  wrapper.h/cpp → bindgen → Raw Rust bindings                │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│              Recast/Detour C++ (git submodule)               │
└─────────────────────────────────────────────────────────────┘
```

## API Endpoints

| Endpoint | Handler | Purpose |
|----------|---------|---------|
| `GET /health` | `health.rs` | Server status, uptime, loaded maps, cache size |
| **Pathfinding** | | |
| `GET /api/v1/path` | `path.rs` | A→B path with smoothing, filtering, `allow_partial` + recovery |
| `GET /api/v1/path-random` | `path.rs` | A→B path with Gaussian random deviation for anti-detection |
| `GET /api/v1/path/validate-snap` | `path.rs` | Snap waypoints to nearest navmesh polygons |
| `GET /api/v1/path/validate-surface` | `path.rs` | Walk waypoints along navmesh surface |
| **Intelligence** | | |
| `GET /api/v1/path-multi` | `intelligence.rs` | Ordered multi-stop route with leg boundaries |
| `GET /api/v1/path-tsp` | `intelligence.rs` | TSP-optimized route (NN + 2-opt, weighted costs) |
| `GET /api/v1/path-avoid` | `intelligence.rs` | Path with avoidance zones (post-processing) |
| `GET /api/v1/path/check` | `intelligence.rs` | Validate remaining path via sequential raycasts |
| `GET /api/v1/path/corridor` | `intelligence.rs` | Path with perpendicular corridor widths |
| `GET /api/v1/explore-route` | `intelligence.rs` | Poisson sampling + TSP ordering + full paths |
| **Tactical** | | |
| `GET /api/v1/tactical/flee` | `tactical.rs` | Flee from threats (rotated angle candidates) |
| `GET /api/v1/tactical/los` | `tactical.rs` | LoS cover positions via random sampling + raycast |
| `GET /api/v1/tactical/kite` | `tactical.rs` | Arc waypoints at radius from target |
| **Spatial** | | |
| `GET /api/v1/move` | `spatial.rs` | Move along navmesh surface |
| `GET /api/v1/raycast` | `spatial.rs` | Raycast between two points |
| `GET /api/v1/random` | `spatial.rs` | Random navmesh point (global or in radius) |
| `GET /api/v1/height` | `spatial.rs` | Get navmesh height at position |
| `GET /api/v1/explore` | `spatial.rs` | Poisson disk sampling in polygon |

## Crate Structure

```
NavBuddy/
├── Cargo.toml                 # Workspace root
├── CLAUDE.md                  # This file
├── config.toml                # Default configuration
├── src/
│   ├── main.rs               # HTTP server entry point
│   ├── lib.rs                # Library root (for integration tests)
│   ├── config.rs             # Configuration loading (TOML)
│   ├── state.rs              # AppState: MmapManager, PathCache, Semaphore
│   ├── error.rs              # AppError → HTTP status code mapping
│   ├── pipeline.rs           # Shared pathfinding pipeline (execute_pathfind)
│   ├── cache.rs              # DashMap path cache with spatial quantization
│   ├── validation.rs         # Input validation (coords, map IDs, params)
│   └── routes/
│       ├── mod.rs            # Router: all 18 endpoints registered
│       ├── health.rs         # Health check
│       ├── path.rs           # Core pathfinding + validation + acquire_query! macro
│       ├── intelligence.rs   # Multi-stop, TSP, avoidance, corridor, check, explore-route
│       ├── tactical.rs       # Flee, LoS cover, kite
│       └── spatial.rs        # Move, raycast, random, height, explore
├── crates/
│   ├── detour-sys/           # Raw FFI bindings (Recast/Detour C++)
│   │   ├── build.rs          # cc + bindgen build script
│   │   ├── src/wrapper.h     # C-linkage declarations
│   │   ├── src/wrapper.cpp   # C++ to C bridge
│   │   └── recastnavigation/ # Git submodule
│   ├── detour/               # Safe Rust wrappers
│   │   └── src/
│   │       ├── mesh.rs       # NavMesh wrapper (Send+Sync)
│   │       ├── query.rs      # NavMeshQuery wrapper (!Send, !Sync)
│   │       ├── filter.rs     # QueryFilter (area costs)
│   │       ├── pool.rs       # Thread-safe QueryPool (Mutex<Vec>)
│   │       └── types.rs      # Vec3, PolyRef
│   ├── tc-mmap/              # TrinityCore .mmap/.mmtile loader
│   │   └── src/
│   │       ├── format.rs     # File format structs
│   │       ├── coords.rs     # Tile coordinate math
│   │       ├── loader.rs     # File I/O
│   │       └── manager.rs    # Lazy-loading MmapManager
│   ├── path-smoothing/       # Smoothing algorithms
│   │   └── src/
│   │       ├── chaikin.rs    # Chaikin corner-cutting
│   │       ├── catmull_rom.rs# Catmull-Rom splines
│   │       └── bezier.rs     # Bezier curves
│   └── polygon-sampling/     # Poisson disk sampling + TSP
│       └── src/lib.rs        # bridson_sampling, nearest_neighbor_tsp
└── tests/
    └── integration_tests.rs  # 31 integration tests against live navmesh
```

## Critical Implementation Details

### `acquire_query!` Macro

The core pattern for acquiring a navmesh query from the pool. Declares variables in the calling scope to avoid borrow-checker issues with RAII guards:

```rust
// Defined in path.rs, re-exported as pub(crate)
macro_rules! acquire_query {
    ($state:expr, $map_id:expr, $pool:ident, $query:ident) => {
        let _nb_mesh = $state.mmap_manager.get_or_load_mesh($map_id)...;
        let $pool = $state.mmap_manager.get_query_pool($map_id)...;
        let $query = $pool.acquire()...;  // PooledQuery RAII guard
    };
}

// Usage in any handler:
acquire_query!(state, params.map_id, pool, query);
let filter = pool.filter();  // Default filter
let result = execute_pathfind(&query, filter, start, end, &options)?;
```

**Important**: Do NOT destructure as `let (pool, query) = ...` — the macro declares `let` bindings directly. The `$query` borrows `$pool`, so both must live in the same scope.

### Shared Pipeline (`pipeline.rs`)

All pathfinding flows through `execute_pathfind`:
1. `find_nearest_poly` — snap start/end to navmesh
2. `find_path` — polygon corridor via A*
3. `find_straight_path` — string-pull to waypoints
4. String-pull optimization (skip redundant waypoints via raycast)
5. Smoothing (Chaikin, Catmull-Rom, or Bezier)
6. `project_waypoints_to_surface` — snap smoothed points back to navmesh
7. `validate_smoothed_path` — fallback to original if smoothed path diverges

Key exports: `execute_pathfind`, `PathOptions`, `PathResult`, `parse_stops`, `parse_waypoints`, `parse_avoidance_zones`, `parse_threats`, `apply_avoidance`, `compute_corridor_widths`, `create_custom_filter`, `create_smoothing_config`.

### PathCache (`cache.rs`)

- DashMap-backed with 5-yard spatial quantization (floor to grid cells)
- Key: `(map_id, quantized_start, quantized_end)`
- TTL: 60 seconds, max 1000 entries
- Checked before `execute_pathfind` in `/api/v1/path`, inserted on cache miss

### FFI Memory Ownership

```rust
// Transfer ownership to Detour with DT_TILE_FREE_DATA
pub fn add_tile(&mut self, tile_data: Box<[u8]>, last_ref: u32) -> Result<u32> {
    let ptr = Box::into_raw(tile_data) as *mut u8;  // Rust gives up ownership
    // On failure: reclaim with Box::from_raw
}
```

### Thread Safety Model

| Type | Send | Sync | Reason |
|------|------|------|--------|
| `NavMesh` | Yes | Yes | Read-only after initialization |
| `NavMeshQuery` | No | No | Internal mutable state (node pool) |
| `QueryFilter` | Yes | Yes | Immutable after construction |
| `QueryPool` | Yes | Yes | Mutex-protected Vec |
| `PathCache` | Yes | Yes | DashMap (concurrent HashMap) |

### TrinityCore File Formats

**.mmap file** (28 bytes) - NavMeshParams:
```
[0:12]  orig[3]: f32      - Origin position
[12:16] tile_width: f32   - Tile width (533.33333)
[16:20] tile_height: f32  - Tile height (533.33333)
[20:24] max_tiles: i32    - Maximum tiles
[24:28] max_polys: i32    - Maximum polys per tile
```

**.mmtile file** - Tile data:
```
[0:4]   magic: u32        - 0x4D4D4150 ("PMAP")
[4:8]   dt_version: u32   - Must be 7
[8:12]  mmap_version: u32 - 5-9 supported
[12:16] size: u32         - Tile data size
[16:20] uses_liquids: u32 - Boolean flag
[20:N]  tile_data: [u8]   - Raw Detour tile
```

### Coordinate Conversion

WoW uses an inverted coordinate system from Detour:

```rust
pub fn from_world_pos(map_id: u32, x: f32, y: f32) -> TileCoord {
    const TILE_SIZE: f32 = 533.33333;
    const MAP_OFFSET: f32 = 32.0 * TILE_SIZE;
    // Note the inversion: WoW Y → Detour X, WoW X → Detour Y
    let tile_x = ((MAP_OFFSET - y) / TILE_SIZE) as u32;
    let tile_y = ((MAP_OFFSET - x) / TILE_SIZE) as u32;
    TileCoord { map_id, x: tile_x.min(63), y: tile_y.min(63) }
}
```

### QueryFilter Area Types

Detour supports per-area-type costs (NOT per-polygon):

| Area | Type ID | Default Cost |
|------|---------|-------------|
| Ground | 0 | 1.0 |
| Road | 1 | 1.0 |
| Water | 2 | 10.0 |
| Lava | 3 | 100.0 |

Override via `filter_ground`, `filter_water`, `filter_lava` query params.

## Common Patterns

### HTTP Handler Pattern

```rust
pub async fn handler(
    State(state): State<AppState>,
    Query(params): Query<RequestType>,
) -> Result<Json<ResponseType>, AppError> {
    // 1. Validate inputs
    validate_map_id(params.map_id)?;
    validate_coordinate(params.start_x, params.start_y, params.start_z)?;
    validate_filter_params(params.filter_ground, params.filter_water, params.filter_lava)?;

    let start_time = std::time::Instant::now();

    // 2. Acquire concurrency permit
    let _permit = state.request_semaphore.acquire().await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    // 3. Acquire navmesh query (macro declares pool + query in scope)
    acquire_query!(state, params.map_id, pool, query);

    // 4. Resolve filter (custom or default)
    let custom_filter;
    let filter = if has_custom_filter(...) {
        custom_filter = create_custom_filter(...)?;
        &custom_filter
    } else {
        pool.filter()
    };

    // 5. Execute pathfinding
    let result = execute_pathfind(&query, filter, start_pos, end_pos, &options)?;

    // 6. Return JSON
    Ok(Json(ResponseType { ... }))
}
```

## Code Style

1. **Error Handling**: `thiserror` for types, `AppError` enum maps to HTTP status codes
2. **FFI Safety**: Document all `unsafe` blocks with `// SAFETY:` comments
3. **No Unwrap**: Use `?` operator, never `.unwrap()` in library code
4. **Logging**: `tracing` macros (`info!`, `debug!`, `error!`)
5. **Validation**: All user inputs validated in `validation.rs` before pathfinding
6. **GET-only**: All endpoints are GET (Lua client limitation), params via query string

## Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Short path (<100 yards) | <1ms | Same tile |
| Medium path (100-1000 yards) | <5ms | Adjacent tiles |
| Long path (>1000 yards) | <20ms | Multiple tiles |
| TSP (10 nodes, navmesh distances) | ~140ms | Called once per route plan |
| Raycast | <0.5ms | Single query |
| Path check (10 segments) | <5ms | Sequential raycasts |
| Cache hit | <0.1ms | DashMap lookup |

## Dependencies

### Required System Dependencies

- Rust 1.75+ (for async traits)
- Clang/LLVM (for bindgen)
- C++14 compiler (g++ or clang++)

### Key Crate Dependencies

```toml
tokio = { version = "1.35", features = ["full"] }
axum = "0.7"
serde = { version = "1.0", features = ["derive"] }
thiserror = "1.0"
tracing = "0.1"
dashmap = "5.5"
rand = "0.8"
tower-http = { version = "0.5", features = ["trace", "timeout"] }
```

## Test Data

Test mmap files in `test-data/mmaps/`. Required for integration tests:
- `0000.mmap` - Eastern Kingdoms header
- `000031*.mmtile` - Stormwind area tiles
- `0001.mmap` - Kalimdor header
- `000132*.mmtile` - Orgrimmar area tiles

## Troubleshooting

### "undefined reference to wrapper_*"
The C++ wrapper isn't being compiled. Check `build.rs` includes `wrapper.cpp`.

### "tile not loading"
Verify file path format: `{map_id:04}{y:02}{x:02}.mmtile` (note: Y before X).

### "path not found" for valid points
Check half_extents in `find_nearest_poly`. Default `[5.0, 5.0, 500.0]` — increase for rough terrain.

### Memory growing unboundedly
Ensure `DT_TILE_FREE_DATA` flag is set when adding tiles, or Detour won't free tile memory.

### acquire_query! borrow errors
The macro declares `let` bindings in the calling scope. Do NOT destructure: use `acquire_query!(state, map_id, pool, query);` — never `let (pool, query) = ...`.
