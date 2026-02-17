//! Navigation mesh (.mmap/.mmtile) file loader.
//!
//! Handles loading CMaNGOS-compatible navigation mesh files (.mmap and .mmtile).

pub mod format;
pub mod coords;
pub mod loader;
pub mod manager;
pub mod error;

pub use format::{MmapHeader, MmapTileHeader};
pub use coords::TileCoord;
pub use loader::MmapLoader;
pub use manager::MmapManager;
pub use error::MmapError;
