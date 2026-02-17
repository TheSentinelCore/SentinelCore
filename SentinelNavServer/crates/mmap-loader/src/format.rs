//! Navigation mesh file format structures.

use crate::error::MmapError;

/// Magic number for mmap tile files: "MMAP" in little-endian.
pub const MMAP_MAGIC: u32 = 0x4D4D4150;

/// Expected Detour navmesh version.
pub const DT_NAVMESH_VERSION: u32 = 7;

/// Minimum supported mmap generator version.
pub const MIN_MMAP_VERSION: u32 = 5;

/// Maximum supported mmap generator version.
pub const MAX_MMAP_VERSION: u32 = 15;

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

/// Header of a .mmtile file (tile data).
///
/// File pattern: `{mapId:03}{x:02}{y:02}.mmtile` (e.g., "0002337.mmtile")
#[repr(C, packed)]
#[derive(Debug, Clone, Copy)]
pub struct MmapTileHeader {
    /// Magic number: "MMAP" = 0x4D4D4150.
    pub mmap_magic: u32,
    /// Detour navmesh version (should be 7).
    pub dt_version: u32,
    /// CMaNGOS mmap generator version.
    pub mmap_version: u32,
    /// Size of tile data following this header.
    pub size: u32,
    /// Whether tile contains liquid data.
    pub uses_liquids: u8,
    /// Padding for alignment.
    pub _padding: [u8; 3],
}

impl MmapTileHeader {
    pub const SIZE: usize = 20;

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
    fn test_mmtile_header_size() {
        assert_eq!(std::mem::size_of::<MmapTileHeader>(), MmapTileHeader::SIZE);
    }

    #[test]
    fn test_valid_header() {
        let header = MmapTileHeader {
            mmap_magic: MMAP_MAGIC,
            dt_version: DT_NAVMESH_VERSION,
            mmap_version: 8,
            size: 1000,
            uses_liquids: 0,
            _padding: [0; 3],
        };
        assert!(header.validate().is_ok());
    }

    #[test]
    fn test_invalid_magic() {
        let header = MmapTileHeader {
            mmap_magic: 0xDEADBEEF,
            dt_version: DT_NAVMESH_VERSION,
            mmap_version: 8,
            size: 1000,
            uses_liquids: 0,
            _padding: [0; 3],
        };
        assert!(matches!(header.validate(), Err(MmapError::InvalidMagic(_))));
    }
}
