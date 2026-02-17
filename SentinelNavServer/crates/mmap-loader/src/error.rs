//! Error types for mmap operations.

use thiserror::Error;

/// Errors that can occur during mmap file operations.
#[derive(Debug, Error)]
pub enum MmapError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Invalid magic number: 0x{0:08X}, expected 0x4D4D4150 (\"MMAP\")")]
    InvalidMagic(u32),

    #[error("Unsupported Detour version: {0}, expected 7")]
    UnsupportedDetourVersion(u32),

    #[error("Unsupported mmap version: {0}, expected 5-15")]
    UnsupportedMmapVersion(u32),

    #[error("File too small for header (got {0} bytes)")]
    FileTooSmall(usize),

    #[error("Truncated tile data")]
    TruncatedTileData,

    #[error("Map {0} not found")]
    MapNotFound(u32),

    #[error("Tile ({x}, {y}) not found for map {map_id}")]
    TileNotFound { map_id: u32, x: i32, y: i32 },

    #[error("Detour error: {0}")]
    Detour(#[from] detour::DetourError),
}
