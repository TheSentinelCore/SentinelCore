# AmeisenNavigation Rust Rewrite Plan
## Custom FFI Bindings via Bindgen for Recast/Detour

This document outlines a complete implementation plan for rewriting AmeisenNavigation as a Rust HTTP service using **custom FFI bindings** generated via `bindgen` for the Recast/Detour C++ navigation library, with strict TrinityCore mmap file format compatibility.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [AmeisenNavigation Feature Analysis](#2-ameisennavigation-feature-analysis)
3. [Detour API Surface to Bind](#3-detour-api-surface-to-bind)
4. [FFI Binding Strategy with Bindgen](#4-ffi-binding-strategy-with-bindgen)
5. [TrinityCore MMAP File Format](#5-trinitycore-mmap-file-format)
6. [Project Structure](#6-project-structure)
7. [Implementation Details](#7-implementation-details)
8. [HTTP Service Architecture](#8-http-service-architecture)
9. [Client Integration (Sylvannas API)](#9-client-integration-sylvannas-api)
10. [Build System](#10-build-system)
11. [Implementation Roadmap](#11-implementation-roadmap)
12. [Testing Strategy](#12-testing-strategy)

---

## 1. Project Overview

### Goals

- Rewrite AmeisenNavigation as a Rust HTTP service
- Create custom FFI bindings to Recast/Detour using `bindgen` (no third-party Rust wrappers)
- Maintain strict compatibility with TrinityCore mmap file format
- Expose pathfinding via HTTP endpoints for Sylvannas bot clients
- Support concurrent pathfinding requests from multiple bot instances

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Sylvannas Bot Clients                        │
│                    (Lua scripts using core.http_get)                │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ HTTP (GET with JSON query params)
┌─────────────────────────────────────────────────────────────────────┐
│                     Rust Navigation HTTP Service                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐ │
│  │   Axum      │  │  Pathfinder │  │  TrinityCore MMAP Loader    │ │
│  │   Router    │──│   Engine    │──│  (lazy tile loading)        │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────────┘ │
│                          │                                          │
│                          ▼                                          │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              Custom FFI Bindings (detour-sys)               │   │
│  │         Generated via bindgen from Detour headers           │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                          │                                          │
│                          ▼                                          │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │           Recast/Detour C++ Static Library                  │   │
│  │              (compiled via cc crate)                        │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. AmeisenNavigation Feature Analysis

Based on analysis of the AmeisenNavigation source, these are the core features to implement:

### Pathfinding Operations

| Feature | Detour API | Description |
|---------|-----------|-------------|
| Find Path | `findPath()` + `findStraightPath()` | A* pathfinding between two world positions |
| Move Along Surface | `moveAlongSurface()` | Constrained delta movement on navmesh |
| Raycast | `raycast()` | Line-of-sight / movement validation |
| Random Point | `findRandomPoint()` | Random navigable position on mesh |
| Random Point in Circle | `findRandomPointAroundCircle()` | Random position within radius |
| Get Poly Height | `getPolyHeight()` | Height at position on navmesh |

### Path Smoothing Algorithms (Pure Rust)

1. **Chaikin Curve Subdivision** - Corner cutting for smooth curves
2. **Catmull-Rom Spline** - Smooth interpolation through waypoints  
3. **Bezier Curve** - Smooth curves with configurable control points

### MMAP Format Support

- TrinityCore 3.3.5a format (primary)
- SkyFire 5.4.8 format (secondary)
- Custom format patterns (configurable)

---

## 3. Detour API Surface to Bind

These are the specific Detour C++ APIs that need FFI bindings:

### Core Types

```cpp
// From DetourNavMesh.h
typedef unsigned int dtPolyRef;      // Polygon reference handle
typedef unsigned int dtTileRef;      // Tile reference handle
typedef unsigned int dtStatus;       // Status code (success/failure flags)

struct dtNavMeshParams {
    float orig[3];          // World origin
    float tileWidth;        // Tile width
    float tileHeight;       // Tile height  
    int maxTiles;           // Max tiles
    int maxPolys;           // Max polygons per tile
};

struct dtMeshHeader {
    int magic;              // DT_NAVMESH_MAGIC
    int version;            // DT_NAVMESH_VERSION
    int x, y, layer;        // Tile coordinates
    unsigned int userId;
    int polyCount;
    int vertCount;
    int maxLinkCount;
    int detailMeshCount;
    int detailVertCount;
    int detailTriCount;
    int bvNodeCount;
    int offMeshConCount;
    int offMeshBase;
    float walkableHeight;
    float walkableRadius;
    float walkableClimb;
    float bmin[3], bmax[3];
    float bvQuantFactor;
};
```

### Allocation Functions

```cpp
// Must bind these for proper lifecycle management
dtNavMesh* dtAllocNavMesh();
void dtFreeNavMesh(dtNavMesh* navmesh);

dtNavMeshQuery* dtAllocNavMeshQuery();
void dtFreeNavMeshQuery(dtNavMeshQuery* query);

dtQueryFilter* dtAllocQueryFilter();
void dtFreeQueryFilter(dtQueryFilter* filter);
```

### dtNavMesh Methods

```cpp
dtStatus dtNavMesh::init(const dtNavMeshParams* params);
dtStatus dtNavMesh::init(unsigned char* data, int dataSize, int flags);

dtStatus dtNavMesh::addTile(
    unsigned char* data, 
    int dataSize,
    int flags,              // DT_TILE_FREE_DATA if Detour owns memory
    dtTileRef lastRef,
    dtTileRef* result
);

dtStatus dtNavMesh::removeTile(
    dtTileRef ref,
    unsigned char** data,
    int* dataSize
);

const dtNavMeshParams* dtNavMesh::getParams() const;
int dtNavMesh::getMaxTiles() const;
const dtMeshTile* dtNavMesh::getTile(int i) const;
```

### dtNavMeshQuery Methods

```cpp
dtStatus dtNavMeshQuery::init(const dtNavMesh* nav, int maxNodes);

// Core pathfinding
dtStatus dtNavMeshQuery::findPath(
    dtPolyRef startRef, 
    dtPolyRef endRef,
    const float* startPos, 
    const float* endPos,
    const dtQueryFilter* filter,
    dtPolyRef* path, 
    int* pathCount, 
    int maxPath
);

dtStatus dtNavMeshQuery::findStraightPath(
    const float* startPos,
    const float* endPos,
    const dtPolyRef* path,
    int pathSize,
    float* straightPath,
    unsigned char* straightPathFlags,
    dtPolyRef* straightPathRefs,
    int* straightPathCount,
    int maxStraightPath,
    int options  // DT_STRAIGHTPATH_AREA_CROSSINGS, etc.
);

// Spatial queries
dtStatus dtNavMeshQuery::findNearestPoly(
    const float* center,
    const float* halfExtents,
    const dtQueryFilter* filter,
    dtPolyRef* nearestRef,
    float* nearestPt
);

dtStatus dtNavMeshQuery::closestPointOnPoly(
    dtPolyRef ref,
    const float* pos,
    float* closest,
    bool* posOverPoly
);

// Movement
dtStatus dtNavMeshQuery::moveAlongSurface(
    dtPolyRef startRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    float* resultPos,
    dtPolyRef* visited,
    int* visitedCount,
    int maxVisitedSize
);

dtStatus dtNavMeshQuery::raycast(
    dtPolyRef startRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    float* t,
    float* hitNormal,
    dtPolyRef* path,
    int* pathCount,
    int maxPath
);

// Random points
dtStatus dtNavMeshQuery::findRandomPoint(
    const dtQueryFilter* filter,
    float (*frand)(),
    dtPolyRef* randomRef,
    float* randomPt
);

dtStatus dtNavMeshQuery::findRandomPointAroundCircle(
    dtPolyRef startRef,
    const float* centerPos,
    float maxRadius,
    const dtQueryFilter* filter,
    float (*frand)(),
    dtPolyRef* randomRef,
    float* randomPt
);

// Height query
dtStatus dtNavMeshQuery::getPolyHeight(
    dtPolyRef ref,
    const float* pos,
    float* height
);
```

### dtQueryFilter Methods

```cpp
void dtQueryFilter::setIncludeFlags(unsigned short flags);
void dtQueryFilter::setExcludeFlags(unsigned short flags);
unsigned short dtQueryFilter::getIncludeFlags() const;
unsigned short dtQueryFilter::getExcludeFlags() const;
void dtQueryFilter::setAreaCost(int i, float cost);
float dtQueryFilter::getAreaCost(int i) const;
```

### Status Macros

```cpp
#define DT_SUCCESS 1u
#define DT_FAILURE 0u
#define DT_IN_PROGRESS (1u << 30)
#define DT_STATUS_DETAIL_MASK 0x0ffffff
#define DT_WRONG_MAGIC (1 << 0)
#define DT_WRONG_VERSION (1 << 1)
#define DT_OUT_OF_MEMORY (1 << 2)
#define DT_INVALID_PARAM (1 << 3)
#define DT_BUFFER_TOO_SMALL (1 << 4)
#define DT_OUT_OF_NODES (1 << 5)
#define DT_PARTIAL_RESULT (1 << 6)
#define DT_ALREADY_OCCUPIED (1 << 7)

inline bool dtStatusSucceed(dtStatus status) { return (status & DT_FAILURE) == 0; }
inline bool dtStatusFailed(dtStatus status) { return (status & DT_FAILURE) != 0; }
inline bool dtStatusInProgress(dtStatus status) { return (status & DT_IN_PROGRESS) != 0; }
inline bool dtStatusDetail(dtStatus status, unsigned int detail) { return (status & detail) != 0; }
```

---

## 4. FFI Binding Strategy with Bindgen

### Wrapper Header Approach

Create a single `wrapper.h` that includes only the headers we need:

```c
// crates/detour-sys/wrapper.h

#ifndef DETOUR_WRAPPER_H
#define DETOUR_WRAPPER_H

// Include Detour headers
#include "DetourAlloc.h"
#include "DetourAssert.h"
#include "DetourCommon.h"
#include "DetourMath.h"
#include "DetourNavMesh.h"
#include "DetourNavMeshBuilder.h"
#include "DetourNavMeshQuery.h"
#include "DetourNode.h"
#include "DetourStatus.h"

// C wrapper functions for C++ class methods
// (bindgen can't directly call C++ methods)

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Allocation
// ============================================================================
dtNavMesh* wrapper_dtAllocNavMesh(void);
void wrapper_dtFreeNavMesh(dtNavMesh* mesh);

dtNavMeshQuery* wrapper_dtAllocNavMeshQuery(void);
void wrapper_dtFreeNavMeshQuery(dtNavMeshQuery* query);

// ============================================================================
// dtNavMesh
// ============================================================================
dtStatus wrapper_dtNavMesh_init(
    dtNavMesh* mesh,
    const dtNavMeshParams* params
);

dtStatus wrapper_dtNavMesh_addTile(
    dtNavMesh* mesh,
    unsigned char* data,
    int dataSize,
    int flags,
    dtTileRef lastRef,
    dtTileRef* result
);

dtStatus wrapper_dtNavMesh_removeTile(
    dtNavMesh* mesh,
    dtTileRef ref,
    unsigned char** data,
    int* dataSize
);

const dtNavMeshParams* wrapper_dtNavMesh_getParams(const dtNavMesh* mesh);

// ============================================================================
// dtNavMeshQuery
// ============================================================================
dtStatus wrapper_dtNavMeshQuery_init(
    dtNavMeshQuery* query,
    const dtNavMesh* nav,
    int maxNodes
);

dtStatus wrapper_dtNavMeshQuery_findPath(
    dtNavMeshQuery* query,
    dtPolyRef startRef,
    dtPolyRef endRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    dtPolyRef* path,
    int* pathCount,
    int maxPath
);

dtStatus wrapper_dtNavMeshQuery_findStraightPath(
    dtNavMeshQuery* query,
    const float* startPos,
    const float* endPos,
    const dtPolyRef* path,
    int pathSize,
    float* straightPath,
    unsigned char* straightPathFlags,
    dtPolyRef* straightPathRefs,
    int* straightPathCount,
    int maxStraightPath,
    int options
);

dtStatus wrapper_dtNavMeshQuery_findNearestPoly(
    dtNavMeshQuery* query,
    const float* center,
    const float* halfExtents,
    const dtQueryFilter* filter,
    dtPolyRef* nearestRef,
    float* nearestPt
);

dtStatus wrapper_dtNavMeshQuery_closestPointOnPoly(
    dtNavMeshQuery* query,
    dtPolyRef ref,
    const float* pos,
    float* closest,
    bool* posOverPoly
);

dtStatus wrapper_dtNavMeshQuery_moveAlongSurface(
    dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    float* resultPos,
    dtPolyRef* visited,
    int* visitedCount,
    int maxVisitedSize
);

dtStatus wrapper_dtNavMeshQuery_raycast(
    dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    float* t,
    float* hitNormal,
    dtPolyRef* path,
    int* pathCount,
    int maxPath
);

// Random point functions need special handling for frand callback
dtStatus wrapper_dtNavMeshQuery_findRandomPoint(
    dtNavMeshQuery* query,
    const dtQueryFilter* filter,
    dtPolyRef* randomRef,
    float* randomPt
);

dtStatus wrapper_dtNavMeshQuery_findRandomPointAroundCircle(
    dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* centerPos,
    float maxRadius,
    const dtQueryFilter* filter,
    dtPolyRef* randomRef,
    float* randomPt
);

dtStatus wrapper_dtNavMeshQuery_getPolyHeight(
    dtNavMeshQuery* query,
    dtPolyRef ref,
    const float* pos,
    float* height
);

// ============================================================================
// dtQueryFilter
// ============================================================================
dtQueryFilter* wrapper_dtAllocQueryFilter(void);
void wrapper_dtFreeQueryFilter(dtQueryFilter* filter);

void wrapper_dtQueryFilter_setIncludeFlags(dtQueryFilter* filter, unsigned short flags);
void wrapper_dtQueryFilter_setExcludeFlags(dtQueryFilter* filter, unsigned short flags);
unsigned short wrapper_dtQueryFilter_getIncludeFlags(const dtQueryFilter* filter);
unsigned short wrapper_dtQueryFilter_getExcludeFlags(const dtQueryFilter* filter);
void wrapper_dtQueryFilter_setAreaCost(dtQueryFilter* filter, int i, float cost);
float wrapper_dtQueryFilter_getAreaCost(const dtQueryFilter* filter, int i);

#ifdef __cplusplus
}
#endif

#endif // DETOUR_WRAPPER_H
```

### C++ Wrapper Implementation

```cpp
// crates/detour-sys/wrapper.cpp

#include "wrapper.h"
#include <cstdlib>

// Thread-local RNG for random point queries
static thread_local unsigned int tls_seed = 1;

static float wrapper_frand() {
    tls_seed = tls_seed * 1103515245 + 12345;
    return ((float)(tls_seed & 0x7fff)) / 32767.0f;
}

extern "C" {

// ============================================================================
// Allocation
// ============================================================================

dtNavMesh* wrapper_dtAllocNavMesh(void) {
    return dtAllocNavMesh();
}

void wrapper_dtFreeNavMesh(dtNavMesh* mesh) {
    dtFreeNavMesh(mesh);
}

dtNavMeshQuery* wrapper_dtAllocNavMeshQuery(void) {
    return dtAllocNavMeshQuery();
}

void wrapper_dtFreeNavMeshQuery(dtNavMeshQuery* query) {
    dtFreeNavMeshQuery(query);
}

// ============================================================================
// dtNavMesh
// ============================================================================

dtStatus wrapper_dtNavMesh_init(dtNavMesh* mesh, const dtNavMeshParams* params) {
    return mesh->init(params);
}

dtStatus wrapper_dtNavMesh_addTile(
    dtNavMesh* mesh,
    unsigned char* data,
    int dataSize,
    int flags,
    dtTileRef lastRef,
    dtTileRef* result
) {
    return mesh->addTile(data, dataSize, flags, lastRef, result);
}

dtStatus wrapper_dtNavMesh_removeTile(
    dtNavMesh* mesh,
    dtTileRef ref,
    unsigned char** data,
    int* dataSize
) {
    return mesh->removeTile(ref, data, dataSize);
}

const dtNavMeshParams* wrapper_dtNavMesh_getParams(const dtNavMesh* mesh) {
    return mesh->getParams();
}

// ============================================================================
// dtNavMeshQuery
// ============================================================================

dtStatus wrapper_dtNavMeshQuery_init(
    dtNavMeshQuery* query,
    const dtNavMesh* nav,
    int maxNodes
) {
    return query->init(nav, maxNodes);
}

dtStatus wrapper_dtNavMeshQuery_findPath(
    dtNavMeshQuery* query,
    dtPolyRef startRef,
    dtPolyRef endRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    dtPolyRef* path,
    int* pathCount,
    int maxPath
) {
    return query->findPath(startRef, endRef, startPos, endPos, filter, path, pathCount, maxPath);
}

dtStatus wrapper_dtNavMeshQuery_findStraightPath(
    dtNavMeshQuery* query,
    const float* startPos,
    const float* endPos,
    const dtPolyRef* path,
    int pathSize,
    float* straightPath,
    unsigned char* straightPathFlags,
    dtPolyRef* straightPathRefs,
    int* straightPathCount,
    int maxStraightPath,
    int options
) {
    return query->findStraightPath(
        startPos, endPos, path, pathSize,
        straightPath, straightPathFlags, straightPathRefs,
        straightPathCount, maxStraightPath, options
    );
}

dtStatus wrapper_dtNavMeshQuery_findNearestPoly(
    dtNavMeshQuery* query,
    const float* center,
    const float* halfExtents,
    const dtQueryFilter* filter,
    dtPolyRef* nearestRef,
    float* nearestPt
) {
    return query->findNearestPoly(center, halfExtents, filter, nearestRef, nearestPt);
}

dtStatus wrapper_dtNavMeshQuery_closestPointOnPoly(
    dtNavMeshQuery* query,
    dtPolyRef ref,
    const float* pos,
    float* closest,
    bool* posOverPoly
) {
    return query->closestPointOnPoly(ref, pos, closest, posOverPoly);
}

dtStatus wrapper_dtNavMeshQuery_moveAlongSurface(
    dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    float* resultPos,
    dtPolyRef* visited,
    int* visitedCount,
    int maxVisitedSize
) {
    return query->moveAlongSurface(
        startRef, startPos, endPos, filter,
        resultPos, visited, visitedCount, maxVisitedSize
    );
}

dtStatus wrapper_dtNavMeshQuery_raycast(
    dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    float* t,
    float* hitNormal,
    dtPolyRef* path,
    int* pathCount,
    int maxPath
) {
    return query->raycast(startRef, startPos, endPos, filter, t, hitNormal, path, pathCount, maxPath);
}

dtStatus wrapper_dtNavMeshQuery_findRandomPoint(
    dtNavMeshQuery* query,
    const dtQueryFilter* filter,
    dtPolyRef* randomRef,
    float* randomPt
) {
    return query->findRandomPoint(filter, wrapper_frand, randomRef, randomPt);
}

dtStatus wrapper_dtNavMeshQuery_findRandomPointAroundCircle(
    dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* centerPos,
    float maxRadius,
    const dtQueryFilter* filter,
    dtPolyRef* randomRef,
    float* randomPt
) {
    return query->findRandomPointAroundCircle(
        startRef, centerPos, maxRadius, filter,
        wrapper_frand, randomRef, randomPt
    );
}

dtStatus wrapper_dtNavMeshQuery_getPolyHeight(
    dtNavMeshQuery* query,
    dtPolyRef ref,
    const float* pos,
    float* height
) {
    return query->getPolyHeight(ref, pos, height);
}

// ============================================================================
// dtQueryFilter
// ============================================================================

dtQueryFilter* wrapper_dtAllocQueryFilter(void) {
    return new dtQueryFilter();
}

void wrapper_dtFreeQueryFilter(dtQueryFilter* filter) {
    delete filter;
}

void wrapper_dtQueryFilter_setIncludeFlags(dtQueryFilter* filter, unsigned short flags) {
    filter->setIncludeFlags(flags);
}

void wrapper_dtQueryFilter_setExcludeFlags(dtQueryFilter* filter, unsigned short flags) {
    filter->setExcludeFlags(flags);
}

unsigned short wrapper_dtQueryFilter_getIncludeFlags(const dtQueryFilter* filter) {
    return filter->getIncludeFlags();
}

unsigned short wrapper_dtQueryFilter_getExcludeFlags(const dtQueryFilter* filter) {
    return filter->getExcludeFlags();
}

void wrapper_dtQueryFilter_setAreaCost(dtQueryFilter* filter, int i, float cost) {
    filter->setAreaCost(i, cost);
}

float wrapper_dtQueryFilter_getAreaCost(const dtQueryFilter* filter, int i) {
    return filter->getAreaCost(i);
}

} // extern "C"
```

### build.rs for detour-sys

```rust
// crates/detour-sys/build.rs

use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=wrapper.h");
    println!("cargo:rerun-if-changed=wrapper.cpp");
    println!("cargo:rerun-if-changed=recastnavigation/");

    let detour_path = PathBuf::from("recastnavigation/Detour");
    
    // Compile Detour C++ sources
    cc::Build::new()
        .cpp(true)
        .include(detour_path.join("Include"))
        .file(detour_path.join("Source/DetourAlloc.cpp"))
        .file(detour_path.join("Source/DetourAssert.cpp"))
        .file(detour_path.join("Source/DetourCommon.cpp"))
        .file(detour_path.join("Source/DetourNavMesh.cpp"))
        .file(detour_path.join("Source/DetourNavMeshBuilder.cpp"))
        .file(detour_path.join("Source/DetourNavMeshQuery.cpp"))
        .file(detour_path.join("Source/DetourNode.cpp"))
        // Compile our wrapper
        .file("wrapper.cpp")
        .flag_if_supported("-std=c++14")
        .flag_if_supported("-fno-exceptions")
        .flag_if_supported("-fno-rtti")
        .warnings(false)
        .compile("detour");

    // Generate bindings
    let bindings = bindgen::Builder::default()
        .header("wrapper.h")
        .clang_arg(format!("-I{}", detour_path.join("Include").display()))
        .clang_arg("-x")
        .clang_arg("c++")
        .clang_arg("-std=c++14")
        // Only generate bindings for our wrapper functions and necessary types
        .allowlist_function("wrapper_.*")
        .allowlist_function("dtStatusSucceed")
        .allowlist_function("dtStatusFailed")
        .allowlist_function("dtStatusInProgress")
        .allowlist_function("dtStatusDetail")
        .allowlist_type("dtNavMesh")
        .allowlist_type("dtNavMeshQuery")
        .allowlist_type("dtQueryFilter")
        .allowlist_type("dtNavMeshParams")
        .allowlist_type("dtMeshHeader")
        .allowlist_type("dtMeshTile")
        .allowlist_type("dtPoly")
        .allowlist_type("dtPolyRef")
        .allowlist_type("dtTileRef")
        .allowlist_type("dtStatus")
        .allowlist_var("DT_.*")
        // Treat dtNavMesh, dtNavMeshQuery, dtQueryFilter as opaque
        .opaque_type("dtNavMesh")
        .opaque_type("dtNavMeshQuery")
        .opaque_type("dtQueryFilter")
        .opaque_type("dtNodePool")
        .opaque_type("dtNode")
        .derive_debug(true)
        .derive_default(true)
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
```

---

## 5. TrinityCore MMAP File Format

### File Types

TrinityCore stores navmesh data in two file types:

#### Map Metadata Files (`.mmap`)

**Filename pattern:** `{mapId:04}.mmap` (e.g., `0000.mmap` for Eastern Kingdoms)

Contains only the 28-byte `dtNavMeshParams` structure:

```rust
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct DtNavMeshParams {
    pub orig: [f32; 3],     // World origin: [-17066.666, 0.0, -17066.666]
    pub tile_width: f32,    // ~533.333 yards per tile
    pub tile_height: f32,   // ~533.333 yards per tile
    pub max_tiles: i32,     // 2048-4096 for continents
    pub max_polys: i32,     // Polygon encoding bits
}
```

#### Tile Data Files (`.mmtile`)

**Filename pattern:** `{mapId:04}{x:02}{y:02}.mmtile` (e.g., `0002239.mmtile`)

Contains a 20-byte TrinityCore header followed by raw Detour tile data:

```rust
/// TrinityCore MMAP tile header
/// sizeof(MmapTileHeader) == 20 bytes
#[repr(C, packed)]
#[derive(Debug, Clone, Copy)]
pub struct MmapTileHeader {
    pub mmap_magic: u32,     // 0x4D4D4150 ("MMAP")
    pub dt_version: u32,     // Detour navmesh version (7)
    pub mmap_version: u32,   // TC mmap generator version (5-9)
    pub size: u32,           // Tile data size following header
    pub uses_liquids: u8,    // Water navigation flag (bool)
    pub padding: [u8; 3],    // Alignment padding
}

pub const MMAP_MAGIC: u32 = 0x4D4D4150;  // "MMAP" in little-endian
pub const DT_NAVMESH_VERSION: u32 = 7;
pub const MMAP_VERSION: u32 = 9;         // Current TC version
```

### MMAP Loader Implementation

```rust
// crates/tc-mmap/src/loader.rs

use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use dashmap::DashMap;
use memmap2::Mmap;
use parking_lot::RwLock;

use crate::format::{MmapTileHeader, MMAP_MAGIC, MMAP_VERSION, DT_NAVMESH_VERSION};
use crate::error::MmapError;

pub struct MmapLoader {
    base_path: PathBuf,
    // Map ID -> (NavMeshParams, loaded tile coordinates)
    loaded_maps: DashMap<u32, Arc<RwLock<LoadedMap>>>,
}

struct LoadedMap {
    params: DtNavMeshParams,
    loaded_tiles: HashMap<(u32, u32), TileData>,
}

struct TileData {
    data: Vec<u8>,
    uses_liquids: bool,
}

impl MmapLoader {
    pub fn new<P: AsRef<Path>>(base_path: P) -> Self {
        Self {
            base_path: base_path.as_ref().to_path_buf(),
            loaded_maps: DashMap::new(),
        }
    }

    /// Load map parameters from .mmap file
    pub fn load_map_params(&self, map_id: u32) -> Result<DtNavMeshParams, MmapError> {
        let filename = self.base_path.join(format!("{:04}.mmap", map_id));
        let mut file = File::open(&filename)
            .map_err(|e| MmapError::FileNotFound(filename.clone(), e))?;
        
        let mut params = DtNavMeshParams::default();
        let params_bytes = unsafe {
            std::slice::from_raw_parts_mut(
                &mut params as *mut _ as *mut u8,
                std::mem::size_of::<DtNavMeshParams>()
            )
        };
        
        file.read_exact(params_bytes)
            .map_err(|e| MmapError::ReadError(filename, e))?;
        
        Ok(params)
    }

    /// Load a single tile from .mmtile file
    pub fn load_tile(&self, map_id: u32, x: u32, y: u32) -> Result<(Vec<u8>, bool), MmapError> {
        let filename = self.base_path.join(format!("{:04}{:02}{:02}.mmtile", map_id, x, y));
        
        let mut file = File::open(&filename)
            .map_err(|e| MmapError::FileNotFound(filename.clone(), e))?;
        
        // Read header
        let mut header = MmapTileHeader::default();
        let header_bytes = unsafe {
            std::slice::from_raw_parts_mut(
                &mut header as *mut _ as *mut u8,
                std::mem::size_of::<MmapTileHeader>()
            )
        };
        
        file.read_exact(header_bytes)
            .map_err(|e| MmapError::ReadError(filename.clone(), e))?;
        
        // Validate header
        if header.mmap_magic != MMAP_MAGIC {
            return Err(MmapError::InvalidMagic {
                expected: MMAP_MAGIC,
                found: header.mmap_magic,
                file: filename,
            });
        }
        
        if header.dt_version != DT_NAVMESH_VERSION {
            return Err(MmapError::VersionMismatch {
                expected: DT_NAVMESH_VERSION,
                found: header.dt_version,
                file: filename,
            });
        }
        
        // Read tile data
        let mut tile_data = vec![0u8; header.size as usize];
        file.read_exact(&mut tile_data)
            .map_err(|e| MmapError::ReadError(filename, e))?;
        
        Ok((tile_data, header.uses_liquids != 0))
    }

    /// Check if a tile file exists
    pub fn tile_exists(&self, map_id: u32, x: u32, y: u32) -> bool {
        let filename = self.base_path.join(format!("{:04}{:02}{:02}.mmtile", map_id, x, y));
        filename.exists()
    }

    /// Get all available tile coordinates for a map
    pub fn get_available_tiles(&self, map_id: u32) -> Vec<(u32, u32)> {
        let pattern = format!("{:04}", map_id);
        let mut tiles = Vec::new();
        
        if let Ok(entries) = std::fs::read_dir(&self.base_path) {
            for entry in entries.flatten() {
                let name = entry.file_name();
                let name_str = name.to_string_lossy();
                
                if name_str.starts_with(&pattern) && name_str.ends_with(".mmtile") {
                    // Parse coordinates from filename: MMMMXXYY.mmtile
                    if name_str.len() >= 12 {
                        if let (Ok(x), Ok(y)) = (
                            name_str[4..6].parse::<u32>(),
                            name_str[6..8].parse::<u32>()
                        ) {
                            tiles.push((x, y));
                        }
                    }
                }
            }
        }
        
        tiles
    }
}
```

---

## 6. Project Structure

```
ameisen-nav-rs/
├── Cargo.toml                    # Workspace root
├── config.toml                   # Server configuration
├── mmaps/                        # TrinityCore mmap files (not in repo)
│
├── crates/
│   ├── detour-sys/              # Raw FFI bindings
│   │   ├── Cargo.toml
│   │   ├── build.rs             # cc + bindgen build script
│   │   ├── wrapper.h            # C wrapper header
│   │   ├── wrapper.cpp          # C wrapper implementation
│   │   ├── src/
│   │   │   └── lib.rs           # Re-export generated bindings
│   │   └── recastnavigation/    # Git submodule
│   │       └── Detour/
│   │           ├── Include/
│   │           └── Source/
│   │
│   ├── detour/                  # Safe Rust wrappers
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── mesh.rs          # NavMesh wrapper
│   │       ├── query.rs         # NavMeshQuery wrapper
│   │       ├── filter.rs        # QueryFilter wrapper
│   │       ├── status.rs        # Status code handling
│   │       └── types.rs         # Vec3, PolyRef, etc.
│   │
│   ├── tc-mmap/                 # TrinityCore format loader
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── format.rs        # File format structs
│   │       ├── loader.rs        # MmapLoader implementation
│   │       ├── manager.rs       # Multi-map manager
│   │       └── error.rs         # Error types
│   │
│   └── path-smoothing/          # Pure Rust smoothing algorithms
│       ├── Cargo.toml
│       └── src/
│           ├── lib.rs
│           ├── chaikin.rs
│           ├── catmull_rom.rs
│           └── bezier.rs
│
└── src/                         # HTTP server
    ├── main.rs                  # Entry point
    ├── config.rs                # Configuration loading
    ├── state.rs                 # AppState definition
    ├── error.rs                 # Error handling
    └── routes/
        ├── mod.rs
        ├── pathfinding.rs       # /path endpoints
        ├── spatial.rs           # /random-point, /raycast
        └── health.rs            # /health endpoint
```

---

## 7. Implementation Details

### Safe Rust Wrapper (detour crate)

```rust
// crates/detour/src/mesh.rs

use std::ptr::NonNull;
use detour_sys::*;
use crate::error::DetourError;
use crate::types::Vec3;

/// Safe wrapper around dtNavMesh
pub struct NavMesh {
    inner: NonNull<dtNavMesh>,
}

// NavMesh is read-only after initialization, safe to share
unsafe impl Send for NavMesh {}
unsafe impl Sync for NavMesh {}

impl NavMesh {
    /// Create a new empty NavMesh
    pub fn new() -> Result<Self, DetourError> {
        let ptr = unsafe { wrapper_dtAllocNavMesh() };
        NonNull::new(ptr)
            .map(|inner| Self { inner })
            .ok_or(DetourError::AllocationFailed)
    }

    /// Initialize the navmesh with parameters
    pub fn init(&mut self, params: &NavMeshParams) -> Result<(), DetourError> {
        let status = unsafe {
            wrapper_dtNavMesh_init(self.inner.as_ptr(), params.as_raw())
        };
        
        if dtStatusSucceed(status) {
            Ok(())
        } else {
            Err(DetourError::from_status(status))
        }
    }

    /// Add a tile to the navmesh
    /// 
    /// # Safety
    /// If `flags` includes DT_TILE_FREE_DATA, the navmesh takes ownership
    /// of the data and will free it when the tile is removed.
    pub fn add_tile(
        &mut self,
        data: Vec<u8>,
        flags: TileFlags,
    ) -> Result<TileRef, DetourError> {
        let mut tile_ref: dtTileRef = 0;
        let data_len = data.len() as i32;
        
        // If DT_TILE_FREE_DATA is set, we need to leak the memory
        // so Detour can manage it
        let data_ptr = if flags.contains(TileFlags::FREE_DATA) {
            let boxed = data.into_boxed_slice();
            Box::into_raw(boxed) as *mut u8
        } else {
            // Otherwise, make a copy that Detour won't free
            let mut owned = data;
            owned.as_mut_ptr()
        };
        
        let status = unsafe {
            wrapper_dtNavMesh_addTile(
                self.inner.as_ptr(),
                data_ptr,
                data_len,
                flags.bits() as i32,
                0,
                &mut tile_ref,
            )
        };
        
        if dtStatusSucceed(status) {
            Ok(TileRef(tile_ref))
        } else {
            // If we leaked memory and failed, we need to reclaim it
            if flags.contains(TileFlags::FREE_DATA) {
                unsafe {
                    let _ = Box::from_raw(std::slice::from_raw_parts_mut(
                        data_ptr,
                        data_len as usize
                    ));
                }
            }
            Err(DetourError::from_status(status))
        }
    }

    /// Get the navmesh parameters
    pub fn params(&self) -> &NavMeshParams {
        unsafe {
            let params = wrapper_dtNavMesh_getParams(self.inner.as_ptr());
            &*(params as *const NavMeshParams)
        }
    }

    /// Get raw pointer for query initialization
    pub(crate) fn as_raw(&self) -> *const dtNavMesh {
        self.inner.as_ptr()
    }
}

impl Drop for NavMesh {
    fn drop(&mut self) {
        unsafe {
            wrapper_dtFreeNavMesh(self.inner.as_ptr());
        }
    }
}
```

```rust
// crates/detour/src/query.rs

use std::ptr::NonNull;
use detour_sys::*;
use crate::error::DetourError;
use crate::filter::QueryFilter;
use crate::mesh::NavMesh;
use crate::types::{Vec3, PolyRef};

/// Maximum path length for queries
pub const MAX_PATH_LENGTH: usize = 256;
pub const MAX_SMOOTH_PATH_LENGTH: usize = 2048;

/// Safe wrapper around dtNavMeshQuery
/// 
/// # Thread Safety
/// dtNavMeshQuery is NOT thread-safe. Each thread needs its own query instance.
pub struct NavMeshQuery {
    inner: NonNull<dtNavMeshQuery>,
}

// NOT Send/Sync - each thread needs its own instance
// If needed, wrap in Mutex or use a pool

impl NavMeshQuery {
    /// Create a new query for the given navmesh
    pub fn new(mesh: &NavMesh, max_nodes: i32) -> Result<Self, DetourError> {
        let ptr = unsafe { wrapper_dtAllocNavMeshQuery() };
        let inner = NonNull::new(ptr).ok_or(DetourError::AllocationFailed)?;
        
        let status = unsafe {
            wrapper_dtNavMeshQuery_init(ptr, mesh.as_raw(), max_nodes)
        };
        
        if dtStatusSucceed(status) {
            Ok(Self { inner })
        } else {
            unsafe { wrapper_dtFreeNavMeshQuery(ptr); }
            Err(DetourError::from_status(status))
        }
    }

    /// Find a path between two points
    pub fn find_path(
        &self,
        start: Vec3,
        end: Vec3,
        filter: &QueryFilter,
        half_extents: Vec3,
    ) -> Result<Vec<Vec3>, DetourError> {
        // Find start polygon
        let start_ref = self.find_nearest_poly(start, half_extents, filter)?;
        let end_ref = self.find_nearest_poly(end, half_extents, filter)?;
        
        // Find path corridor
        let mut path = vec![0u32; MAX_PATH_LENGTH];
        let mut path_count = 0i32;
        
        let status = unsafe {
            wrapper_dtNavMeshQuery_findPath(
                self.inner.as_ptr(),
                start_ref.0,
                end_ref.0,
                start.as_ptr(),
                end.as_ptr(),
                filter.as_raw(),
                path.as_mut_ptr(),
                &mut path_count,
                MAX_PATH_LENGTH as i32,
            )
        };
        
        if !dtStatusSucceed(status) {
            return Err(DetourError::from_status(status));
        }
        
        // Convert to straight path
        let mut straight_path = vec![0f32; MAX_SMOOTH_PATH_LENGTH * 3];
        let mut straight_path_flags = vec![0u8; MAX_SMOOTH_PATH_LENGTH];
        let mut straight_path_refs = vec![0u32; MAX_SMOOTH_PATH_LENGTH];
        let mut straight_path_count = 0i32;
        
        let status = unsafe {
            wrapper_dtNavMeshQuery_findStraightPath(
                self.inner.as_ptr(),
                start.as_ptr(),
                end.as_ptr(),
                path.as_ptr(),
                path_count,
                straight_path.as_mut_ptr(),
                straight_path_flags.as_mut_ptr(),
                straight_path_refs.as_mut_ptr(),
                &mut straight_path_count,
                MAX_SMOOTH_PATH_LENGTH as i32,
                0, // options
            )
        };
        
        if !dtStatusSucceed(status) {
            return Err(DetourError::from_status(status));
        }
        
        // Convert to Vec<Vec3>
        let result: Vec<Vec3> = (0..straight_path_count as usize)
            .map(|i| Vec3::new(
                straight_path[i * 3],
                straight_path[i * 3 + 1],
                straight_path[i * 3 + 2],
            ))
            .collect();
        
        Ok(result)
    }

    /// Find nearest polygon to a point
    pub fn find_nearest_poly(
        &self,
        center: Vec3,
        half_extents: Vec3,
        filter: &QueryFilter,
    ) -> Result<PolyRef, DetourError> {
        let mut nearest_ref = 0u32;
        let mut nearest_pt = [0f32; 3];
        
        let status = unsafe {
            wrapper_dtNavMeshQuery_findNearestPoly(
                self.inner.as_ptr(),
                center.as_ptr(),
                half_extents.as_ptr(),
                filter.as_raw(),
                &mut nearest_ref,
                nearest_pt.as_mut_ptr(),
            )
        };
        
        if dtStatusSucceed(status) && nearest_ref != 0 {
            Ok(PolyRef(nearest_ref))
        } else {
            Err(DetourError::from_status(status))
        }
    }

    /// Move along navmesh surface
    pub fn move_along_surface(
        &self,
        start_ref: PolyRef,
        start: Vec3,
        end: Vec3,
        filter: &QueryFilter,
    ) -> Result<Vec3, DetourError> {
        let mut result_pos = [0f32; 3];
        let mut visited = vec![0u32; 16];
        let mut visited_count = 0i32;
        
        let status = unsafe {
            wrapper_dtNavMeshQuery_moveAlongSurface(
                self.inner.as_ptr(),
                start_ref.0,
                start.as_ptr(),
                end.as_ptr(),
                filter.as_raw(),
                result_pos.as_mut_ptr(),
                visited.as_mut_ptr(),
                &mut visited_count,
                16,
            )
        };
        
        if dtStatusSucceed(status) {
            Ok(Vec3::from_array(result_pos))
        } else {
            Err(DetourError::from_status(status))
        }
    }

    /// Raycast on navmesh
    pub fn raycast(
        &self,
        start_ref: PolyRef,
        start: Vec3,
        end: Vec3,
        filter: &QueryFilter,
    ) -> Result<RaycastResult, DetourError> {
        let mut t = 0f32;
        let mut hit_normal = [0f32; 3];
        let mut path = vec![0u32; MAX_PATH_LENGTH];
        let mut path_count = 0i32;
        
        let status = unsafe {
            wrapper_dtNavMeshQuery_raycast(
                self.inner.as_ptr(),
                start_ref.0,
                start.as_ptr(),
                end.as_ptr(),
                filter.as_raw(),
                &mut t,
                hit_normal.as_mut_ptr(),
                path.as_mut_ptr(),
                &mut path_count,
                MAX_PATH_LENGTH as i32,
            )
        };
        
        if dtStatusSucceed(status) {
            Ok(RaycastResult {
                t,
                hit_normal: Vec3::from_array(hit_normal),
                hit: t < 1.0,
            })
        } else {
            Err(DetourError::from_status(status))
        }
    }

    /// Find random point on navmesh
    pub fn find_random_point(&self, filter: &QueryFilter) -> Result<Vec3, DetourError> {
        let mut random_ref = 0u32;
        let mut random_pt = [0f32; 3];
        
        let status = unsafe {
            wrapper_dtNavMeshQuery_findRandomPoint(
                self.inner.as_ptr(),
                filter.as_raw(),
                &mut random_ref,
                random_pt.as_mut_ptr(),
            )
        };
        
        if dtStatusSucceed(status) {
            Ok(Vec3::from_array(random_pt))
        } else {
            Err(DetourError::from_status(status))
        }
    }

    /// Find random point within radius
    pub fn find_random_point_around(
        &self,
        center: Vec3,
        radius: f32,
        filter: &QueryFilter,
        half_extents: Vec3,
    ) -> Result<Vec3, DetourError> {
        let start_ref = self.find_nearest_poly(center, half_extents, filter)?;
        
        let mut random_ref = 0u32;
        let mut random_pt = [0f32; 3];
        
        let status = unsafe {
            wrapper_dtNavMeshQuery_findRandomPointAroundCircle(
                self.inner.as_ptr(),
                start_ref.0,
                center.as_ptr(),
                radius,
                filter.as_raw(),
                &mut random_ref,
                random_pt.as_mut_ptr(),
            )
        };
        
        if dtStatusSucceed(status) {
            Ok(Vec3::from_array(random_pt))
        } else {
            Err(DetourError::from_status(status))
        }
    }
}

impl Drop for NavMeshQuery {
    fn drop(&mut self) {
        unsafe {
            wrapper_dtFreeNavMeshQuery(self.inner.as_ptr());
        }
    }
}

pub struct RaycastResult {
    pub t: f32,
    pub hit_normal: Vec3,
    pub hit: bool,
}
```

### Path Smoothing (Pure Rust)

```rust
// crates/path-smoothing/src/chaikin.rs

use crate::Vec3;

/// Chaikin curve subdivision - smooths paths by cutting corners
pub fn smooth_chaikin(path: &[Vec3], iterations: usize) -> Vec<Vec3> {
    if path.len() < 2 {
        return path.to_vec();
    }
    
    let mut result = path.to_vec();
    
    for _ in 0..iterations {
        let mut smoothed = Vec::with_capacity(result.len() * 2);
        smoothed.push(result[0]);
        
        for window in result.windows(2) {
            let p0 = window[0];
            let p1 = window[1];
            
            // Q = 3/4 * P0 + 1/4 * P1
            smoothed.push(Vec3::new(
                p0.x * 0.75 + p1.x * 0.25,
                p0.y * 0.75 + p1.y * 0.25,
                p0.z * 0.75 + p1.z * 0.25,
            ));
            
            // R = 1/4 * P0 + 3/4 * P1
            smoothed.push(Vec3::new(
                p0.x * 0.25 + p1.x * 0.75,
                p0.y * 0.25 + p1.y * 0.75,
                p0.z * 0.25 + p1.z * 0.75,
            ));
        }
        
        smoothed.push(*result.last().unwrap());
        result = smoothed;
    }
    
    result
}
```

```rust
// crates/path-smoothing/src/catmull_rom.rs

use crate::Vec3;

/// Catmull-Rom spline interpolation
pub fn smooth_catmull_rom(path: &[Vec3], segments_per_span: usize) -> Vec<Vec3> {
    if path.len() < 4 {
        return path.to_vec();
    }
    
    let mut result = Vec::new();
    
    for i in 0..path.len().saturating_sub(3) {
        let p0 = path[i];
        let p1 = path[i + 1];
        let p2 = path[i + 2];
        let p3 = path[i + 3];
        
        for j in 0..segments_per_span {
            let t = j as f32 / segments_per_span as f32;
            result.push(catmull_rom_point(p0, p1, p2, p3, t));
        }
    }
    
    // Add final point
    if let Some(last) = path.last() {
        result.push(*last);
    }
    
    result
}

fn catmull_rom_point(p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3, t: f32) -> Vec3 {
    let t2 = t * t;
    let t3 = t2 * t;
    
    let c0 = -0.5 * t3 + t2 - 0.5 * t;
    let c1 = 1.5 * t3 - 2.5 * t2 + 1.0;
    let c2 = -1.5 * t3 + 2.0 * t2 + 0.5 * t;
    let c3 = 0.5 * t3 - 0.5 * t2;
    
    Vec3::new(
        p0.x * c0 + p1.x * c1 + p2.x * c2 + p3.x * c3,
        p0.y * c0 + p1.y * c1 + p2.y * c2 + p3.y * c3,
        p0.z * c0 + p1.z * c1 + p2.z * c2 + p3.z * c3,
    )
}
```

---

## 8. HTTP Service Architecture

### API Endpoints

Since Sylvannas only supports `core.http_get`, all endpoints use GET with query parameters:

| Endpoint | Parameters | Description |
|----------|-----------|-------------|
| `GET /api/v1/path` | map_id, start_x/y/z, end_x/y/z, smoothing | Find path between points |
| `GET /api/v1/move` | map_id, start_x/y/z, end_x/y/z | Move along surface |
| `GET /api/v1/raycast` | map_id, start_x/y/z, end_x/y/z | Line-of-sight check |
| `GET /api/v1/random` | map_id | Random point on navmesh |
| `GET /api/v1/random-circle` | map_id, center_x/y/z, radius | Random point in radius |
| `GET /api/v1/height` | map_id, x, y, z | Get height at position |
| `GET /health` | - | Health check |

### Request/Response Formats

```rust
// Request via query params: /api/v1/path?map_id=0&start_x=100&start_y=200&...

// Response JSON
#[derive(Serialize)]
pub struct PathResponse {
    pub success: bool,
    pub path: Option<Vec<[f32; 3]>>,
    pub distance: Option<f32>,
    pub compute_time_ms: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Serialize)]
pub struct RaycastResponse {
    pub success: bool,
    pub hit: bool,
    pub t: f32,
    pub hit_point: Option<[f32; 3]>,
    pub hit_normal: Option<[f32; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Serialize)]  
pub struct RandomPointResponse {
    pub success: bool,
    pub point: Option<[f32; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}
```

### Axum Route Implementation

```rust
// src/routes/pathfinding.rs

use axum::{
    extract::{Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Instant;

use crate::state::AppState;
use crate::error::AppError;

#[derive(Deserialize)]
pub struct PathQuery {
    pub map_id: u32,
    pub start_x: f32,
    pub start_y: f32,
    pub start_z: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub end_z: f32,
    #[serde(default)]
    pub smoothing: Smoothing,
}

#[derive(Deserialize, Default, Clone, Copy)]
#[serde(rename_all = "snake_case")]
pub enum Smoothing {
    #[default]
    None,
    Chaikin,
    CatmullRom,
    Bezier,
}

#[derive(Serialize)]
pub struct PathResponse {
    pub success: bool,
    pub path: Option<Vec<[f32; 3]>>,
    pub distance: Option<f32>,
    pub compute_time_ms: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

pub async fn find_path(
    State(state): State<Arc<AppState>>,
    Query(params): Query<PathQuery>,
) -> Result<Json<PathResponse>, AppError> {
    let start_time = Instant::now();
    
    let start = Vec3::new(params.start_x, params.start_y, params.start_z);
    let end = Vec3::new(params.end_x, params.end_y, params.end_z);
    
    // Ensure map and tiles are loaded
    state.ensure_tiles_for_path(params.map_id, start, end).await?;
    
    // Offload CPU-bound pathfinding to blocking thread pool
    let state_clone = state.clone();
    let smoothing = params.smoothing;
    
    let result = tokio::task::spawn_blocking(move || {
        let pathfinder = state_clone.get_pathfinder(params.map_id)?;
        
        // Find raw path
        let raw_path = pathfinder.find_path(start, end)?;
        
        // Apply smoothing
        let smoothed = match smoothing {
            Smoothing::None => raw_path,
            Smoothing::Chaikin => path_smoothing::chaikin::smooth_chaikin(&raw_path, 2),
            Smoothing::CatmullRom => path_smoothing::catmull_rom::smooth_catmull_rom(&raw_path, 10),
            Smoothing::Bezier => path_smoothing::bezier::smooth_bezier(&raw_path, 10),
        };
        
        Ok::<_, AppError>(smoothed)
    }).await??;
    
    let path: Vec<[f32; 3]> = result.iter()
        .map(|v| [v.x, v.y, v.z])
        .collect();
    
    let distance = calculate_path_distance(&result);
    
    Ok(Json(PathResponse {
        success: true,
        path: Some(path),
        distance: Some(distance),
        compute_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
        error: None,
    }))
}

fn calculate_path_distance(path: &[Vec3]) -> f32 {
    path.windows(2)
        .map(|w| w[0].distance(w[1]))
        .sum()
}
```

### AppState with Query Pool

```rust
// src/state.rs

use std::sync::Arc;
use dashmap::DashMap;
use parking_lot::Mutex;
use tokio::sync::Semaphore;

use detour::{NavMesh, NavMeshQuery, QueryFilter};
use tc_mmap::MmapLoader;

pub struct AppState {
    pub mmap_loader: MmapLoader,
    pub navmeshes: DashMap<u32, Arc<NavMesh>>,
    pub query_pools: DashMap<u32, QueryPool>,
    pub pathfinding_semaphore: Arc<Semaphore>,
    pub config: Config,
}

/// Pool of NavMeshQuery instances for a single map
/// (dtNavMeshQuery is not thread-safe)
pub struct QueryPool {
    mesh: Arc<NavMesh>,
    queries: Mutex<Vec<NavMeshQuery>>,
    filter: Arc<QueryFilter>,
}

impl QueryPool {
    pub fn new(mesh: Arc<NavMesh>, initial_size: usize) -> Result<Self, DetourError> {
        let mut queries = Vec::with_capacity(initial_size);
        for _ in 0..initial_size {
            queries.push(NavMeshQuery::new(&mesh, 2048)?);
        }
        
        let filter = Arc::new(QueryFilter::default());
        
        Ok(Self {
            mesh,
            queries: Mutex::new(queries),
            filter,
        })
    }
    
    pub fn acquire(&self) -> PooledQuery {
        let query = {
            let mut pool = self.queries.lock();
            pool.pop()
        }.unwrap_or_else(|| {
            NavMeshQuery::new(&self.mesh, 2048)
                .expect("Failed to create NavMeshQuery")
        });
        
        PooledQuery {
            query: Some(query),
            pool: self,
            filter: self.filter.clone(),
        }
    }
    
    fn release(&self, query: NavMeshQuery) {
        self.queries.lock().push(query);
    }
}

pub struct PooledQuery<'a> {
    query: Option<NavMeshQuery>,
    pool: &'a QueryPool,
    filter: Arc<QueryFilter>,
}

impl<'a> PooledQuery<'a> {
    pub fn find_path(&self, start: Vec3, end: Vec3) -> Result<Vec<Vec3>, DetourError> {
        let half_extents = Vec3::new(2.5, 5.0, 2.5);
        self.query.as_ref().unwrap().find_path(start, end, &self.filter, half_extents)
    }
    
    // ... other query methods
}

impl<'a> Drop for PooledQuery<'a> {
    fn drop(&mut self) {
        if let Some(query) = self.query.take() {
            self.pool.release(query);
        }
    }
}
```

---

## 9. Client Integration (Sylvannas API)

Since Sylvannas only provides `core.http_get`, the Lua client uses GET requests with query parameters:

```lua
-- navigation_client.lua
local NavigationClient = {}
NavigationClient.__index = NavigationClient

local json = require("common/utility/json") -- Assuming json library available

function NavigationClient:new(base_url)
    local self = setmetatable({}, NavigationClient)
    self.base_url = base_url or "http://localhost:3000"
    self.pending_requests = {}
    return self
end

function NavigationClient:find_path(map_id, start_pos, end_pos, smoothing, callback)
    local url = string.format(
        "%s/api/v1/path?map_id=%d&start_x=%.2f&start_y=%.2f&start_z=%.2f&end_x=%.2f&end_y=%.2f&end_z=%.2f&smoothing=%s",
        self.base_url,
        map_id,
        start_pos.x, start_pos.y, start_pos.z,
        end_pos.x, end_pos.y, end_pos.z,
        smoothing or "none"
    )
    
    core.http_get(url, function(http_code, content_type, response_data, headers)
        if http_code ~= 200 then
            callback(nil, "HTTP error: " .. tostring(http_code))
            return
        end
        
        local success, result = pcall(json.decode, response_data)
        if not success then
            callback(nil, "JSON parse error")
            return
        end
        
        if result.success and result.path then
            -- Convert path array to vec3 table
            local path = {}
            for i, point in ipairs(result.path) do
                path[i] = vec3.new(point[1], point[2], point[3])
            end
            callback(path, nil, result.distance, result.compute_time_ms)
        else
            callback(nil, result.error or "Unknown error")
        end
    end)
end

function NavigationClient:raycast(map_id, start_pos, end_pos, callback)
    local url = string.format(
        "%s/api/v1/raycast?map_id=%d&start_x=%.2f&start_y=%.2f&start_z=%.2f&end_x=%.2f&end_y=%.2f&end_z=%.2f",
        self.base_url,
        map_id,
        start_pos.x, start_pos.y, start_pos.z,
        end_pos.x, end_pos.y, end_pos.z
    )
    
    core.http_get(url, function(http_code, content_type, response_data, headers)
        if http_code ~= 200 then
            callback(nil, "HTTP error: " .. tostring(http_code))
            return
        end
        
        local success, result = pcall(json.decode, response_data)
        if not success then
            callback(nil, "JSON parse error")
            return
        end
        
        if result.success then
            callback({
                hit = result.hit,
                t = result.t,
                hit_point = result.hit_point and vec3.new(result.hit_point[1], result.hit_point[2], result.hit_point[3]),
                hit_normal = result.hit_normal and vec3.new(result.hit_normal[1], result.hit_normal[2], result.hit_normal[3]),
            }, nil)
        else
            callback(nil, result.error or "Unknown error")
        end
    end)
end

function NavigationClient:random_point(map_id, callback)
    local url = string.format("%s/api/v1/random?map_id=%d", self.base_url, map_id)
    
    core.http_get(url, function(http_code, content_type, response_data, headers)
        if http_code ~= 200 then
            callback(nil, "HTTP error: " .. tostring(http_code))
            return
        end
        
        local success, result = pcall(json.decode, response_data)
        if not success then
            callback(nil, "JSON parse error")
            return
        end
        
        if result.success and result.point then
            callback(vec3.new(result.point[1], result.point[2], result.point[3]), nil)
        else
            callback(nil, result.error or "Unknown error")
        end
    end)
end

function NavigationClient:random_point_around(map_id, center, radius, callback)
    local url = string.format(
        "%s/api/v1/random-circle?map_id=%d&center_x=%.2f&center_y=%.2f&center_z=%.2f&radius=%.2f",
        self.base_url,
        map_id,
        center.x, center.y, center.z,
        radius
    )
    
    core.http_get(url, function(http_code, content_type, response_data, headers)
        if http_code ~= 200 then
            callback(nil, "HTTP error: " .. tostring(http_code))
            return
        end
        
        local success, result = pcall(json.decode, response_data)
        if not success then
            callback(nil, "JSON parse error")
            return
        end
        
        if result.success and result.point then
            callback(vec3.new(result.point[1], result.point[2], result.point[3]), nil)
        else
            callback(nil, result.error or "Unknown error")
        end
    end)
end

return NavigationClient
```

Usage example:

```lua
local NavigationClient = require("navigation_client")
local nav = NavigationClient:new("http://localhost:3000")

-- Get current map and position
local map_id = core.get_map_id()
local player = core.object_manager.get_local_player()
local player_pos = player:get_position()

-- Find path to target
local target_pos = vec3.new(1000, 2000, 100)
nav:find_path(map_id, player_pos, target_pos, "catmull_rom", function(path, error, distance)
    if error then
        core.log_error("Navigation error: " .. error)
        return
    end
    
    core.log("Found path with " .. #path .. " waypoints, distance: " .. distance)
    
    -- Use simple_movement to follow path
    local movement = require("common/utility/simple_movement")
    movement:navigate(path)
end)
```

---

## 10. Build System

### Workspace Cargo.toml

```toml
# Cargo.toml
[workspace]
members = ["crates/*"]
resolver = "2"

[workspace.package]
version = "0.1.0"
edition = "2021"
rust-version = "1.75"
license = "GPL-3.0"

[workspace.dependencies]
# Internal crates
detour-sys = { path = "crates/detour-sys" }
detour = { path = "crates/detour" }
tc-mmap = { path = "crates/tc-mmap" }
path-smoothing = { path = "crates/path-smoothing" }

# Async runtime
tokio = { version = "1.35", features = ["full"] }

# HTTP server
axum = "0.7"
tower-http = { version = "0.5", features = ["trace", "compression-gzip", "timeout"] }

# Serialization
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

# Concurrency
dashmap = "5.5"
parking_lot = "0.12"
rayon = "1.8"

# Error handling
thiserror = "1.0"
anyhow = "1.0"

# File handling
memmap2 = "0.9"
bytemuck = { version = "1.14", features = ["derive"] }

# Logging
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# Config
toml = "0.8"

[profile.release]
lto = true
codegen-units = 1
opt-level = 3
```

### detour-sys Cargo.toml

```toml
# crates/detour-sys/Cargo.toml
[package]
name = "detour-sys"
version.workspace = true
edition.workspace = true

[lib]
name = "detour_sys"
path = "src/lib.rs"

[build-dependencies]
cc = { version = "1.0", features = ["parallel"] }
bindgen = "0.69"
```

### Server Cargo.toml

```toml
# Cargo.toml (root - the HTTP server)
[package]
name = "ameisen-nav-server"
version.workspace = true
edition.workspace = true

[[bin]]
name = "nav-server"
path = "src/main.rs"

[dependencies]
detour.workspace = true
tc-mmap.workspace = true
path-smoothing.workspace = true

tokio.workspace = true
axum.workspace = true
tower-http.workspace = true

serde.workspace = true
serde_json.workspace = true

dashmap.workspace = true
parking_lot.workspace = true

thiserror.workspace = true
anyhow.workspace = true

tracing.workspace = true
tracing-subscriber.workspace = true

toml.workspace = true
```

---

## 11. Implementation Roadmap

### Phase 1: FFI Foundation (Week 1-2)

1. Clone recastnavigation as git submodule
2. Create `wrapper.h` and `wrapper.cpp` with C wrappers
3. Set up `build.rs` with cc + bindgen
4. Verify bindings compile and link correctly
5. Write basic allocation/deallocation tests

**Deliverables:**
- `detour-sys` crate compiling successfully
- Basic sanity tests passing

### Phase 2: Safe Wrappers (Week 2-3)

1. Implement `NavMesh` wrapper with RAII
2. Implement `NavMeshQuery` wrapper
3. Implement `QueryFilter` wrapper
4. Add error types and status code handling
5. Write unit tests for each wrapper

**Deliverables:**
- `detour` crate with safe API
- Comprehensive test coverage

### Phase 3: TrinityCore Loader (Week 3-4)

1. Implement mmap/mmtile file format parsing
2. Build `MmapLoader` with lazy tile loading
3. Implement multi-map manager
4. Add tile coordinate calculation helpers
5. Test with real TrinityCore mmap files

**Deliverables:**
- `tc-mmap` crate loading real navmesh data
- Integration tests with TC mmaps

### Phase 4: HTTP Service (Week 4-5)

1. Set up Axum router with endpoints
2. Implement `AppState` with query pool
3. Add pathfinding endpoint with smoothing
4. Add raycast, random point endpoints
5. Implement concurrent request handling

**Deliverables:**
- Working HTTP server
- All endpoints functional

### Phase 5: Path Smoothing (Week 5)

1. Implement Chaikin algorithm
2. Implement Catmull-Rom splines
3. Implement Bezier curves
4. Add smoothing parameter to path endpoint
5. Performance testing

**Deliverables:**
- `path-smoothing` crate
- Smooth paths comparable to AmeisenNavigation

### Phase 6: Production Hardening (Week 6)

1. Add comprehensive logging
2. Implement graceful shutdown
3. Add configuration file support
4. Performance optimization
5. Docker containerization

**Deliverables:**
- Production-ready server
- Docker image
- Documentation

---

## 12. Testing Strategy

### Unit Tests

```rust
// crates/detour/src/tests.rs

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_navmesh_allocation() {
        let mesh = NavMesh::new().expect("Failed to allocate NavMesh");
        // Mesh should be valid but uninitialized
    }
    
    #[test]
    fn test_navmesh_init() {
        let mut mesh = NavMesh::new().unwrap();
        let params = NavMeshParams {
            orig: [-17066.666, 0.0, -17066.666],
            tile_width: 533.333,
            tile_height: 533.333,
            max_tiles: 2048,
            max_polys: 1 << 20,
        };
        mesh.init(&params).expect("Failed to init NavMesh");
    }
}
```

### Integration Tests

```rust
// tests/integration_test.rs

use std::path::PathBuf;

#[test]
fn test_load_real_mmaps() {
    let mmap_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("test_data/mmaps");
    
    if !mmap_path.exists() {
        eprintln!("Skipping test: no mmap data at {:?}", mmap_path);
        return;
    }
    
    let loader = tc_mmap::MmapLoader::new(&mmap_path);
    
    // Load Eastern Kingdoms
    let params = loader.load_map_params(0).expect("Failed to load map 0 params");
    assert!(params.max_tiles > 0);
    
    // Load a specific tile
    let (tile_data, uses_liquids) = loader.load_tile(0, 32, 32)
        .expect("Failed to load tile");
    assert!(!tile_data.is_empty());
}

#[test]
fn test_pathfinding_eastern_kingdoms() {
    // Initialize navmesh with real data
    let loader = tc_mmap::MmapLoader::new("test_data/mmaps");
    let params = loader.load_map_params(0).unwrap();
    
    let mut mesh = NavMesh::new().unwrap();
    mesh.init(&params).unwrap();
    
    // Load necessary tiles for path
    let (tile_data, _) = loader.load_tile(0, 32, 32).unwrap();
    mesh.add_tile(tile_data, TileFlags::FREE_DATA).unwrap();
    
    // Create query
    let query = NavMeshQuery::new(&mesh, 2048).unwrap();
    let filter = QueryFilter::default();
    
    // Find path (Stormwind area coordinates)
    let start = Vec3::new(-8913.0, -132.0, 80.0);
    let end = Vec3::new(-8850.0, -100.0, 81.0);
    
    let path = query.find_path(start, end, &filter, Vec3::new(2.5, 5.0, 2.5))
        .expect("Pathfinding failed");
    
    assert!(!path.is_empty());
    assert!(path.len() >= 2);
}
```

### Benchmark Tests

```rust
// benches/pathfinding.rs

use criterion::{criterion_group, criterion_main, Criterion};

fn benchmark_pathfinding(c: &mut Criterion) {
    // Setup navmesh...
    
    c.bench_function("short_path_50m", |b| {
        b.iter(|| {
            query.find_path(start, end, &filter, half_extents)
        })
    });
    
    c.bench_function("medium_path_200m", |b| {
        // ...
    });
    
    c.bench_function("long_path_500m", |b| {
        // ...
    });
}

criterion_group!(benches, benchmark_pathfinding);
criterion_main!(benches);
```

### Performance Targets

| Operation | Target Latency | Notes |
|-----------|---------------|-------|
| Short path (<50m) | <1ms | Common in dungeons |
| Medium path (50-200m) | 1-5ms | Typical questing |
| Long path (200m+) | 5-20ms | Cross-zone travel |
| Tile load | <10ms | Lazy loading overhead |
| Map preload (dungeon) | <100ms | 10-50 tiles |
| Map preload (continent) | <2s | Parallel loading |

---

## Summary

This plan provides a complete blueprint for rewriting AmeisenNavigation in Rust with:

1. **Custom FFI bindings** via bindgen with C wrapper functions for C++ class methods
2. **Safe Rust wrappers** with RAII semantics and proper memory management
3. **TrinityCore mmap compatibility** with exact file format parsing
4. **HTTP service** using Axum with query parameter-based API (compatible with `core.http_get`)
5. **Thread-safe design** with query pools for concurrent pathfinding
6. **Pure Rust path smoothing** algorithms matching AmeisenNavigation functionality

The modular crate structure allows independent testing and development of each component, while the HTTP interface ensures seamless integration with your existing Sylvannas bot architecture.