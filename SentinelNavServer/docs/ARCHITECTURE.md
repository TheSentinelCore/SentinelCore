# Architecture Design Document

## AmeisenNav-RS System Architecture

**Version:** 1.0.0  
**Last Updated:** 2026-02-02

---

## 1. System Overview

AmeisenNav-RS is a high-performance navigation mesh server that bridges the gap between Rust HTTP services and C++ game navigation libraries. It serves pathfinding requests from multiple bot clients while maintaining thread safety and low latency.

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Client Layer                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  Bot Client │  │  Bot Client │  │  Bot Client │  │  Bot Client │        │
│  │  (Sylvannas)│  │  (Sylvannas)│  │  (Sylvannas)│  │  (Sylvannas)│        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
└─────────┼────────────────┼────────────────┼────────────────┼────────────────┘
          │                │                │                │
          └────────────────┴────────────────┴────────────────┘
                                    │
                                    │ HTTP GET (JSON)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Service Layer                                     │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                          Axum HTTP Server                               │ │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐  │ │
│  │  │ /api/v1/path │ │ /api/v1/move │ │/api/v1/random│ │ /health      │  │ │
│  │  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────────────┘  │ │
│  └─────────┼────────────────┼────────────────┼───────────────────────────┘ │
│            └────────────────┴────────────────┘                              │
│                             │                                               │
│                             ▼                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                        Application State                                │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────┐   │ │
│  │  │  NavMesh Cache   │  │   Query Pools    │  │  Mmap Loader       │   │ │
│  │  │  (DashMap)       │  │  (per-map)       │  │  (file I/O)        │   │ │
│  │  └──────────────────┘  └──────────────────┘  └────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Navigation Layer                                   │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                      Safe Rust Wrappers (detour)                        │ │
│  │  ┌──────────────┐  ┌──────────────────┐  ┌──────────────────────┐     │ │
│  │  │   NavMesh    │  │   NavMeshQuery   │  │   QueryFilter        │     │ │
│  │  │  (Send+Sync) │  │  (NOT thread-safe)│  │   (Send+Sync)        │     │ │
│  │  └──────────────┘  └──────────────────┘  └──────────────────────┘     │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│                                    ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Raw FFI Bindings (detour-sys)                        │ │
│  │           wrapper_dtNavMesh_*  |  wrapper_dtNavMeshQuery_*              │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│                                    ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │               Recast/Detour C++ Static Library                          │ │
│  │         dtNavMesh  |  dtNavMeshQuery  |  dtQueryFilter                  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Storage Layer                                     │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                     CMaNGOS MMAP Files                                  │ │
│  │  ┌────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐ │ │
│  │  │ 0000.mmap  │  │ 00003232.mmtile │  │ 00003233.mmtile  ...       │ │ │
│  │  │ (metadata) │  │  (tile data)    │  │  (tile data)               │ │ │
│  │  └────────────┘  └─────────────────┘  └─────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Crate Architecture

### 2.1 Workspace Structure

```
ameisen-nav-rs/
├── Cargo.toml                     # Workspace manifest
│
├── crates/
│   ├── detour-sys/                # Layer 1: Raw FFI bindings
│   │   ├── Cargo.toml
│   │   ├── build.rs               # cc + bindgen build script
│   │   ├── wrapper.h              # C wrapper declarations
│   │   ├── wrapper.cpp            # C wrapper implementations
│   │   ├── src/lib.rs             # Re-export generated bindings
│   │   └── recastnavigation/      # Git submodule
│   │       └── Detour/
│   │           ├── Include/
│   │           └── Source/
│   │
│   ├── detour/                    # Layer 2: Safe Rust wrappers
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── mesh.rs            # NavMesh wrapper
│   │       ├── query.rs           # NavMeshQuery wrapper
│   │       ├── filter.rs          # QueryFilter wrapper
│   │       ├── status.rs          # Status code handling
│   │       ├── error.rs           # Error types
│   │       └── pool.rs            # Query pool implementation
│   │
│   ├── mmap-loader/               # Layer 3: CMaNGOS-compatible loader
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── format.rs          # File format structs
│   │       ├── loader.rs          # File I/O
│   │       ├── manager.rs         # Multi-map management
│   │       └── error.rs           # Error types
│   │
│   └── path-smoothing/            # Layer 4: Pure Rust algorithms
│       ├── Cargo.toml
│       └── src/
│           ├── lib.rs
│           ├── chaikin.rs         # Chaikin curve subdivision
│           ├── catmull_rom.rs     # Catmull-Rom splines
│           └── bezier.rs          # Bezier curves
│
└── src/                           # HTTP server binary
    ├── main.rs                    # Entry point
    ├── config.rs                  # Configuration loading
    ├── state.rs                   # Application state
    ├── error.rs                   # API error handling
    └── routes/
        ├── mod.rs
        ├── pathfinding.rs         # /api/v1/path, /api/v1/move
        ├── spatial.rs             # /api/v1/random, /api/v1/raycast
        └── health.rs              # /health
```

### 2.2 Dependency Graph

```
                    ┌─────────────────────┐
                    │   ameisen-nav-rs    │
                    │   (HTTP server)     │
                    └──────────┬──────────┘
                               │
           ┌───────────────────┼───────────────────┐
           │                   │                   │
           ▼                   ▼                   ▼
    ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
    │ path-smoothing│   │ mmap-loader  │   │    detour    │
    │ (pure Rust)  │   │ (mmap I/O)  │   │ (safe wrappers)
    └──────────────┘   └──────┬───────┘   └──────┬───────┘
                              │                   │
                              │                   │
                              │                   ▼
                              │           ┌──────────────┐
                              │           │  detour-sys  │
                              │           │ (FFI bindings)│
                              │           └──────┬───────┘
                              │                   │
                              │                   ▼
                              │           ┌──────────────┐
                              └──────────►│ Recast/Detour│
                                          │    (C++)     │
                                          └──────────────┘
```

---

## 3. Component Designs

### 3.1 FFI Binding Layer (detour-sys)

**Purpose:** Provide raw, unsafe bindings to Recast/Detour C++ library.

**Design Decisions:**
- Use C wrapper functions because bindgen cannot bind C++ class methods
- Compile Detour sources directly via `cc` crate (no system dependencies)
- Opaque types for C++ classes (dtNavMesh, dtNavMeshQuery, etc.)
- All functions are `unsafe extern "C"`

**Build Process:**
```
┌─────────────────────────────────────────────────────────────────┐
│                        build.rs                                  │
│                                                                  │
│  1. cc::Build                          2. cc::Build             │
│     ├─ DetourNavMesh.cpp                  └─ wrapper.cpp        │
│     ├─ DetourNavMeshQuery.cpp                                   │
│     ├─ DetourNode.cpp                                           │
│     └─ ... other Detour sources                                 │
│            ↓                                    ↓                │
│     libdetour.a                        libdetour_wrapper.a      │
│                                                                  │
│  3. bindgen::Builder                                            │
│     ├─ input: wrapper.h                                         │
│     ├─ allowlist_function("wrapper_.*")                         │
│     └─ opaque_type("dtNavMesh", "dtNavMeshQuery", ...)          │
│            ↓                                                     │
│     $OUT_DIR/bindings.rs                                        │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Safe Wrapper Layer (detour)

**Purpose:** Provide safe, idiomatic Rust API over unsafe FFI.

**Key Abstractions:**

```
┌────────────────────────────────────────────────────────────────┐
│                         NavMesh                                 │
│  - Wraps dtNavMesh*                                            │
│  - Send + Sync (read-only after init)                          │
│  - Drop calls wrapper_dtFreeNavMesh                            │
│  - add_tile() handles memory ownership                         │
└────────────────────────────────────────────────────────────────┘
                              │
                              │ References
                              ▼
┌────────────────────────────────────────────────────────────────┐
│                      NavMeshQuery                               │
│  - Wraps dtNavMeshQuery*                                       │
│  - NOT Send/Sync (internal state)                              │
│  - Holds Arc<NavMesh> to prevent use-after-free                │
│  - Drop calls wrapper_dtFreeNavMeshQuery                       │
└────────────────────────────────────────────────────────────────┘
                              │
                              │ Uses
                              ▼
┌────────────────────────────────────────────────────────────────┐
│                       QueryFilter                               │
│  - Wraps dtQueryFilter*                                        │
│  - Send + Sync (immutable after creation)                      │
│  - Configures pathfinding behavior                             │
└────────────────────────────────────────────────────────────────┘
```

**Memory Ownership Model:**

```
              add_tile(TileData::Owned)
                        │
                        ▼
┌────────────────────────────────────────────────────────────────┐
│   Box<[u8]>  ──Box::into_raw()──►  *mut u8                     │
│                                      │                          │
│                         dtNavMesh::addTile(data, DT_TILE_FREE_DATA)
│                                      │                          │
│                                      ▼                          │
│                           Detour owns memory                    │
│                     (will free on removeTile)                   │
└────────────────────────────────────────────────────────────────┘

              On addTile failure:
┌────────────────────────────────────────────────────────────────┐
│   *mut u8  ──Box::from_raw()──►  Box<[u8]>  ──drop──►  freed   │
└────────────────────────────────────────────────────────────────┘
```

### 3.3 MMap Loader (mmap-loader)

**Purpose:** Load and parse CMaNGOS-compatible navigation mesh files.

**Component Structure:**

```
┌────────────────────────────────────────────────────────────────┐
│                       MmapManager                               │
│  - Coordinates loading across multiple maps                    │
│  - Maintains loaded map registry                               │
│  - Handles preloading strategy                                 │
└────────────────────────────────────────────────────────────────┘
                              │
                              │ Contains
                              ▼
┌────────────────────────────────────────────────────────────────┐
│                       MmapLoader                                │
│  - Loads .mmap and .mmtile files                               │
│  - Validates file headers                                      │
│  - Implements tile caching                                     │
└────────────────────────────────────────────────────────────────┘
                              │
                              │ Produces
                              ▼
┌────────────────────────────────────────────────────────────────┐
│                      Tile Data                                  │
│  - MmapNavMeshParams (from .mmap)                              │
│  - Raw tile bytes (from .mmtile)                               │
└────────────────────────────────────────────────────────────────┘
```

**Lazy Loading Strategy:**

```
Request: find_path(map=0, start=(100,200,50), end=(300,400,60))
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Calculate required tiles                                    │
│     start_tile = (x=32, y=32)                                   │
│     end_tile = (x=33, y=33)                                     │
│     tiles_needed = [(32,32), (32,33), (33,32), (33,33)]        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. Check which tiles are loaded                                │
│     loaded: [(32,32), (33,32)]                                  │
│     missing: [(32,33), (33,33)]                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Load missing tiles                                          │
│     load_tile(0, 32, 33) → read 00003233.mmtile → addTile()    │
│     load_tile(0, 33, 33) → read 00003333.mmtile → addTile()    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. Perform pathfinding                                         │
└─────────────────────────────────────────────────────────────────┘
```

### 3.4 HTTP Service Layer

**Purpose:** Handle HTTP requests and coordinate navigation operations.

**Request Flow:**

```
                HTTP GET /api/v1/path?...
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Axum Router                                   │
│   route("/api/v1/path", get(find_path))                         │
└─────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                 find_path Handler                                │
│   1. Parse query parameters                                      │
│   2. Acquire semaphore permit                                    │
│   3. Ensure tiles loaded                                         │
│   4. Acquire query from pool                                     │
│   5. spawn_blocking { query.find_path() }                       │
│   6. Apply smoothing                                             │
│   7. Build JSON response                                         │
└─────────────────────────────────────────────────────────────────┘
                        │
                        ▼
                  JSON Response
```

**Application State:**

```rust
pub struct AppState {
    // File system access
    pub mmap_loader: Arc<MmapLoader>,
    
    // Cached navmeshes (map_id -> NavMesh)
    pub navmeshes: DashMap<u32, Arc<NavMesh>>,
    
    // Query pools (map_id -> QueryPool)
    pub query_pools: DashMap<u32, QueryPool>,
    
    // Configuration
    pub config: Config,
    
    // Concurrency control
    pub pathfinding_semaphore: Arc<Semaphore>,
}
```

---

## 4. Concurrency Model

### 4.1 Thread Safety Analysis

| Component | Thread Safety | Justification |
|-----------|--------------|---------------|
| NavMesh | Send + Sync | Read-only after initialization |
| NavMeshQuery | !Send, !Sync | Internal mutable state (node pool) |
| QueryFilter | Send + Sync | Immutable configuration |
| MmapLoader | Send + Sync | Mutex-protected cache |
| DashMap | Send + Sync | Concurrent hash map |
| QueryPool | Send + Sync | Mutex-protected pool |

### 4.2 Query Pool Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│                       QueryPool                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  Mutex<Vec<NavMeshQuery>>                                 │ │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐            │ │
│  │  │   Query    │ │   Query    │ │   Query    │   ...      │ │
│  │  └────────────┘ └────────────┘ └────────────┘            │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
         │                                    ▲
         │ acquire()                          │ return (via Drop)
         ▼                                    │
┌────────────────────────────────────────────┴────────────────────┐
│                     PooledQuery                                  │
│   - Wraps Option<NavMeshQuery>                                  │
│   - Implements Deref for transparent access                     │
│   - Drop returns query to pool                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 Async/Blocking Boundary

```
┌─────────────────────────────────────────────────────────────────┐
│                   Tokio Async Runtime                            │
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐ │
│   │  Async Tasks (HTTP handlers)                              │ │
│   │    - Parse requests                                       │ │
│   │    - Manage state                                         │ │
│   │    - Build responses                                      │ │
│   └──────────────────────────┬───────────────────────────────┘ │
│                              │                                   │
│                   tokio::task::spawn_blocking()                 │
│                              │                                   │
│   ┌──────────────────────────▼───────────────────────────────┐ │
│   │  Blocking Thread Pool                                     │ │
│   │    - CPU-bound pathfinding                               │ │
│   │    - FFI calls                                           │ │
│   │    - File I/O                                            │ │
│   └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Data Flow

### 5.1 Pathfinding Request Flow

```
Client Request
     │
     ▼
┌────────────────────────────────────────────────────────────┐
│ Parse: PathParams { map_id, start, end, smoothing }        │
└────────────────────────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────────────────┐
│ Load Map (if needed)                                        │
│   1. Read {map_id}.mmap                                     │
│   2. Create NavMesh from params                             │
│   3. Store in navmeshes DashMap                             │
│   4. Create QueryPool for map                               │
└────────────────────────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────────────────┐
│ Load Tiles (lazy)                                           │
│   1. Calculate tile coords for start/end                    │
│   2. Load missing tiles from .mmtile files                  │
│   3. Add tiles to NavMesh                                   │
└────────────────────────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────────────────┐
│ Pathfinding (spawn_blocking)                                │
│   1. Acquire query from pool                                │
│   2. findNearestPoly(start) → start_ref                     │
│   3. findNearestPoly(end) → end_ref                         │
│   4. findPath(start_ref, end_ref) → poly_path               │
│   5. findStraightPath(poly_path) → waypoints                │
│   6. Return query to pool                                   │
└────────────────────────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────────────────┐
│ Smoothing (optional)                                        │
│   chaikin() | catmull_rom() | bezier()                     │
└────────────────────────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────────────────┐
│ Response: PathResponse { success, path, distance, ... }    │
└────────────────────────────────────────────────────────────┘
     │
     ▼
Client Response
```

---

## 6. Error Handling Strategy

### 6.1 Error Propagation

```
┌─────────────────────────────────────────────────────────────────┐
│                    FFI Layer (detour-sys)                        │
│   - Returns dtStatus codes                                       │
│   - Never panics                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                        DetourError
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Safe Layer (detour)                            │
│   - Converts dtStatus to Result<T, DetourError>                 │
│   - Adds context (StartNotFound, EndNotFound, etc.)             │
└─────────────────────────────────────────────────────────────────┘
                              │
                        DetourError | MmapError
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Service Layer (routes)                         │
│   - Converts to ApiError                                         │
│   - Maps to HTTP status codes                                    │
│   - Builds JSON error response                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                         ApiError
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      HTTP Response                               │
│   { "success": false, "error": "Start position not on navmesh" }│
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Error Categories

| Category | Examples | HTTP Status |
|----------|----------|-------------|
| Client Error | Invalid params, missing coords | 400 Bad Request |
| Not Found | Map not available, path not found | 404 Not Found |
| Server Error | Allocation failed, FFI error | 500 Internal Server Error |
| Overload | Too many concurrent requests | 503 Service Unavailable |

---

## 7. Performance Optimizations

### 7.1 Caching Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                    Three-Level Cache                             │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ L1: NavMesh Cache (DashMap)                                │ │
│  │   - Loaded navmeshes per map                               │ │
│  │   - Never evicted (maps are large, few in number)          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ L2: Tile Cache (in NavMesh)                                │ │
│  │   - Loaded tiles within each mesh                          │ │
│  │   - LRU eviction for continent maps                        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ L3: File Cache (MmapLoader)                                │ │
│  │   - Raw tile bytes from recent loads                       │ │
│  │   - Avoids repeated disk I/O                               │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Preloading Strategy

```
At Startup:
┌─────────────────────────────────────────────────────────────────┐
│ 1. Load configured preload_maps (e.g., [0, 1, 530, 571])       │
│                                                                  │
│ 2. For dungeons (known small maps):                             │
│    - Load ALL tiles eagerly                                     │
│    - Fast startup, complete coverage                            │
│                                                                  │
│ 3. For continents (large maps):                                 │
│    - Load map params only                                       │
│    - Tiles loaded on-demand                                     │
│    - Optionally preload common areas                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. Deployment Architecture

### 8.1 Single Instance Deployment

```
┌─────────────────────────────────────────────────────────────────┐
│                         Host Machine                             │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Docker Container                               │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │           ameisen-nav-rs                             │ │ │
│  │  │              :3000                                   │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  │                         │                                  │ │
│  │              Volume: /data/mmaps                          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │           Bot Instances (same host)                        │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐                   │ │
│  │  │Sylvannas │ │Sylvannas │ │Sylvannas │                   │ │
│  │  │   Bot    │ │   Bot    │ │   Bot    │                   │ │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘                   │ │
│  │       └────────────┴────────────┘                          │ │
│  │                    │                                        │ │
│  │              localhost:3000                                 │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Resource Requirements

| Component | Memory | CPU | Disk |
|-----------|--------|-----|------|
| Server Process | ~100MB base | Variable | - |
| Per Continent | ~500-800MB | - | ~200MB |
| Per Dungeon | ~10-50MB | - | ~5-20MB |
| Total (4 continents) | ~2-3GB | 2+ cores | ~1GB |

---

## 9. Security Considerations

### 9.1 Input Validation

```rust
// All numeric parameters are validated
fn validate_coords(x: f32, y: f32, z: f32) -> Result<Vec3, ApiError> {
    if !x.is_finite() || !y.is_finite() || !z.is_finite() {
        return Err(ApiError::InvalidParams);
    }
    
    // WoW coordinate bounds
    if x.abs() > 50000.0 || y.abs() > 50000.0 || z.abs() > 50000.0 {
        return Err(ApiError::InvalidParams);
    }
    
    Ok(Vec3::new(x, y, z))
}
```

### 9.2 Resource Limits

| Limit | Value | Purpose |
|-------|-------|---------|
| Max concurrent requests | 100 | Prevent overload |
| Request timeout | 30s | Prevent hung requests |
| Max path length | 2048 | Bound memory usage |
| Max maps loaded | 20 | Bound memory usage |
