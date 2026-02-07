//! Application state shared across handlers.

use std::sync::Arc;
use std::time::Instant;
use tokio::sync::Semaphore;

use crate::cache::PathCache;
use crate::config::Config;
use tc_mmap::MmapManager;

/// Shared application state.
#[derive(Clone)]
pub struct AppState {
    /// Application configuration.
    pub config: Arc<Config>,
    /// Navigation mesh manager for loading and querying maps.
    pub mmap_manager: Arc<MmapManager>,
    /// Semaphore for limiting concurrent pathfinding requests.
    pub request_semaphore: Arc<Semaphore>,
    /// Path cache for fast repeated lookups.
    pub path_cache: Arc<PathCache>,
    /// Server start time for uptime tracking.
    pub start_time: Instant,
}

impl AppState {
    /// Create new application state.
    ///
    /// This initializes the MmapManager and preloads any configured maps.
    pub fn new(config: Config) -> anyhow::Result<Self> {
        // Create mmap manager
        let mmap_manager = MmapManager::new(
            &config.navmesh.mmap_path,
            config.pathfinding.query_pool_size,
            2048, // max_query_nodes - standard for WoW pathfinding
        );

        // Preload configured maps
        for &map_id in &config.navmesh.preload_maps {
            tracing::info!("Preloading map {}", map_id);
            match mmap_manager.get_or_load_mesh(map_id) {
                Ok(_) => tracing::info!("Successfully preloaded map {}", map_id),
                Err(e) => tracing::warn!("Failed to preload map {}: {}", map_id, e),
            }
        }

        Ok(Self {
            config: Arc::new(config.clone()),
            mmap_manager: Arc::new(mmap_manager),
            request_semaphore: Arc::new(Semaphore::new(
                config.server.max_concurrent_requests,
            )),
            path_cache: Arc::new(PathCache::new()),
            start_time: Instant::now(),
        })
    }

    /// Get server uptime in seconds.
    pub fn uptime_secs(&self) -> f64 {
        self.start_time.elapsed().as_secs_f64()
    }
}
