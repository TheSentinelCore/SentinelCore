//! Tile coordinate utilities.

use crate::format::MmapHeader;
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

    /// Generate the filename for this tile.
    ///
    /// Format: `{mapId:03}{x:02}{y:02}.mmtile`
    pub fn filename(&self) -> String {
        format!("{:03}{:02}{:02}.mmtile", self.map_id, self.x, self.y)
    }

    /// Generate the mmap header filename for this map.
    ///
    /// Format: `{mapId:03}.mmap`
    pub fn mmap_filename(map_id: u32) -> String {
        format!("{:03}.mmap", map_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tile_filename() {
        let coord = TileCoord::new(0, 23, 37);
        assert_eq!(coord.filename(), "0002337.mmtile");
    }

    #[test]
    fn test_mmap_filename() {
        assert_eq!(TileCoord::mmap_filename(0), "000.mmap");
        assert_eq!(TileCoord::mmap_filename(1), "001.mmap");
        assert_eq!(TileCoord::mmap_filename(530), "530.mmap");
    }
}
