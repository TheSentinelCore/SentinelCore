//! Navigation mesh (.mmap/.mmtile) file loader.
//!
//! Handles loading CMaNGOS and TrinityCore navigation mesh files (.mmap and .mmtile).

pub mod format;
pub mod coords;
pub mod loader;
pub mod manager;
pub mod error;

pub use format::{MmapFormat, MmapHeader, MmapTileHeader, TrinityMmapHeader, parse_mmap_file};
pub use coords::TileCoord;
pub use loader::MmapLoader;
pub use manager::MmapManager;
pub use error::MmapError;
