//! Tile coordinate utilities.

use crate::format::{MmapFormat, MmapHeader};
use detour::Vec3;

/// Size of one navmesh tile in yards (WoW units).
pub const TILE_SIZE: f32 = 533.33333;

/// Number of tiles per map axis.
pub const GRID_SIZE: i32 = 64;

/// Tile coordinates for a navmesh tile.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TileCoord {
    pub map_id: u32,
    pub x: i32,
    pub y: i32,
}

impl TileCoord {
    /// Create a new tile coordinate.
    pub fn new(map_id: u32, x: i32, y: i32) -> Self {
        Self { map_id, x, y }
    }

    /// Calculate tile coordinates for a world position.
    ///
    /// Note: CMaNGOS uses a coordinate system where the origin is at
    /// the center of the map, and tile coordinates increase outward.
    pub fn from_world_pos(map_id: u32, params: &MmapHeader, pos: Vec3) -> Self {
        let x = ((pos.x - params.orig[0]) / params.tile_width) as i32;
        let y = ((pos.y - params.orig[2]) / params.tile_height) as i32;

        Self {
            map_id,
            x: x.clamp(0, GRID_SIZE - 1),
            y: y.clamp(0, GRID_SIZE - 1),
        }
    }

    /// Generate the filename for this tile in the given format.
    ///
    /// - CMaNGOS: `{mapId:03}{x:02}{y:02}.mmtile` (e.g., "0002337.mmtile")
    /// - TrinityCore: `{mapId:04}_{x:02}_{y:02}.mmtile` (e.g., "0000_23_37.mmtile")
    pub fn filename(&self, format: MmapFormat) -> String {
        match format {
            MmapFormat::CMaNGOS => {
                std::format!("{:03}{:02}{:02}.mmtile", self.map_id, self.x, self.y)
            }
            MmapFormat::TrinityCore => {
                std::format!("{:04}_{:02}_{:02}.mmtile", self.map_id, self.x, self.y)
            }
        }
    }

    /// Generate the mmap header filename for a map in the given format.
    ///
    /// - CMaNGOS: `{mapId:03}.mmap` (e.g., "000.mmap")
    /// - TrinityCore: `{mapId:04}.mmap` (e.g., "0000.mmap")
    pub fn mmap_filename(map_id: u32, format: MmapFormat) -> String {
        match format {
            MmapFormat::CMaNGOS => std::format!("{:03}.mmap", map_id),
            MmapFormat::TrinityCore => std::format!("{:04}.mmap", map_id),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tile_filename_cmangos() {
        let coord = TileCoord::new(0, 23, 37);
        assert_eq!(coord.filename(MmapFormat::CMaNGOS), "0002337.mmtile");
    }

    #[test]
    fn test_tile_filename_trinitycore() {
        let coord = TileCoord::new(0, 23, 37);
        assert_eq!(coord.filename(MmapFormat::TrinityCore), "0000_23_37.mmtile");
    }

    #[test]
    fn test_mmap_filename_cmangos() {
        assert_eq!(TileCoord::mmap_filename(0, MmapFormat::CMaNGOS), "000.mmap");
        assert_eq!(TileCoord::mmap_filename(1, MmapFormat::CMaNGOS), "001.mmap");
        assert_eq!(TileCoord::mmap_filename(530, MmapFormat::CMaNGOS), "530.mmap");
    }

    #[test]
    fn test_mmap_filename_trinitycore() {
        assert_eq!(TileCoord::mmap_filename(0, MmapFormat::TrinityCore), "0000.mmap");
        assert_eq!(TileCoord::mmap_filename(1, MmapFormat::TrinityCore), "0001.mmap");
        assert_eq!(TileCoord::mmap_filename(530, MmapFormat::TrinityCore), "0530.mmap");
    }
}
