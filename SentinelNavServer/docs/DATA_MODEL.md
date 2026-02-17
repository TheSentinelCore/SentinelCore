# Data Model Document

## AmeisenNav-RS Data Structures and Formats

**Version:** 1.0.0  
**Last Updated:** 2026-02-02

---

## 1. Overview

This document describes all data structures used in AmeisenNav-RS, including internal Rust types, FFI types from Recast/Detour, file formats, and API data transfer objects.

---

## 2. Core Geometry Types

### 2.1 Vec3

A 3D vector representing world positions and directions.

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Vec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Vec3 {
    pub const ZERO: Vec3 = Vec3 { x: 0.0, y: 0.0, z: 0.0 };

    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }

    pub fn from_array(arr: [f32; 3]) -> Self {
        Self { x: arr[0], y: arr[1], z: arr[2] }
    }

    pub fn as_ptr(&self) -> *const f32 {
        &self.x as *const f32
    }

    pub fn distance(&self, other: &Vec3) -> f32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        let dz = self.z - other.z;
        (dx * dx + dy * dy + dz * dz).sqrt()
    }

    pub fn distance_2d(&self, other: &Vec3) -> f32 {
        let dx = self.x - other.x;
        let dz = self.z - other.z;
        (dx * dx + dz * dz).sqrt()
    }

    pub fn length(&self) -> f32 {
        (self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
    }

    pub fn normalize(&self) -> Vec3 {
        let len = self.length();
        if len > 0.0 {
            Vec3::new(self.x / len, self.y / len, self.z / len)
        } else {
            Vec3::ZERO
        }
    }
}

impl std::ops::Add for Vec3 {
    type Output = Vec3;
    fn add(self, rhs: Vec3) -> Vec3 {
        Vec3::new(self.x + rhs.x, self.y + rhs.y, self.z + rhs.z)
    }
}

impl std::ops::Sub for Vec3 {
    type Output = Vec3;
    fn sub(self, rhs: Vec3) -> Vec3 {
        Vec3::new(self.x - rhs.x, self.y - rhs.y, self.z - rhs.z)
    }
}

impl std::ops::Mul<f32> for Vec3 {
    type Output = Vec3;
    fn mul(self, rhs: f32) -> Vec3 {
        Vec3::new(self.x * rhs, self.y * rhs, self.z * rhs)
    }
}
```

### 2.2 BoundingBox

Axis-aligned bounding box for spatial queries.

```rust
#[derive(Debug, Clone, Copy)]
pub struct BoundingBox {
    pub min: Vec3,
    pub max: Vec3,
}

impl BoundingBox {
    pub fn new(min: Vec3, max: Vec3) -> Self {
        Self { min, max }
    }

    pub fn contains(&self, point: &Vec3) -> bool {
        point.x >= self.min.x && point.x <= self.max.x &&
        point.y >= self.min.y && point.y <= self.max.y &&
        point.z >= self.min.z && point.z <= self.max.z
    }

    pub fn center(&self) -> Vec3 {
        Vec3::new(
            (self.min.x + self.max.x) / 2.0,
            (self.min.y + self.max.y) / 2.0,
            (self.min.z + self.max.z) / 2.0,
        )
    }

    pub fn half_extents(&self) -> Vec3 {
        Vec3::new(
            (self.max.x - self.min.x) / 2.0,
            (self.max.y - self.min.y) / 2.0,
            (self.max.z - self.min.z) / 2.0,
        )
    }
}
```

---

## 3. Detour FFI Types

### 3.1 Reference Types

```rust
/// Polygon reference - unique identifier for a polygon in the navmesh
pub type PolyRef = u32;  // u64 with DT_POLYREF64 feature

/// Tile reference - unique identifier for a tile
pub type TileRef = u32;  // u64 with DT_POLYREF64 feature

/// Status code from Detour operations
pub type Status = u32;
```

### 3.2 NavMesh Parameters

```rust
/// Parameters for initializing a navigation mesh
/// Corresponds to dtNavMeshParams in Detour
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct NavMeshParams {
    /// World-space origin of the navigation mesh
    pub orig: [f32; 3],
    
    /// Width of each tile in world units
    pub tile_width: f32,
    
    /// Height of each tile in world units  
    pub tile_height: f32,
    
    /// Maximum number of tiles the mesh can contain
    pub max_tiles: i32,
    
    /// Maximum number of polygons per tile
    pub max_polys: i32,
}

impl NavMeshParams {
    /// Create params for TrinityCore WoW maps
    pub fn wow_default() -> Self {
        Self {
            orig: [0.0, 0.0, 0.0],
            tile_width: 533.33333,   // WoW tile size
            tile_height: 533.33333,
            max_tiles: 64 * 64,      // WoW grid is 64x64
            max_polys: 1 << 22,      // ~4 million polys
        }
    }
}
```

### 3.3 Mesh Header

```rust
/// Header at the start of each navmesh tile
/// Corresponds to dtMeshHeader in Detour
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct MeshHeader {
    /// Magic number: 'D'<<24 | 'N'<<16 | 'A'<<8 | 'V'
    pub magic: i32,
    
    /// Data format version
    pub version: i32,
    
    /// Tile X coordinate
    pub x: i32,
    
    /// Tile Y coordinate  
    pub y: i32,
    
    /// Tile layer (for multi-layer tiles)
    pub layer: i32,
    
    /// User-defined ID
    pub user_id: u32,
    
    /// Number of polygons in tile
    pub poly_count: i32,
    
    /// Number of vertices in tile
    pub vert_count: i32,
    
    /// Maximum number of links
    pub max_link_count: i32,
    
    /// Number of detail meshes
    pub detail_mesh_count: i32,
    
    /// Number of detail vertices
    pub detail_vert_count: i32,
    
    /// Number of detail triangles
    pub detail_tri_count: i32,
    
    /// Number of BVH nodes
    pub bv_node_count: i32,
    
    /// Number of off-mesh connections
    pub off_mesh_con_count: i32,
    
    /// Index of first polygon for off-mesh connections
    pub off_mesh_base: i32,
    
    /// Agent height
    pub walkable_height: f32,
    
    /// Agent radius
    pub walkable_radius: f32,
    
    /// Maximum climb height
    pub walkable_climb: f32,
    
    /// Tile bounds minimum
    pub bmin: [f32; 3],
    
    /// Tile bounds maximum
    pub bmax: [f32; 3],
    
    /// BVH quantization factor
    pub bv_quant_factor: f32,
}

impl MeshHeader {
    pub const MAGIC: i32 = (b'D' as i32) << 24 | (b'N' as i32) << 16 | 
                          (b'A' as i32) << 8 | (b'V' as i32);
    pub const VERSION: i32 = 7;  // DT_NAVMESH_VERSION
}
```

### 3.4 Query Filter

```rust
/// Configuration for pathfinding queries
/// Wraps dtQueryFilter
#[derive(Debug, Clone)]
pub struct QueryFilter {
    /// Flags that must be present on polygons
    pub include_flags: u16,
    
    /// Flags that must NOT be present on polygons
    pub exclude_flags: u16,
    
    /// Cost multiplier for each area type (0-63)
    pub area_costs: [f32; 64],
}

impl Default for QueryFilter {
    fn default() -> Self {
        let mut area_costs = [1.0f32; 64];
        // Common WoW area costs
        area_costs[0] = 1.0;   // Ground
        area_costs[1] = 1.0;   // Road (slightly cheaper)
        area_costs[2] = 10.0;  // Water (expensive)
        area_costs[3] = 100.0; // Lava (very expensive)
        
        Self {
            include_flags: 0xFFFF,  // Include all
            exclude_flags: 0,       // Exclude none
            area_costs,
        }
    }
}
```

### 3.5 Status Codes

```rust
/// Detour operation status
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DetourStatus(pub u32);

impl DetourStatus {
    // Status flags
    pub const SUCCESS: u32 = 1 << 30;
    pub const FAILURE: u32 = 0;
    pub const IN_PROGRESS: u32 = 1 << 30;
    
    // Detail flags
    pub const WRONG_MAGIC: u32 = 1 << 0;
    pub const WRONG_VERSION: u32 = 1 << 1;
    pub const OUT_OF_MEMORY: u32 = 1 << 2;
    pub const INVALID_PARAM: u32 = 1 << 3;
    pub const BUFFER_TOO_SMALL: u32 = 1 << 4;
    pub const OUT_OF_NODES: u32 = 1 << 5;
    pub const PARTIAL_RESULT: u32 = 1 << 6;
    pub const ALREADY_OCCUPIED: u32 = 1 << 7;
    
    pub fn succeeded(&self) -> bool {
        (self.0 & Self::FAILURE) == 0
    }
    
    pub fn failed(&self) -> bool {
        (self.0 & Self::FAILURE) != 0
    }
    
    pub fn in_progress(&self) -> bool {
        (self.0 & Self::IN_PROGRESS) != 0
    }
    
    pub fn is_partial(&self) -> bool {
        (self.0 & Self::PARTIAL_RESULT) != 0
    }
}
```

---

## 4. TrinityCore File Formats

### 4.1 MMAP File (Map Metadata)

**Filename Pattern:** `{mapId:04}.mmap` (e.g., `0000.mmap` for Eastern Kingdoms)

**File Structure:**
```
Offset  Size  Field              Description
------  ----  -----              -----------
0x00    12    orig[3]            World origin (3 floats)
0x0C    4     tile_width         Tile width (float)
0x10    4     tile_height        Tile height (float)
0x14    4     max_tiles          Maximum tiles (int32)
0x18    4     max_polys          Maximum polygons (int32)
------  ----  -----              -----------
Total: 28 bytes
```

```rust
/// TrinityCore map metadata file
#[repr(C, packed)]
#[derive(Debug, Clone, Copy)]
pub struct MmapFile {
    pub params: NavMeshParams,
}

impl MmapFile {
    pub const SIZE: usize = 28;
    
    pub fn from_bytes(data: &[u8]) -> Result<Self, MmapError> {
        if data.len() < Self::SIZE {
            return Err(MmapError::FileTooSmall);
        }
        
        Ok(unsafe {
            std::ptr::read_unaligned(data.as_ptr() as *const Self)
        })
    }
}
```

### 4.2 MMTILE File (Tile Data)

**Filename Pattern:** `{mapId:04}{x:02}{y:02}.mmtile` (e.g., `00003232.mmtile`)

**File Structure:**
```
Offset  Size  Field              Description
------  ----  -----              -----------
0x00    4     mmap_magic         Magic "MMAP" = 0x4D4D4150
0x04    4     dt_version         Detour version (7)
0x08    4     mmap_version       TC generator version (5-9)
0x0C    4     size               Tile data size (following header)
0x10    1     uses_liquids       Has liquid data (bool)
0x11    3     padding            Alignment padding
------  ----  -----              -----------
Header: 20 bytes

0x14    N     tile_data          Raw Detour tile data (dtMeshTile format)
```

```rust
/// TrinityCore tile file header
#[repr(C, packed)]
#[derive(Debug, Clone, Copy)]
pub struct MmapTileHeader {
    /// Magic number "MMAP" in little-endian
    pub mmap_magic: u32,
    
    /// Detour navmesh version (should be 7)
    pub dt_version: u32,
    
    /// TrinityCore mmap generator version (5-9)
    pub mmap_version: u32,
    
    /// Size of tile data following header
    pub size: u32,
    
    /// Whether tile contains liquid data
    pub uses_liquids: u8,
    
    /// Padding for alignment
    pub _padding: [u8; 3],
}

impl MmapTileHeader {
    pub const MAGIC: u32 = 0x4D4D4150;  // "MMAP"
    pub const SIZE: usize = 20;
    pub const DT_VERSION: u32 = 7;
    pub const MIN_MMAP_VERSION: u32 = 5;
    pub const MAX_MMAP_VERSION: u32 = 9;
    
    pub fn from_bytes(data: &[u8]) -> Result<Self, MmapError> {
        if data.len() < Self::SIZE {
            return Err(MmapError::FileTooSmall);
        }
        
        let header: Self = unsafe {
            std::ptr::read_unaligned(data.as_ptr() as *const Self)
        };
        
        header.validate()?;
        Ok(header)
    }
    
    pub fn validate(&self) -> Result<(), MmapError> {
        if self.mmap_magic != Self::MAGIC {
            return Err(MmapError::InvalidMagic(self.mmap_magic));
        }
        if self.dt_version != Self::DT_VERSION {
            return Err(MmapError::UnsupportedDetourVersion(self.dt_version));
        }
        if self.mmap_version < Self::MIN_MMAP_VERSION || 
           self.mmap_version > Self::MAX_MMAP_VERSION {
            return Err(MmapError::UnsupportedMmapVersion(self.mmap_version));
        }
        Ok(())
    }
}

/// Complete tile file contents
pub struct MmapTileFile {
    pub header: MmapTileHeader,
    pub tile_data: Vec<u8>,
}

impl MmapTileFile {
    pub fn from_bytes(data: Vec<u8>) -> Result<Self, MmapError> {
        let header = MmapTileHeader::from_bytes(&data)?;
        
        let tile_start = MmapTileHeader::SIZE;
        let tile_end = tile_start + header.size as usize;
        
        if data.len() < tile_end {
            return Err(MmapError::TruncatedTileData);
        }
        
        Ok(Self {
            header,
            tile_data: data[tile_start..tile_end].to_vec(),
        })
    }
}
```

### 4.3 Tile Coordinate System

```rust
/// Tile coordinates for WoW maps
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TileCoord {
    pub map_id: u32,
    pub x: i32,
    pub y: i32,
}

impl TileCoord {
    pub const TILE_SIZE: f32 = 533.33333;
    pub const GRID_SIZE: i32 = 64;
    
    /// Calculate tile coordinates for a world position
    pub fn from_world_pos(map_id: u32, params: &NavMeshParams, pos: Vec3) -> Self {
        let x = ((pos.x - params.orig[0]) / params.tile_width) as i32;
        let y = ((pos.z - params.orig[2]) / params.tile_height) as i32;
        Self { map_id, x, y }
    }
    
    /// Get the world-space bounds of this tile
    pub fn bounds(&self, params: &NavMeshParams) -> BoundingBox {
        let min_x = params.orig[0] + (self.x as f32 * params.tile_width);
        let min_z = params.orig[2] + (self.y as f32 * params.tile_height);
        
        BoundingBox {
            min: Vec3::new(min_x, f32::MIN, min_z),
            max: Vec3::new(
                min_x + params.tile_width,
                f32::MAX,
                min_z + params.tile_height,
            ),
        }
    }
    
    /// Generate filename for this tile
    pub fn filename(&self) -> String {
        format!("{:04}{:02}{:02}.mmtile", self.map_id, self.x, self.y)
    }
}
```

---

## 5. API Data Transfer Objects

### 5.1 Request Parameters

```rust
/// Query parameters for /api/v1/path
#[derive(Debug, Deserialize)]
pub struct PathParams {
    pub map_id: u32,
    pub start_x: f32,
    pub start_y: f32,
    pub start_z: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub end_z: f32,
    #[serde(default)]
    pub smoothing: Option<String>,
}

/// Query parameters for /api/v1/move
#[derive(Debug, Deserialize)]
pub struct MoveParams {
    pub map_id: u32,
    pub start_x: f32,
    pub start_y: f32,
    pub start_z: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub end_z: f32,
}

/// Query parameters for /api/v1/raycast
#[derive(Debug, Deserialize)]
pub struct RaycastParams {
    pub map_id: u32,
    pub start_x: f32,
    pub start_y: f32,
    pub start_z: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub end_z: f32,
}

/// Query parameters for /api/v1/random
#[derive(Debug, Deserialize)]
pub struct RandomParams {
    pub map_id: u32,
}

/// Query parameters for /api/v1/random-circle
#[derive(Debug, Deserialize)]
pub struct RandomCircleParams {
    pub map_id: u32,
    pub center_x: f32,
    pub center_y: f32,
    pub center_z: f32,
    pub radius: f32,
}

/// Query parameters for /api/v1/height
#[derive(Debug, Deserialize)]
pub struct HeightParams {
    pub map_id: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}
```

### 5.2 Response Objects

```rust
/// Response for /api/v1/path
#[derive(Debug, Serialize)]
pub struct PathResponse {
    pub success: bool,
    pub path: Vec<[f32; 3]>,
    pub distance: f32,
    pub compute_time_ms: f64,
    pub partial: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Response for /api/v1/move
#[derive(Debug, Serialize)]
pub struct MoveResponse {
    pub success: bool,
    pub result_position: [f32; 3],
    pub compute_time_ms: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Response for /api/v1/raycast
#[derive(Debug, Serialize)]
pub struct RaycastResponse {
    pub success: bool,
    pub hit: bool,
    pub t: f32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hit_point: Option<[f32; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hit_normal: Option<[f32; 3]>,
    pub compute_time_ms: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Response for /api/v1/random
#[derive(Debug, Serialize)]
pub struct RandomResponse {
    pub success: bool,
    pub position: [f32; 3],
    pub compute_time_ms: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Response for /api/v1/random-circle
#[derive(Debug, Serialize)]
pub struct RandomCircleResponse {
    pub success: bool,
    pub position: [f32; 3],
    pub distance_from_center: f32,
    pub compute_time_ms: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Response for /api/v1/height
#[derive(Debug, Serialize)]
pub struct HeightResponse {
    pub success: bool,
    pub height: f32,
    pub compute_time_ms: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Response for /health
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    pub uptime_seconds: u64,
    pub loaded_maps: Vec<u32>,
    pub total_tiles_loaded: usize,
    pub memory_usage_mb: f64,
}
```

---

## 6. Internal Result Types

### 6.1 Path Results

```rust
/// Result of a pathfinding operation
#[derive(Debug)]
pub struct PathResult {
    /// Waypoints forming the path
    pub path: Vec<Vec3>,
    
    /// Whether this is only a partial path
    pub partial: bool,
}

impl PathResult {
    /// Calculate total path distance
    pub fn distance(&self) -> f32 {
        if self.path.len() < 2 {
            return 0.0;
        }
        
        self.path.windows(2)
            .map(|w| w[0].distance(&w[1]))
            .sum()
    }
    
    /// Get path length (number of waypoints)
    pub fn len(&self) -> usize {
        self.path.len()
    }
    
    /// Check if path is empty
    pub fn is_empty(&self) -> bool {
        self.path.is_empty()
    }
}
```

### 6.2 Raycast Result

```rust
/// Result of a raycast operation
#[derive(Debug)]
pub struct RaycastResult {
    /// Whether the ray hit something
    pub hit: bool,
    
    /// Parameter along ray where hit occurred (0.0 = start, 1.0 = end)
    pub t: f32,
    
    /// Position where ray hit (if hit)
    pub hit_point: Option<Vec3>,
    
    /// Normal at hit point (if hit)
    pub hit_normal: Option<Vec3>,
}
```

---

## 7. Configuration Types

### 7.1 Server Configuration

```rust
#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub navmesh: NavmeshConfig,
    pub pathfinding: PathfindingConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    /// Host to bind to
    pub host: String,
    
    /// Port to listen on
    pub port: u16,
    
    /// Maximum concurrent requests
    pub max_concurrent_requests: usize,
}

#[derive(Debug, Clone, Deserialize)]
pub struct NavmeshConfig {
    /// Path to mmap files directory
    pub mmap_path: PathBuf,
    
    /// Maps to preload at startup
    pub preload_maps: Vec<u32>,
    
    /// Maximum cached tiles
    pub max_cached_tiles: usize,
    
    /// Enable lazy tile loading
    pub lazy_loading: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PathfindingConfig {
    /// Default smoothing algorithm
    pub default_smoothing: SmoothingAlgorithm,
    
    /// Maximum path length in waypoints
    pub max_path_length: usize,
    
    /// Query pool size per map
    pub query_pool_size: usize,
}

#[derive(Debug, Clone, Copy, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum SmoothingAlgorithm {
    #[default]
    None,
    Chaikin,
    CatmullRom,
    Bezier,
}
```

---

## 8. Error Types

```rust
#[derive(Debug, thiserror::Error)]
pub enum DetourError {
    #[error("Memory allocation failed")]
    AllocationFailed,
    
    #[error("NavMesh initialization failed")]
    InitFailed,
    
    #[error("Start position not on navmesh")]
    StartNotFound,
    
    #[error("End position not on navmesh")]
    EndNotFound,
    
    #[error("No path found between positions")]
    PathNotFound,
    
    #[error("Straight path calculation failed")]
    StraightPathFailed,
    
    #[error("Detour status error: 0x{0:08X}")]
    StatusError(u32),
}

#[derive(Debug, thiserror::Error)]
pub enum MmapError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    
    #[error("Invalid magic number: 0x{0:08X}, expected 0x4D4D4150")]
    InvalidMagic(u32),
    
    #[error("Unsupported Detour version: {0}, expected 7")]
    UnsupportedDetourVersion(u32),
    
    #[error("Unsupported mmap version: {0}, expected 5-9")]
    UnsupportedMmapVersion(u32),
    
    #[error("File too small for header")]
    FileTooSmall,
    
    #[error("Truncated tile data")]
    TruncatedTileData,
    
    #[error("Map {0} not found")]
    MapNotFound(u32),
    
    #[error("Tile ({0}, {1}) not found for map {2}")]
    TileNotFound(i32, i32, u32),
}
```

---

## 9. WoW-Specific Constants

```rust
/// Well-known WoW map IDs
pub mod map_ids {
    pub const EASTERN_KINGDOMS: u32 = 0;
    pub const KALIMDOR: u32 = 1;
    pub const OUTLAND: u32 = 530;
    pub const NORTHREND: u32 = 571;
    
    // Common dungeons
    pub const DEADMINES: u32 = 36;
    pub const STOCKADE: u32 = 34;
    pub const SHADOWFANG_KEEP: u32 = 33;
    pub const SCARLET_MONASTERY: u32 = 189;
}

/// WoW coordinate system constants
pub mod coords {
    /// Size of one navmesh tile in yards
    pub const TILE_SIZE: f32 = 533.33333;
    
    /// Number of tiles per map axis
    pub const GRID_SIZE: i32 = 64;
    
    /// Total map size in yards
    pub const MAP_SIZE: f32 = TILE_SIZE * GRID_SIZE as f32;
}

/// Area types used in TrinityCore navmeshes
pub mod area_types {
    pub const GROUND: u8 = 0;
    pub const WATER: u8 = 1;
    pub const MAGMA: u8 = 2;
    pub const SLIME: u8 = 3;
}
```
