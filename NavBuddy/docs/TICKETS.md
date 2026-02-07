# Implementation Tickets

## AmeisenNav-RS Development Tasks

**Version:** 1.0.0  
**Last Updated:** 2026-02-02

---

## Overview

This document contains the detailed implementation tickets for the 6-week AmeisenNav-RS development roadmap. Tickets are organized by phase and include acceptance criteria, dependencies, and estimated complexity.

---

## Phase 1: FFI Foundation (Week 1)

### TICKET-001: Initialize Workspace Structure

**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** None

**Description:**  
Set up the Rust workspace with the initial crate structure.

**Tasks:**
- [ ] Create root `Cargo.toml` with workspace members
- [ ] Create `crates/detour-sys/Cargo.toml`
- [ ] Create `crates/detour/Cargo.toml`
- [ ] Create `crates/tc-mmap/Cargo.toml`
- [ ] Create `crates/path-smoothing/Cargo.toml`
- [ ] Create `src/main.rs` stub for HTTP server
- [ ] Add `.gitignore` with Rust patterns

**Acceptance Criteria:**
- `cargo check` succeeds at workspace root
- All crates compile (empty lib.rs files)
- Workspace structure matches ARCHITECTURE.md

---

### TICKET-002: Add Recast/Detour as Git Submodule

**Priority:** P0  
**Estimate:** 1 hour  
**Dependencies:** TICKET-001

**Description:**  
Add the recastnavigation library as a git submodule.

**Tasks:**
- [ ] `git submodule add https://github.com/recastnavigation/recastnavigation.git crates/detour-sys/recastnavigation`
- [ ] Pin to stable release tag (e.g., v1.6.0)
- [ ] Verify Detour source files are present
- [ ] Add submodule update instructions to README

**Acceptance Criteria:**
- `crates/detour-sys/recastnavigation/Detour/` contains source files
- Submodule is tracked in `.gitmodules`

---

### TICKET-003: Create C Wrapper Header (wrapper.h)

**Priority:** P0  
**Estimate:** 4 hours  
**Dependencies:** TICKET-002

**Description:**  
Create C-linkage wrapper declarations for Detour C++ classes that bindgen can process.

**Tasks:**
- [ ] Define opaque types: `dtNavMesh`, `dtNavMeshQuery`, `dtQueryFilter`
- [ ] Declare allocation functions:
  - `wrapper_dtAllocNavMesh()`
  - `wrapper_dtAllocNavMeshQuery()`
  - `wrapper_dtAllocQueryFilter()`
- [ ] Declare deallocation functions:
  - `wrapper_dtFreeNavMesh()`
  - `wrapper_dtFreeNavMeshQuery()`
  - `wrapper_dtFreeQueryFilter()`
- [ ] Declare NavMesh functions:
  - `wrapper_dtNavMesh_init()`
  - `wrapper_dtNavMesh_addTile()`
  - `wrapper_dtNavMesh_removeTile()`
  - `wrapper_dtNavMesh_getTileAt()`
- [ ] Declare NavMeshQuery functions:
  - `wrapper_dtNavMeshQuery_init()`
  - `wrapper_dtNavMeshQuery_findNearestPoly()`
  - `wrapper_dtNavMeshQuery_findPath()`
  - `wrapper_dtNavMeshQuery_findStraightPath()`
  - `wrapper_dtNavMeshQuery_moveAlongSurface()`
  - `wrapper_dtNavMeshQuery_raycast()`
  - `wrapper_dtNavMeshQuery_findRandomPoint()`
  - `wrapper_dtNavMeshQuery_findRandomPointAroundCircle()`
  - `wrapper_dtNavMeshQuery_getPolyHeight()`
- [ ] Declare QueryFilter functions:
  - `wrapper_dtQueryFilter_setIncludeFlags()`
  - `wrapper_dtQueryFilter_setExcludeFlags()`
  - `wrapper_dtQueryFilter_setAreaCost()`

**Acceptance Criteria:**
- All function signatures are `extern "C"`
- Header compiles with C++ compiler
- All required Detour functionality is exposed

---

### TICKET-004: Implement C Wrapper (wrapper.cpp)

**Priority:** P0  
**Estimate:** 6 hours  
**Dependencies:** TICKET-003

**Description:**  
Implement the C wrapper functions that call Detour C++ methods.

**Tasks:**
- [ ] Include Detour headers
- [ ] Implement allocation wrappers using `dtAllocNavMesh()`, etc.
- [ ] Implement NavMesh wrappers with proper casting
- [ ] Implement NavMeshQuery wrappers
- [ ] Implement QueryFilter wrappers
- [ ] Add null pointer checks
- [ ] Return appropriate dtStatus codes

**Acceptance Criteria:**
- All wrapper functions compile
- No memory leaks in allocation/deallocation pairs
- Status codes are properly propagated

---

### TICKET-005: Configure build.rs for detour-sys

**Priority:** P0  
**Estimate:** 4 hours  
**Dependencies:** TICKET-004

**Description:**  
Create build script that compiles Detour sources and generates Rust bindings.

**Tasks:**
- [ ] Add build dependencies: `cc`, `bindgen`
- [ ] Configure `cc::Build` for Detour source files:
  - DetourNavMesh.cpp
  - DetourNavMeshQuery.cpp
  - DetourNavMeshBuilder.cpp
  - DetourNode.cpp
  - DetourCommon.cpp
  - DetourAlloc.cpp
- [ ] Configure `cc::Build` for wrapper.cpp
- [ ] Set include paths for Detour headers
- [ ] Enable C++14 standard
- [ ] Configure `bindgen::Builder`:
  - Input: wrapper.h
  - Allowlist: `wrapper_*` functions
  - Opaque types: `dtNavMesh`, `dtNavMeshQuery`, `dtQueryFilter`
  - Generate `bindings.rs` in `$OUT_DIR`
- [ ] Link libraries in correct order

**Acceptance Criteria:**
- `cargo build -p detour-sys` succeeds
- Generated `bindings.rs` contains expected function declarations
- No linker errors

---

### TICKET-006: Create detour-sys lib.rs

**Priority:** P0  
**Estimate:** 1 hour  
**Dependencies:** TICKET-005

**Description:**  
Create the lib.rs file that re-exports generated bindings.

**Tasks:**
- [ ] Include generated bindings with `include!`
- [ ] Re-export all `wrapper_*` functions
- [ ] Add module-level documentation
- [ ] Mark entire module as `unsafe`

**Acceptance Criteria:**
- `cargo doc -p detour-sys` generates documentation
- All wrapper functions are visible to dependent crates

---

## Phase 2: Safe Wrappers (Week 2)

### TICKET-007: Implement Vec3 Type

**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** TICKET-006

**Description:**  
Create the core geometry type for 3D positions.

**Tasks:**
- [ ] Define `Vec3` struct with `x`, `y`, `z` fields
- [ ] Implement `new()`, `from_array()`, `as_ptr()`, `as_mut_ptr()`
- [ ] Implement `distance()`, `distance_2d()`, `length()`, `normalize()`
- [ ] Implement `Add`, `Sub`, `Mul<f32>` traits
- [ ] Derive `Debug`, `Clone`, `Copy`, `PartialEq`
- [ ] Add unit tests

**Acceptance Criteria:**
- All methods work correctly
- Tests pass
- `#[repr(C)]` for FFI compatibility

---

### TICKET-008: Implement DetourStatus Type

**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** TICKET-006

**Description:**  
Create a type-safe wrapper for Detour status codes.

**Tasks:**
- [ ] Define `DetourStatus` newtype wrapping `u32`
- [ ] Define status flag constants: `SUCCESS`, `FAILURE`, `PARTIAL_RESULT`, etc.
- [ ] Implement `succeeded()`, `failed()`, `is_partial()` methods
- [ ] Implement conversion to `Result<(), DetourError>`
- [ ] Add unit tests with known status values

**Acceptance Criteria:**
- Status interpretation matches Detour behavior
- All flag combinations handled correctly

---

### TICKET-009: Define Error Types

**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** TICKET-008

**Description:**  
Create the error types for the detour crate.

**Tasks:**
- [ ] Define `DetourError` enum using `thiserror`
- [ ] Add variants:
  - `AllocationFailed`
  - `InitFailed`
  - `StartNotFound`
  - `EndNotFound`
  - `PathNotFound`
  - `StraightPathFailed`
  - `StatusError(u32)`
- [ ] Implement `From<DetourStatus>` for `DetourError`
- [ ] Add error messages

**Acceptance Criteria:**
- All error variants have descriptive messages
- Errors implement `std::error::Error`

---

### TICKET-010: Implement NavMesh Wrapper

**Priority:** P0  
**Estimate:** 6 hours  
**Dependencies:** TICKET-007, TICKET-008, TICKET-009

**Description:**  
Create the safe wrapper for dtNavMesh.

**Tasks:**
- [ ] Define `NavMesh` struct holding `*mut dtNavMesh`
- [ ] Implement `new()` calling `wrapper_dtAllocNavMesh()`
- [ ] Implement `init()` calling `wrapper_dtNavMesh_init()`
- [ ] Implement `add_tile()` with memory ownership handling:
  - Accept `Box<[u8]>` for owned data
  - Use `Box::into_raw()` to transfer ownership
  - Pass `DT_TILE_FREE_DATA` flag
  - Reclaim memory on failure with `Box::from_raw()`
- [ ] Implement `remove_tile()`
- [ ] Implement `get_tile_at()`
- [ ] Implement `Drop` calling `wrapper_dtFreeNavMesh()`
- [ ] Implement `Send + Sync` (unsafe, justified by read-only access)
- [ ] Add integration tests

**Acceptance Criteria:**
- Memory is properly managed (no leaks)
- Thread safety is documented and justified
- All operations return `Result`

---

### TICKET-011: Implement NavMeshQuery Wrapper

**Priority:** P0  
**Estimate:** 8 hours  
**Dependencies:** TICKET-010

**Description:**  
Create the safe wrapper for dtNavMeshQuery.

**Tasks:**
- [ ] Define `NavMeshQuery` struct holding:
  - `*mut dtNavMeshQuery`
  - `Arc<NavMesh>` (to prevent use-after-free)
- [ ] Implement `new()` with max_nodes parameter
- [ ] Implement `init()` linking to NavMesh
- [ ] Implement `find_nearest_poly()`:
  - Accept center position and half extents
  - Return `(PolyRef, Vec3)` tuple
- [ ] Implement `find_path()`:
  - Accept start/end refs and positions
  - Accept max path length
  - Return `Vec<PolyRef>` and partial flag
- [ ] Implement `find_straight_path()`:
  - Accept poly path
  - Return `Vec<Vec3>` waypoints
- [ ] Implement `move_along_surface()`
- [ ] Implement `raycast()`
- [ ] Implement `find_random_point()`
- [ ] Implement `find_random_point_around_circle()`
- [ ] Implement `get_poly_height()`
- [ ] Implement `Drop` calling `wrapper_dtFreeNavMeshQuery()`
- [ ] Do NOT implement `Send` or `Sync` (internal mutable state)

**Acceptance Criteria:**
- All pathfinding operations work correctly
- NavMesh lifetime is properly managed
- Thread safety is correctly restricted

---

### TICKET-012: Implement QueryFilter Wrapper

**Priority:** P1  
**Estimate:** 2 hours  
**Dependencies:** TICKET-006

**Description:**  
Create the safe wrapper for dtQueryFilter.

**Tasks:**
- [ ] Define `QueryFilter` struct holding `*mut dtQueryFilter`
- [ ] Implement `new()` with default settings
- [ ] Implement `set_include_flags()`
- [ ] Implement `set_exclude_flags()`
- [ ] Implement `set_area_cost()`
- [ ] Implement `Default` trait with WoW-appropriate defaults
- [ ] Implement `Drop`
- [ ] Implement `Send + Sync` (immutable after creation)

**Acceptance Criteria:**
- Filter affects pathfinding results correctly
- Default configuration works for WoW maps

---

### TICKET-013: Implement Query Pool

**Priority:** P0  
**Estimate:** 4 hours  
**Dependencies:** TICKET-011

**Description:**  
Create the thread-safe query pool for sharing NavMeshQuery instances.

**Tasks:**
- [ ] Define `QueryPool` struct with:
  - `Arc<NavMesh>`
  - `Mutex<Vec<NavMeshQuery>>`
  - `max_queries` configuration
- [ ] Implement `new()` that pre-allocates queries
- [ ] Implement `acquire()` returning `PooledQuery`:
  - Try to pop from pool
  - Create new if pool empty and under limit
  - Block/error if at limit
- [ ] Define `PooledQuery` RAII guard:
  - Implement `Deref` to `NavMeshQuery`
  - Implement `Drop` to return query to pool
- [ ] Ensure `QueryPool` is `Send + Sync`
- [ ] Add tests for concurrent access

**Acceptance Criteria:**
- Pool correctly manages query lifecycle
- Concurrent access is safe
- Queries are reused (no excessive allocation)

---

## Phase 3: TrinityCore Loader (Week 3)

### TICKET-014: Define MMAP File Format Structs

**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** None

**Description:**  
Create structures matching TrinityCore mmap file formats.

**Tasks:**
- [ ] Define `MmapFile` struct (28 bytes NavMeshParams)
- [ ] Define `MmapTileHeader` struct:
  - `mmap_magic: u32` (0x4D4D4150)
  - `dt_version: u32` (7)
  - `mmap_version: u32` (5-9)
  - `size: u32`
  - `uses_liquids: u8`
- [ ] Define `MmapTileFile` struct
- [ ] Use `#[repr(C, packed)]` for correct memory layout
- [ ] Implement `from_bytes()` with validation
- [ ] Define constants: MAGIC, DT_VERSION, etc.
- [ ] Add unit tests with real file samples

**Acceptance Criteria:**
- Structs match TrinityCore binary format exactly
- Validation catches corrupt files
- Tested against real mmap files

---

### TICKET-015: Implement TileCoord Utility

**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** TICKET-014

**Description:**  
Create utilities for working with tile coordinates.

**Tasks:**
- [ ] Define `TileCoord` struct with `map_id`, `x`, `y`
- [ ] Implement `from_world_pos()` calculating tile from coordinates
- [ ] Implement `bounds()` returning world-space tile bounds
- [ ] Implement `filename()` generating mmtile filename
- [ ] Derive `Hash`, `Eq` for use as map keys
- [ ] Add constants: TILE_SIZE, GRID_SIZE
- [ ] Unit tests for coordinate conversions

**Acceptance Criteria:**
- World position to tile conversion matches TrinityCore
- Filename generation matches TrinityCore pattern

---

### TICKET-016: Implement MmapLoader

**Priority:** P0  
**Estimate:** 6 hours  
**Dependencies:** TICKET-014, TICKET-015

**Description:**  
Create the file I/O component for loading mmap files.

**Tasks:**
- [ ] Define `MmapLoader` struct with:
  - `mmap_path: PathBuf`
  - `params_cache: Mutex<HashMap<u32, NavMeshParams>>`
- [ ] Implement `new()` validating path exists
- [ ] Implement `load_map_params()`:
  - Read `{mapId:04}.mmap` file
  - Parse and cache NavMeshParams
  - Return cached on subsequent calls
- [ ] Implement `load_tile()`:
  - Read `{mapId:04}{x:02}{y:02}.mmtile` file
  - Validate header (magic, version)
  - Return raw tile data as `Vec<u8>`
- [ ] Implement `tile_exists()` checking file presence
- [ ] Implement `list_available_tiles()` for a map
- [ ] Define `MmapError` enum with I/O and validation variants
- [ ] Use `std::fs::read()` for file I/O

**Acceptance Criteria:**
- Successfully loads real TrinityCore mmap files
- Proper error handling for missing/corrupt files
- Caching reduces repeated disk I/O

---

### TICKET-017: Implement MmapManager

**Priority:** P0  
**Estimate:** 6 hours  
**Dependencies:** TICKET-016, TICKET-010, TICKET-013

**Description:**  
Create the high-level manager coordinating map loading.

**Tasks:**
- [ ] Define `MmapManager` struct with:
  - `Arc<MmapLoader>`
  - `DashMap<u32, Arc<NavMesh>>`
  - `DashMap<u32, QueryPool>`
  - `DashMap<(u32, i32, i32), bool>` (loaded tiles tracking)
- [ ] Implement `new()` with config
- [ ] Implement `ensure_map_loaded()`:
  - Load params if not cached
  - Create NavMesh and QueryPool
  - Store in DashMaps
- [ ] Implement `ensure_tiles_loaded()`:
  - Calculate required tiles for start/end positions
  - Load missing tiles via MmapLoader
  - Add to NavMesh
  - Track in loaded tiles set
- [ ] Implement `get_navmesh()` returning `Arc<NavMesh>`
- [ ] Implement `acquire_query()` from pool
- [ ] Add preload functionality for startup

**Acceptance Criteria:**
- Lazy loading works correctly
- Concurrent access is safe
- Tiles are loaded on-demand as needed

---

## Phase 4: HTTP Service (Week 4)

### TICKET-018: Define Configuration Types

**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** None

**Description:**  
Create configuration structures for the HTTP server.

**Tasks:**
- [ ] Define `Config` struct with nested configs
- [ ] Define `ServerConfig`: host, port, max_concurrent_requests
- [ ] Define `NavmeshConfig`: mmap_path, preload_maps, lazy_loading
- [ ] Define `PathfindingConfig`: default_smoothing, max_path_length, query_pool_size
- [ ] Implement config loading from TOML file
- [ ] Implement environment variable overrides
- [ ] Create default config file example

**Acceptance Criteria:**
- Config loads from file
- Environment variables override file settings
- Defaults are sensible for WoW usage

---

### TICKET-019: Define API Request/Response Types

**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** TICKET-007

**Description:**  
Create the DTOs for HTTP API endpoints.

**Tasks:**
- [ ] Define request params with `serde::Deserialize`:
  - `PathParams`
  - `MoveParams`
  - `RaycastParams`
  - `RandomParams`
  - `RandomCircleParams`
  - `HeightParams`
- [ ] Define response types with `serde::Serialize`:
  - `PathResponse`
  - `MoveResponse`
  - `RaycastResponse`
  - `RandomResponse`
  - `RandomCircleResponse`
  - `HeightResponse`
  - `HealthResponse`
- [ ] Add validation for numeric bounds
- [ ] Include `compute_time_ms` in all responses

**Acceptance Criteria:**
- All types serialize/deserialize correctly
- Validation rejects out-of-bounds values
- JSON format matches API_DESIGN.md

---

### TICKET-020: Implement Application State

**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** TICKET-017, TICKET-018

**Description:**  
Create the shared state for the HTTP server.

**Tasks:**
- [ ] Define `AppState` struct with:
  - `Arc<MmapManager>`
  - `Arc<Config>`
  - `Arc<Semaphore>` (concurrency limit)
  - `AtomicU64` (uptime counter)
- [ ] Implement `new()` initializing all components
- [ ] Implement startup preloading from config
- [ ] Use `Arc<AppState>` with Axum extractors

**Acceptance Criteria:**
- State is properly shared across handlers
- Preloading completes before serving requests
- Semaphore limits concurrent pathfinding

---

### TICKET-021: Implement /api/v1/path Endpoint

**Priority:** P0  
**Estimate:** 6 hours  
**Dependencies:** TICKET-019, TICKET-020

**Description:**  
Create the main pathfinding endpoint.

**Tasks:**
- [ ] Create route handler `find_path()`
- [ ] Extract `Query<PathParams>` from request
- [ ] Validate parameters (coords in bounds, map_id positive)
- [ ] Acquire semaphore permit
- [ ] Call `ensure_tiles_loaded()` for start/end positions
- [ ] Acquire query from pool
- [ ] Use `spawn_blocking` for pathfinding:
  - `find_nearest_poly()` for start
  - `find_nearest_poly()` for end
  - `find_path()` for poly path
  - `find_straight_path()` for waypoints
- [ ] Apply smoothing if requested
- [ ] Calculate total distance
- [ ] Build and return `PathResponse`
- [ ] Handle all error cases

**Acceptance Criteria:**
- Returns valid paths for navigable positions
- Returns partial paths when full path unavailable
- Proper error responses for invalid inputs
- Latency within performance targets

---

### TICKET-022: Implement /api/v1/move Endpoint

**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** TICKET-020

**Description:**  
Create the constrained movement endpoint.

**Tasks:**
- [ ] Create route handler `move_along_surface()`
- [ ] Extract and validate `Query<MoveParams>`
- [ ] Acquire semaphore and query
- [ ] Call `move_along_surface()` in spawn_blocking
- [ ] Return `MoveResponse` with result position

**Acceptance Criteria:**
- Movement is constrained to navmesh surface
- Handles obstacles correctly

---

### TICKET-023: Implement /api/v1/raycast Endpoint

**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** TICKET-020

**Description:**  
Create the line-of-sight raycast endpoint.

**Tasks:**
- [ ] Create route handler `raycast()`
- [ ] Extract and validate `Query<RaycastParams>`
- [ ] Acquire semaphore and query
- [ ] Call `raycast()` in spawn_blocking
- [ ] Return `RaycastResponse` with hit info

**Acceptance Criteria:**
- Correctly detects navmesh boundaries
- Returns hit position and normal when applicable

---

### TICKET-024: Implement Random Point Endpoints

**Priority:** P1  
**Estimate:** 3 hours  
**Dependencies:** TICKET-020

**Description:**  
Create the random point generation endpoints.

**Tasks:**
- [ ] Implement `/api/v1/random` handler
- [ ] Implement `/api/v1/random-circle` handler
- [ ] Both use `spawn_blocking` for FFI calls
- [ ] Return appropriate response types

**Acceptance Criteria:**
- Generated points are on valid navmesh
- Circle radius is respected

---

### TICKET-025: Implement /api/v1/height Endpoint

**Priority:** P1  
**Estimate:** 2 hours  
**Dependencies:** TICKET-020

**Description:**  
Create the height query endpoint.

**Tasks:**
- [ ] Create route handler `get_height()`
- [ ] Extract and validate `Query<HeightParams>`
- [ ] Call `get_poly_height()` in spawn_blocking
- [ ] Return `HeightResponse`

**Acceptance Criteria:**
- Returns accurate navmesh height at position
- Handles positions not on navmesh

---

### TICKET-026: Implement /health Endpoint

**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** TICKET-020

**Description:**  
Create the health check endpoint.

**Tasks:**
- [ ] Create route handler `health_check()`
- [ ] Gather statistics:
  - Uptime seconds
  - Loaded maps list
  - Total tiles loaded
  - Memory usage (if available)
- [ ] Return `HealthResponse`

**Acceptance Criteria:**
- Returns accurate server state
- Suitable for load balancer health checks

---

### TICKET-027: Implement API Error Handling

**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** TICKET-021

**Description:**  
Create unified error handling for all endpoints.

**Tasks:**
- [ ] Define `ApiError` enum with variants:
  - `InvalidParams(String)`
  - `MapNotFound(u32)`
  - `PathNotFound`
  - `ServiceOverloaded`
  - `InternalError(String)`
- [ ] Implement `IntoResponse` for `ApiError`
- [ ] Map errors to HTTP status codes:
  - 400 for InvalidParams
  - 404 for MapNotFound, PathNotFound
  - 500 for InternalError
  - 503 for ServiceOverloaded
- [ ] Return JSON error responses
- [ ] Add error logging

**Acceptance Criteria:**
- All errors return proper HTTP status
- Error messages are helpful but not exposing internals

---

### TICKET-028: Set Up Axum Server

**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** TICKET-021 through TICKET-027

**Description:**  
Create the main server entry point with routing.

**Tasks:**
- [ ] Create `main.rs` with tokio runtime
- [ ] Load configuration
- [ ] Initialize AppState with preloading
- [ ] Set up Router with all routes
- [ ] Add request logging middleware
- [ ] Add timeout middleware (30s)
- [ ] Bind to configured host:port
- [ ] Handle graceful shutdown (SIGTERM)

**Acceptance Criteria:**
- Server starts and accepts requests
- All endpoints are reachable
- Graceful shutdown completes in-flight requests

---

## Phase 5: Path Smoothing (Week 5)

### TICKET-029: Implement Chaikin Smoothing

**Priority:** P1  
**Estimate:** 3 hours  
**Dependencies:** TICKET-007

**Description:**  
Implement Chaikin's corner-cutting algorithm.

**Tasks:**
- [ ] Create `crates/path-smoothing/src/chaikin.rs`
- [ ] Implement `chaikin_smooth()`:
  - Accept `&[Vec3]` and iterations parameter
  - For each iteration, replace each segment with two new points:
    - Q = 3/4 * P0 + 1/4 * P1
    - R = 1/4 * P0 + 3/4 * P1
  - Preserve first and last points
- [ ] Default to 2-3 iterations
- [ ] Add unit tests with known inputs

**Acceptance Criteria:**
- Produces smoother paths
- Start and end points are preserved
- No sharp corners remain after sufficient iterations

---

### TICKET-030: Implement Catmull-Rom Smoothing

**Priority:** P1  
**Estimate:** 4 hours  
**Dependencies:** TICKET-007

**Description:**  
Implement Catmull-Rom spline interpolation.

**Tasks:**
- [ ] Create `crates/path-smoothing/src/catmull_rom.rs`
- [ ] Implement `catmull_rom_smooth()`:
  - Accept `&[Vec3]` and samples_per_segment
  - Use Catmull-Rom spline formula
  - Interpolate between consecutive control points
  - Handle endpoints by duplicating first/last points
- [ ] Default to 10 samples per segment
- [ ] Add unit tests

**Acceptance Criteria:**
- Produces smooth curves through all original points
- Continuous first derivative (C1 continuity)
- Configurable density

---

### TICKET-031: Implement Bezier Smoothing

**Priority:** P2  
**Estimate:** 4 hours  
**Dependencies:** TICKET-007

**Description:**  
Implement cubic Bezier curve smoothing.

**Tasks:**
- [ ] Create `crates/path-smoothing/src/bezier.rs`
- [ ] Implement `bezier_smooth()`:
  - Generate control points from path
  - Use cubic Bezier formula
  - Sample curve at regular intervals
- [ ] Add tension parameter for control point generation
- [ ] Add unit tests

**Acceptance Criteria:**
- Produces smooth approximation of path
- Configurable smoothness via tension
- Works with paths of any length

---

### TICKET-032: Integrate Smoothing with HTTP Endpoints

**Priority:** P1  
**Estimate:** 2 hours  
**Dependencies:** TICKET-029, TICKET-030, TICKET-031, TICKET-021

**Description:**  
Add smoothing option to path endpoint.

**Tasks:**
- [ ] Add `smoothing` query parameter to PathParams
- [ ] Parse smoothing algorithm: `none`, `chaikin`, `catmull_rom`, `bezier`
- [ ] Apply selected smoothing after pathfinding
- [ ] Update path response with smoothed waypoints
- [ ] Update distance calculation for smoothed path

**Acceptance Criteria:**
- Smoothing parameter works correctly
- Default is `none` or configurable
- Smoothed paths render naturally in game

---

## Phase 6: Production Hardening (Week 6)

### TICKET-033: Add Comprehensive Logging

**Priority:** P1  
**Estimate:** 3 hours  
**Dependencies:** TICKET-028

**Description:**  
Add structured logging throughout the application.

**Tasks:**
- [ ] Add `tracing` and `tracing-subscriber` dependencies
- [ ] Initialize subscriber in main()
- [ ] Add request logging with:
  - Method, path, params
  - Response status and timing
  - Error details
- [ ] Add pathfinding operation logging:
  - Map ID, tile loads
  - Path length, smoothing applied
  - Timing breakdown
- [ ] Configure log levels via environment

**Acceptance Criteria:**
- All requests are logged
- Errors include stack context
- Log format is structured (JSON)

---

### TICKET-034: Add Performance Metrics

**Priority:** P1  
**Estimate:** 4 hours  
**Dependencies:** TICKET-028

**Description:**  
Add metrics collection for monitoring.

**Tasks:**
- [ ] Add `metrics` and `metrics-exporter-prometheus` dependencies
- [ ] Define metrics:
  - `pathfinding_requests_total` (counter)
  - `pathfinding_duration_seconds` (histogram)
  - `tiles_loaded_total` (gauge per map)
  - `query_pool_active` (gauge per map)
  - `concurrent_requests` (gauge)
- [ ] Add `/metrics` endpoint for Prometheus
- [ ] Record metrics in handlers

**Acceptance Criteria:**
- Prometheus can scrape metrics
- Latency histograms are accurate
- Resource usage is visible

---

### TICKET-035: Add Input Validation Hardening

**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** TICKET-019

**Description:**  
Strengthen input validation against malicious inputs.

**Tasks:**
- [ ] Validate all coordinates are finite (not NaN/Inf)
- [ ] Validate coordinates within WoW bounds (±50000)
- [ ] Validate map_id is reasonable (< 10000)
- [ ] Validate radius is positive and bounded
- [ ] Rate limit requests per client (if needed)
- [ ] Add request size limits

**Acceptance Criteria:**
- Invalid inputs rejected with 400 status
- No panics on malicious input
- Clear error messages

---

### TICKET-036: Create Integration Tests

**Priority:** P0  
**Estimate:** 6 hours  
**Dependencies:** TICKET-028

**Description:**  
Create comprehensive integration tests.

**Tasks:**
- [ ] Create `tests/integration.rs`
- [ ] Add test fixtures with sample mmap files
- [ ] Test pathfinding scenarios:
  - Short path (same tile)
  - Medium path (adjacent tiles)
  - Long path (multiple tiles)
  - Path not found (unreachable)
  - Partial path (best effort)
- [ ] Test edge cases:
  - Position not on navmesh
  - Invalid map ID
  - Concurrent requests
- [ ] Test smoothing algorithms
- [ ] Test HTTP API responses

**Acceptance Criteria:**
- All tests pass with real mmap files
- Edge cases are covered
- Tests run in CI

---

### TICKET-037: Create Benchmarks

**Priority:** P1  
**Estimate:** 4 hours  
**Dependencies:** TICKET-036

**Description:**  
Create performance benchmarks.

**Tasks:**
- [ ] Add `criterion` dependency
- [ ] Create `benches/pathfinding.rs`
- [ ] Benchmark scenarios:
  - Short path (<100 yards)
  - Medium path (100-1000 yards)
  - Long path (>1000 yards)
  - Raycast operation
  - Random point generation
- [ ] Benchmark with/without smoothing
- [ ] Record baseline metrics

**Acceptance Criteria:**
- Benchmarks are reproducible
- Meet performance targets from PRD:
  - Short: <1ms
  - Medium: <5ms
  - Long: <20ms

---

### TICKET-038: Create Dockerfile

**Priority:** P1  
**Estimate:** 3 hours  
**Dependencies:** TICKET-028

**Description:**  
Create Docker configuration for deployment.

**Tasks:**
- [ ] Create multi-stage Dockerfile:
  - Build stage with Rust toolchain
  - Runtime stage with minimal base
- [ ] Install build dependencies (clang, etc.)
- [ ] Copy and build application
- [ ] Create minimal runtime image
- [ ] Configure entrypoint and environment
- [ ] Document volume mounts for mmap files
- [ ] Create `docker-compose.yml` example

**Acceptance Criteria:**
- Docker build succeeds
- Image size is reasonable (<500MB)
- Container runs correctly with mounted mmaps

---

### TICKET-039: Write Documentation

**Priority:** P1  
**Estimate:** 4 hours  
**Dependencies:** All

**Description:**  
Create user-facing documentation.

**Tasks:**
- [ ] Update README.md with:
  - Project description
  - Quick start guide
  - Configuration reference
  - API overview
- [ ] Create CHANGELOG.md
- [ ] Document Lua client usage
- [ ] Add troubleshooting guide
- [ ] Generate and publish rustdoc

**Acceptance Criteria:**
- New users can get started from README
- All configuration options documented
- API is clearly documented

---

### TICKET-040: Final Testing and Release

**Priority:** P0  
**Estimate:** 4 hours  
**Dependencies:** All

**Description:**  
Perform final testing and prepare release.

**Tasks:**
- [ ] Run full test suite
- [ ] Performance testing under load
- [ ] Memory leak testing with valgrind
- [ ] Test with real Sylvannas bot
- [ ] Create release tag
- [ ] Build release artifacts
- [ ] Update gemini.md with final details

**Acceptance Criteria:**
- All tests pass
- Performance meets requirements
- No memory leaks detected
- Works end-to-end with Sylvannas bot

---

## Summary

| Phase | Tickets | Estimated Hours |
|-------|---------|-----------------|
| Phase 1: FFI Foundation | 6 | 18 |
| Phase 2: Safe Wrappers | 7 | 26 |
| Phase 3: TrinityCore Loader | 4 | 17 |
| Phase 4: HTTP Service | 11 | 33 |
| Phase 5: Path Smoothing | 4 | 13 |
| Phase 6: Production Hardening | 8 | 31 |
| **Total** | **40** | **138** |

**Estimated Total:** ~138 hours (approximately 3.5 weeks at 40 hrs/week)

**Critical Path:** TICKET-001 → TICKET-005 → TICKET-006 → TICKET-010 → TICKET-011 → TICKET-017 → TICKET-020 → TICKET-021 → TICKET-028 → TICKET-040
