//! Application state shared across handlers.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::Semaphore;

use crate::cache::PathCache;
use crate::config::Config;
use tc_mmap::MmapManager;

/// Server-wide request metrics.
pub struct Metrics {
    pub total_requests: AtomicU64,
    pub failed_requests: AtomicU64,
}

impl Metrics {
    pub fn new() -> Self {
        Self {
            total_requests: AtomicU64::new(0),
            failed_requests: AtomicU64::new(0),
        }
    }
}

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
    /// Request metrics.
    pub metrics: Arc<Metrics>,
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
            metrics: Arc::new(Metrics::new()),
        })
    }

    /// Get server uptime in seconds.
    pub fn uptime_secs(&self) -> f64 {
        self.start_time.elapsed().as_secs_f64()
    }

    /// Try to acquire a request permit, returning 503 if overloaded.
    pub fn try_acquire_permit(&self) -> Result<tokio::sync::OwnedSemaphorePermit, crate::error::AppError> {
        self.request_semaphore.clone().try_acquire_owned()
            .map_err(|_| crate::error::AppError::Overloaded)
    }
}
