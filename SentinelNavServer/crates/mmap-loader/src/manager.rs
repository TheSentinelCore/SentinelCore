//! High-level mmap manager.

use crate::error::MmapError;
use crate::loader::MmapLoader;
use dashmap::DashMap;
use detour::{NavMesh, QueryPool};
use std::path::Path;
use std::sync::Arc;
use tracing::{debug, info, warn};

/// High-level manager for navigation meshes.
///
/// Handles eager loading of maps and provides thread-safe access
/// to navmeshes and query pools.
///
/// # Loading Strategy
///
/// When a map is first requested via `get_or_load_mesh()`, all available
/// tiles for that map are loaded eagerly. This matches the behavior of
/// the AmeisenNavigation reference implementation.
///
/// # Thread Safety
///
/// MmapManager is thread-safe:
/// - `DashMap` provides concurrent access to cached meshes
/// - `Arc<NavMesh>` allows shared ownership across threads
/// - `QueryPool` handles thread-safe query access internally
pub struct MmapManager {
    loader: Arc<MmapLoader>,
    meshes: DashMap<u32, Arc<NavMesh>>,
    query_pools: DashMap<u32, QueryPool>,
    query_pool_size: usize,
    max_query_nodes: u32,
    /// Per-map loading locks to prevent duplicate concurrent loads.
    loading_locks: DashMap<u32, Arc<parking_lot::Mutex<()>>>,
}

impl MmapManager {
    /// Create a new manager.
    ///
    /// # Arguments
    /// * `mmap_path` - Path to directory containing .mmap and .mmtile files
    /// * `query_pool_size` - Initial number of NavMeshQuery instances per map
    /// * `max_query_nodes` - Maximum nodes for pathfinding (typically 2048)
    pub fn new(
        mmap_path: impl AsRef<Path>,
        query_pool_size: usize,
        max_query_nodes: u32,
    ) -> Self {
        Self {
            loader: Arc::new(MmapLoader::new(mmap_path)),
            meshes: DashMap::new(),
            query_pools: DashMap::new(),
            query_pool_size,
            max_query_nodes,
            loading_locks: DashMap::new(),
        }
    }

    /// Get or load a navmesh for the given map.
    ///
    /// If the map is already loaded, returns the cached mesh immediately.
    /// Otherwise, loads the map parameters and all available tiles eagerly.
    ///
    /// # Tile Loading
    ///
    /// Individual tile failures are logged as warnings but do not fail the
    /// entire map load. This allows maps with some missing/corrupt tiles
    /// to still be usable for pathfinding in valid areas.
    ///
    /// # Errors
    ///
    /// Returns an error if:
    /// - The .mmap file cannot be loaded
    /// - NavMesh allocation or initialization fails
    /// - QueryPool creation fails
    pub fn get_or_load_mesh(&self, map_id: u32) -> Result<Arc<NavMesh>, MmapError> {
        // Check if already loaded (fast path)
        if let Some(mesh) = self.meshes.get(&map_id) {
            debug!("Map {} already loaded, returning cached mesh", map_id);
            return Ok(mesh.clone());
        }

        // Get or create a per-map loading lock to prevent duplicate loads
        let lock = self.loading_locks
            .entry(map_id)
            .or_insert_with(|| Arc::new(parking_lot::Mutex::new(())))
            .clone();

        // Serialize loading for this specific map
        let _guard = lock.lock();

        // Re-check after acquiring lock (another thread may have loaded it)
        if let Some(mesh) = self.meshes.get(&map_id) {
            debug!("Map {} loaded by another thread, returning cached mesh", map_id);
            return Ok(mesh.clone());
        }

        info!("Loading map {}", map_id);

        // Load map params from .mmap file
        let mmap_header = self.loader.load_map_params(map_id)?;

        // Convert to NavMeshParams (this also copies values out of packed struct)
        let nav_params = mmap_header.to_nav_mesh_params();

        debug!(
            "Map {} params: origin={:?}, tile_size={}x{}, max_tiles={}, max_polys={}",
            map_id,
            nav_params.orig,
            nav_params.tile_width,
            nav_params.tile_height,
            nav_params.max_tiles,
            nav_params.max_polys
        );

        // Create and initialize navmesh
        let mut mesh = NavMesh::new()?;
        mesh.init(&nav_params)?;
        debug!("NavMesh initialized for map {}", map_id);

        // Load all available tiles eagerly
        let tiles = self.loader.list_tiles(map_id);
        let total_tiles = tiles.len();
        let mut loaded_count = 0;
        let mut failed_count = 0;

        info!("Loading {} tiles for map {}", total_tiles, map_id);

        for (idx, coord) in tiles.iter().enumerate() {
            match self.loader.load_tile(map_id, coord.x, coord.y) {
                Ok(tile_data) => {
                    // Convert Vec<u8> to Box<[u8]> for add_tile
                    let tile_box: Box<[u8]> = tile_data.into_boxed_slice();

                    match mesh.add_tile(tile_box) {
                        Ok(_tile_ref) => {
                            loaded_count += 1;
                            // Log progress every 100 tiles
                            if (idx + 1) % 100 == 0 || idx + 1 == total_tiles {
                                debug!(
                                    "Loaded {}/{} tiles for map {}",
                                    idx + 1,
                                    total_tiles,
                                    map_id
                                );
                            }
                        }
                        Err(e) => {
                            failed_count += 1;
                            warn!(
                                "Failed to add tile ({}, {}) for map {}: {}",
                                coord.x, coord.y, map_id, e
                            );
                        }
                    }
                }
                Err(e) => {
                    failed_count += 1;
                    warn!(
                        "Failed to load tile ({}, {}) for map {}: {}",
                        coord.x, coord.y, map_id, e
                    );
                }
            }
        }

        info!(
            "Map {} loaded: {}/{} tiles successful, {} failed",
            map_id, loaded_count, total_tiles, failed_count
        );

        // Wrap in Arc for sharing
        let mesh = Arc::new(mesh);

        // Insert into cache
        self.meshes.insert(map_id, mesh.clone());

        // Create query pool for this map
        let pool = QueryPool::new(mesh.clone(), self.query_pool_size, self.max_query_nodes)?;
        self.query_pools.insert(map_id, pool);

        Ok(mesh)
    }

    /// Get the query pool for a map.
    ///
    /// Returns None if the map hasn't been loaded yet.
    /// Call `get_or_load_mesh()` first to ensure the map is loaded.
    pub fn get_query_pool(
        &self,
        map_id: u32,
    ) -> Option<dashmap::mapref::one::Ref<'_, u32, QueryPool>> {
        self.query_pools.get(&map_id)
    }

    /// Check if a map is loaded.
    pub fn is_loaded(&self, map_id: u32) -> bool {
        self.meshes.contains_key(&map_id)
    }

    /// Get list of loaded maps.
    pub fn loaded_maps(&self) -> Vec<u32> {
        self.meshes.iter().map(|r| *r.key()).collect()
    }

    /// Get the loader for direct file access.
    pub fn loader(&self) -> &MmapLoader {
        &self.loader
    }

    /// Unload a map to free memory.
    ///
    /// Removes the mesh and query pool from cache. Returns true if the
    /// map was loaded (and thus removed), false if it wasn't loaded.
    ///
    /// # Note
    ///
    /// Any existing `Arc<NavMesh>` references will remain valid until
    /// all references are dropped.
    pub fn unload_map(&self, map_id: u32) -> bool {
        // Remove query pool first (holds Arc<NavMesh>)
        self.query_pools.remove(&map_id);
        // Then remove mesh
        let removed = self.meshes.remove(&map_id).is_some();
        if removed {
            info!("Unloaded map {}", map_id);
        }
        removed
    }

    /// Get the number of loaded maps.
    pub fn loaded_map_count(&self) -> usize {
        self.meshes.len()
    }
}
