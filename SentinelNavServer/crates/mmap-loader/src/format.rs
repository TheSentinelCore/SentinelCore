//! Navigation mesh file format structures.

use crate::error::MmapError;

/// Magic number for mmap tile files: "MMAP" in little-endian.
pub const MMAP_MAGIC: u32 = 0x4D4D4150;

/// Expected Detour navmesh version.
pub const DT_NAVMESH_VERSION: u32 = 7;

/// Minimum supported mmap generator version.
pub const MIN_MMAP_VERSION: u32 = 4;

/// Maximum supported mmap generator version (AzerothCore uses 19).
pub const MAX_MMAP_VERSION: u32 = 19;

/// Header of a .mmap file (map metadata).
///
/// This contains the dtNavMeshParams structure (28 bytes).
/// File pattern: `{mapId:03}.mmap` (e.g., "000.mmap")
#[repr(C, packed)]
#[derive(Debug, Clone, Copy)]
pub struct MmapHeader {
    /// World origin (3 floats).
    pub orig: [f32; 3],
    /// Tile width (usually 533.33333).
    pub tile_width: f32,
    /// Tile height (usually 533.33333).
    pub tile_height: f32,
    /// Maximum number of tiles.
    pub max_tiles: i32,
    /// Maximum polygons per tile.
    pub max_polys: i32,
}

impl MmapHeader {
    pub const SIZE: usize = 28;

    /// Parse from bytes.
    pub fn from_bytes(data: &[u8]) -> Result<Self, MmapError> {
        if data.len() < Self::SIZE {
            return Err(MmapError::FileTooSmall(data.len()));
        }

        // SAFETY: We've verified the length and MmapHeader is repr(C, packed)
        let header: Self = unsafe { std::ptr::read_unaligned(data.as_ptr() as *const Self) };

        Ok(header)
    }

    /// Convert to NavMeshParams for NavMesh initialization.
    ///
    /// The MmapHeader contains the same dtNavMeshParams structure
    /// that Detour expects for mesh initialization.
    pub fn to_nav_mesh_params(&self) -> detour::mesh::NavMeshParams {
        detour::mesh::NavMeshParams {
            orig: self.orig,
            tile_width: self.tile_width,
            tile_height: self.tile_height,
            max_tiles: self.max_tiles,
            max_polys: self.max_polys,
        }
    }
}

/// Recast configuration embedded in AzerothCore mmtile headers.
///
/// This 36-byte block sits between the base header fields and the Detour
/// tile data. It is read but not used at runtime — we only need it so that
/// `MmapTileHeader::SIZE` correctly reflects the on-disk layout and the
/// loader skips to the right offset for the tile data.
#[repr(C, packed)]
#[derive(Debug, Clone, Copy)]
pub struct MmapTileRecastConfig {
    pub walkable_slope_angle: f32,
    pub walkable_radius: u8,
    pub walkable_height: u8,
    pub walkable_climb: u8,
    pub _padding0: u8,
    pub vertex_per_map_edge: u32,
    pub vertex_per_tile_edge: u32,
    pub tiles_per_map_edge: u32,
    pub base_unit_dim: f32,
    pub cell_size_horizontal: f32,
    pub cell_size_vertical: f32,
    pub max_simplification_error: f32,
}

/// Header of a .mmtile file (tile data).
///
/// Supports both CMaNGOS (20-byte) and AzerothCore (56-byte) layouts.
/// File pattern: `{mapId:03}{x:02}{y:02}.mmtile` (e.g., "0002337.mmtile")
#[repr(C, packed)]
#[derive(Debug, Clone, Copy)]
pub struct MmapTileHeader {
    /// Magic number: "MMAP" = 0x4D4D4150.
    pub mmap_magic: u32,
    /// Detour navmesh version (should be 7).
    pub dt_version: u32,
    /// Mmap generator version.
    pub mmap_version: u32,
    /// Size of tile data following this header.
    pub size: u32,
    /// Whether tile contains liquid data.
    pub uses_liquids: u8,
    /// Padding for alignment.
    pub _padding: [u8; 3],
    /// AzerothCore recast configuration (36 bytes).
    pub recast_config: MmapTileRecastConfig,
}

impl MmapTileHeader {
    /// AzerothCore header size: 20 (base) + 36 (RecastConfig) = 56 bytes.
    pub const SIZE: usize = 56;

    /// Parse from bytes and validate.
    pub fn from_bytes(data: &[u8]) -> Result<Self, MmapError> {
        if data.len() < Self::SIZE {
            return Err(MmapError::FileTooSmall(data.len()));
        }

        // SAFETY: We've verified the length and MmapTileHeader is repr(C, packed)
        let header: Self = unsafe { std::ptr::read_unaligned(data.as_ptr() as *const Self) };

        header.validate()?;
        Ok(header)
    }

    /// Validate the header fields.
    pub fn validate(&self) -> Result<(), MmapError> {
        if self.mmap_magic != MMAP_MAGIC {
            return Err(MmapError::InvalidMagic(self.mmap_magic));
        }
        if self.dt_version != DT_NAVMESH_VERSION {
            return Err(MmapError::UnsupportedDetourVersion(self.dt_version));
        }
        if self.mmap_version < MIN_MMAP_VERSION || self.mmap_version > MAX_MMAP_VERSION {
            return Err(MmapError::UnsupportedMmapVersion(self.mmap_version));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mmap_header_size() {
        assert_eq!(std::mem::size_of::<MmapHeader>(), MmapHeader::SIZE);
    }

    #[test]
    fn test_recast_config_size() {
        assert_eq!(std::mem::size_of::<MmapTileRecastConfig>(), 36);
    }

    #[test]
    fn test_mmtile_header_size() {
        assert_eq!(std::mem::size_of::<MmapTileHeader>(), MmapTileHeader::SIZE);
        assert_eq!(MmapTileHeader::SIZE, 56);
    }

    fn make_test_header(magic: u32, dt_ver: u32, mmap_ver: u32) -> MmapTileHeader {
        MmapTileHeader {
            mmap_magic: magic,
            dt_version: dt_ver,
            mmap_version: mmap_ver,
            size: 1000,
            uses_liquids: 0,
            _padding: [0; 3],
            recast_config: MmapTileRecastConfig {
                walkable_slope_angle: 60.0,
                walkable_radius: 3,
                walkable_height: 6,
                walkable_climb: 6,
                _padding0: 0,
                vertex_per_map_edge: 3000,
                vertex_per_tile_edge: 80,
                tiles_per_map_edge: 38,
                base_unit_dim: 0.1778,
                cell_size_horizontal: 0.1778,
                cell_size_vertical: 0.1778,
                max_simplification_error: 0.8,
            },
        }
    }

    #[test]
    fn test_valid_header_azerothcore() {
        let header = make_test_header(MMAP_MAGIC, DT_NAVMESH_VERSION, 19);
        assert!(header.validate().is_ok());
    }

    #[test]
    fn test_valid_header_cmangos() {
        let header = make_test_header(MMAP_MAGIC, DT_NAVMESH_VERSION, 8);
        assert!(header.validate().is_ok());
    }

    #[test]
    fn test_invalid_magic() {
        let header = make_test_header(0xDEADBEEF, DT_NAVMESH_VERSION, 8);
        assert!(matches!(header.validate(), Err(MmapError::InvalidMagic(_))));
    }
}
