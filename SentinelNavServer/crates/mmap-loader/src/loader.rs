//! Mmap file loader.

use crate::coords::TileCoord;
use crate::error::MmapError;
use crate::format::{MmapFormat, MmapHeader, MmapTileHeader, parse_mmap_file};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use tracing::debug;

/// Loader for CMaNGOS and TrinityCore mmap files.
///
/// Auto-detects the format on first map load by examining the .mmap header.
pub struct MmapLoader {
    mmap_path: PathBuf,
    params_cache: Mutex<HashMap<u32, MmapHeader>>,
    /// Detected format (set on first successful map load).
    detected_format: Mutex<Option<MmapFormat>>,
}

impl MmapLoader {
    /// Create a new loader for the given mmap directory.
    pub fn new(mmap_path: impl AsRef<Path>) -> Self {
        Self {
            mmap_path: mmap_path.as_ref().to_path_buf(),
            params_cache: Mutex::new(HashMap::new()),
            detected_format: Mutex::new(None),
        }
    }

    /// Get the detected mmap format, or None if no map has been loaded yet.
    pub fn format(&self) -> Option<MmapFormat> {
        *self.detected_format.lock()
    }

    /// Load map parameters from .mmap file.
    ///
    /// On first call, auto-detects the format by trying both naming conventions
    /// and examining the file header.
    pub fn load_map_params(&self, map_id: u32) -> Result<MmapHeader, MmapError> {
        // Check cache first
        {
            let cache = self.params_cache.lock();
            if let Some(params) = cache.get(&map_id) {
                return Ok(*params);
            }
        }

        // Try to find and load the .mmap file
        let (data, format) = self.find_and_read_mmap(map_id)?;

        // Parse based on detected format
        let (_detected_format, header) = parse_mmap_file(&data)?;

        // Store the detected format
        {
            let mut fmt = self.detected_format.lock();
            if fmt.is_none() {
                debug!("Auto-detected mmap format: {:?}", format);
                *fmt = Some(format);
            }
        }

        // Cache for future use
        {
            let mut cache = self.params_cache.lock();
            cache.insert(map_id, header);
        }

        Ok(header)
    }

    /// Find the .mmap file by trying both naming conventions.
    ///
    /// Returns the file contents and the detected format.
    fn find_and_read_mmap(&self, map_id: u32) -> Result<(Vec<u8>, MmapFormat), MmapError> {
        // If we already know the format, use it directly
        if let Some(format) = *self.detected_format.lock() {
            let filename = TileCoord::mmap_filename(map_id, format);
            let path = self.mmap_path.join(&filename);
            if path.exists() {
                let data = std::fs::read(&path)?;
                return Ok((data, format));
            }
            return Err(MmapError::MapNotFound(map_id));
        }

        // Auto-detect: try TrinityCore naming first (4-digit), then CMaNGOS (3-digit)
        for format in [MmapFormat::TrinityCore, MmapFormat::CMaNGOS] {
            let filename = TileCoord::mmap_filename(map_id, format);
            let path = self.mmap_path.join(&filename);
            if path.exists() {
                let data = std::fs::read(&path)?;
                return Ok((data, format));
            }
        }

        Err(MmapError::MapNotFound(map_id))
    }

    /// Get the effective format, defaulting to CMaNGOS if not yet detected.
    fn effective_format(&self) -> MmapFormat {
        self.detected_format.lock().unwrap_or(MmapFormat::CMaNGOS)
    }

    /// Load tile data from .mmtile file.
    ///
    /// Returns the raw Detour tile data (without the mmtile header).
    pub fn load_tile(&self, map_id: u32, x: i32, y: i32) -> Result<Vec<u8>, MmapError> {
        let format = self.effective_format();
        let coord = TileCoord::new(map_id, x, y);
        let path = self.mmap_path.join(coord.filename(format));

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
        let format = self.effective_format();
        let coord = TileCoord::new(map_id, x, y);
        self.mmap_path.join(coord.filename(format)).exists()
    }

    /// Check if a map exists.
    pub fn map_exists(&self, map_id: u32) -> bool {
        let format = self.effective_format();
        let filename = TileCoord::mmap_filename(map_id, format);
        if self.mmap_path.join(&filename).exists() {
            return true;
        }
        // If format not detected yet, also try the other naming
        if self.detected_format.lock().is_none() {
            for fmt in [MmapFormat::TrinityCore, MmapFormat::CMaNGOS] {
                let filename = TileCoord::mmap_filename(map_id, fmt);
                if self.mmap_path.join(&filename).exists() {
                    return true;
                }
            }
        }
        false
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
