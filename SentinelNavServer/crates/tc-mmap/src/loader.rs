//! Mmap file loader.

use crate::coords::TileCoord;
use crate::error::MmapError;
use crate::format::{MmapHeader, MmapTileHeader};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Loader for TrinityCore mmap files.
pub struct MmapLoader {
    mmap_path: PathBuf,
    params_cache: Mutex<HashMap<u32, MmapHeader>>,
}

impl MmapLoader {
    /// Create a new loader for the given mmap directory.
    pub fn new(mmap_path: impl AsRef<Path>) -> Self {
        Self {
            mmap_path: mmap_path.as_ref().to_path_buf(),
            params_cache: Mutex::new(HashMap::new()),
        }
    }

    /// Load map parameters from .mmap file.
    pub fn load_map_params(&self, map_id: u32) -> Result<MmapHeader, MmapError> {
        // Check cache first
        {
            let cache = self.params_cache.lock();
            if let Some(params) = cache.get(&map_id) {
                return Ok(*params);
            }
        }

        let filename = TileCoord::mmap_filename(map_id);
        let path = self.mmap_path.join(&filename);

        if !path.exists() {
            return Err(MmapError::MapNotFound(map_id));
        }

        let data = std::fs::read(&path)?;
        let header = MmapHeader::from_bytes(&data)?;

        // Cache for future use
        {
            let mut cache = self.params_cache.lock();
            cache.insert(map_id, header);
        }

        Ok(header)
    }

    /// Load tile data from .mmtile file.
    ///
    /// Returns the raw Detour tile data (without the mmtile header).
    pub fn load_tile(&self, map_id: u32, x: i32, y: i32) -> Result<Vec<u8>, MmapError> {
        let coord = TileCoord::new(map_id, x, y);
        let path = self.mmap_path.join(coord.filename());

        if !path.exists() {
            return Err(MmapError::TileNotFound { map_id, x, y });
        }

        let data = std::fs::read(&path)?;

        // Parse and validate header
        let header = MmapTileHeader::from_bytes(&data)?;

        // Extract tile data (skip header)
        let tile_start = MmapTileHeader::SIZE;
        let tile_end = tile_start
            .checked_add(header.size as usize)
            .ok_or(MmapError::TruncatedTileData)?;

        if data.len() < tile_end {
            return Err(MmapError::TruncatedTileData);
        }

        Ok(data[tile_start..tile_end].to_vec())
    }

    /// Check if a tile exists.
    pub fn tile_exists(&self, map_id: u32, x: i32, y: i32) -> bool {
        let coord = TileCoord::new(map_id, x, y);
        self.mmap_path.join(coord.filename()).exists()
    }

    /// Check if a map exists.
    pub fn map_exists(&self, map_id: u32) -> bool {
        let filename = TileCoord::mmap_filename(map_id);
        self.mmap_path.join(filename).exists()
    }

    /// List all available tiles for a map.
    pub fn list_tiles(&self, map_id: u32) -> Vec<TileCoord> {
        let mut tiles = Vec::new();

        for x in 0..64 {
            for y in 0..64 {
                if self.tile_exists(map_id, x, y) {
                    tiles.push(TileCoord::new(map_id, x, y));
                }
            }
        }

        tiles
    }
}
