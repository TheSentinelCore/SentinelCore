//! Navigation mesh file format structures.
//!
//! Supports both CMaNGOS and TrinityCore mmap formats:
//! - **CMaNGOS**: .mmap = raw `dtNavMeshParams` (28 bytes); tiles = `{mapId:03}{x:02}{y:02}.mmtile`
//! - **TrinityCore**: .mmap = magic + version + `dtNavMeshParams` + offmesh count (40 bytes);
//!   tiles = `{mapId:04}_{x:02}_{y:02}.mmtile`

use crate::error::MmapError;

/// Magic number for mmap tile files: "MMAP" in little-endian.
pub const MMAP_MAGIC: u32 = 0x4D4D4150;

/// Expected Detour navmesh version.
pub const DT_NAVMESH_VERSION: u32 = 7;

/// Minimum supported mmap generator version.
pub const MIN_MMAP_VERSION: u32 = 5;

/// Maximum supported mmap generator version (TrinityCore uses 16).
pub const MAX_MMAP_VERSION: u32 = 16;

/// Detected mmap file format variant.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MmapFormat {
    /// CMaNGOS format: raw dtNavMeshParams in .mmap, `{mapId:03}{x:02}{y:02}.mmtile`
    CMaNGOS,
    /// TrinityCore format: wrapped header in .mmap, `{mapId:04}_{x:02}_{y:02}.mmtile`
    TrinityCore,
}

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

/// TrinityCore .mmap file header (40 bytes).
///
/// TrinityCore wraps `dtNavMeshParams` in a header with magic, version,
/// and an off-mesh connection count.
///
/// File pattern: `{mapId:04}.mmap` (e.g., "0000.mmap")
#[repr(C, packed)]
#[derive(Debug, Clone, Copy)]
pub struct TrinityMmapHeader {
    /// Magic number: "MMAP" = 0x4D4D4150.
    pub mmap_magic: u32,
    /// TrinityCore mmap generator version (currently 16).
    pub mmap_version: u32,
    /// Navigation mesh parameters (same as CMaNGOS MmapHeader).
    pub params: MmapHeader,
    /// Number of off-mesh connections following this header.
    pub offmesh_count: u32,
}

impl TrinityMmapHeader {
    pub const SIZE: usize = 40;

    /// Parse from bytes and validate.
    pub fn from_bytes(data: &[u8]) -> Result<Self, MmapError> {
        if data.len() < Self::SIZE {
            return Err(MmapError::FileTooSmall(data.len()));
        }

        // SAFETY: We've verified the length and TrinityMmapHeader is repr(C, packed)
        let header: Self = unsafe { std::ptr::read_unaligned(data.as_ptr() as *const Self) };

        if header.mmap_magic != MMAP_MAGIC {
            return Err(MmapError::InvalidMagic(header.mmap_magic));
        }

        Ok(header)
    }
}

/// Auto-detect format and parse a .mmap file's contents.
///
/// Detection logic:
/// - If the first 4 bytes equal `MMAP_MAGIC` (0x4D4D4150), it's TrinityCore format (40 bytes)
/// - Otherwise, it's CMaNGOS format (raw 28-byte `dtNavMeshParams`)
///
/// Returns the detected format and the parsed navigation mesh parameters.
pub fn parse_mmap_file(data: &[u8]) -> Result<(MmapFormat, MmapHeader), MmapError> {
    if data.len() < 4 {
        return Err(MmapError::FileTooSmall(data.len()));
    }

    let first_u32 = u32::from_le_bytes([data[0], data[1], data[2], data[3]]);

    if first_u32 == MMAP_MAGIC {
        // TrinityCore format: magic + version + dtNavMeshParams + offmesh_count
        let tc_header = TrinityMmapHeader::from_bytes(data)?;
        Ok((MmapFormat::TrinityCore, tc_header.params))
    } else {
        // CMaNGOS format: raw dtNavMeshParams
        let header = MmapHeader::from_bytes(data)?;
        Ok((MmapFormat::CMaNGOS, header))
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

    #[test]
    fn test_trinitycore_version_accepted() {
        let header = MmapTileHeader {
            mmap_magic: MMAP_MAGIC,
            dt_version: DT_NAVMESH_VERSION,
            mmap_version: 16,
            size: 1000,
            uses_liquids: 0,
            _padding: [0; 3],
        };
        assert!(header.validate().is_ok());
    }

    #[test]
    fn test_trinity_mmap_header_size() {
        assert_eq!(std::mem::size_of::<TrinityMmapHeader>(), TrinityMmapHeader::SIZE);
    }

    #[test]
    fn test_parse_mmap_file_cmangos() {
        // CMaNGOS: raw dtNavMeshParams, first 4 bytes are orig[0] (a float, not MMAP_MAGIC)
        let mut data = vec![0u8; 28];
        // orig[0] = 1.0f32 (not MMAP_MAGIC)
        data[0..4].copy_from_slice(&1.0f32.to_le_bytes());
        // tile_width at offset 12
        data[12..16].copy_from_slice(&533.33333f32.to_le_bytes());
        // tile_height at offset 16
        data[16..20].copy_from_slice(&533.33333f32.to_le_bytes());
        // max_tiles at offset 20
        data[20..24].copy_from_slice(&1024i32.to_le_bytes());
        // max_polys at offset 24
        data[24..28].copy_from_slice(&1024i32.to_le_bytes());

        let (format, header) = parse_mmap_file(&data).unwrap();
        assert_eq!(format, MmapFormat::CMaNGOS);
        let max_tiles = header.max_tiles;
        assert_eq!(max_tiles, 1024);
    }

    #[test]
    fn test_parse_mmap_file_trinitycore() {
        // TrinityCore: magic + version + dtNavMeshParams + offmesh_count
        let mut data = vec![0u8; 40];
        // magic
        data[0..4].copy_from_slice(&MMAP_MAGIC.to_le_bytes());
        // version = 16
        data[4..8].copy_from_slice(&16u32.to_le_bytes());
        // dtNavMeshParams starts at offset 8
        // tile_width at offset 8+12 = 20
        data[20..24].copy_from_slice(&533.33333f32.to_le_bytes());
        // tile_height at offset 24
        data[24..28].copy_from_slice(&533.33333f32.to_le_bytes());
        // max_tiles at offset 28
        data[28..32].copy_from_slice(&2048i32.to_le_bytes());
        // max_polys at offset 32
        data[32..36].copy_from_slice(&2048i32.to_le_bytes());
        // offmesh_count at offset 36
        data[36..40].copy_from_slice(&0u32.to_le_bytes());

        let (format, header) = parse_mmap_file(&data).unwrap();
        assert_eq!(format, MmapFormat::TrinityCore);
        let max_tiles = header.max_tiles;
        assert_eq!(max_tiles, 2048);
    }
}
