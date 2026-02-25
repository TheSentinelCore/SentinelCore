//! Server-wide shared state with trait-based service injection.
//!
//! `ServerBlackboard` holds per-game `GameBundle`s (each with its own MmapManager
//! and service implementations) plus shared infrastructure (cache, metrics, config).

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

use mmap_loader::MmapManager;
use tokio::sync::Semaphore;

use crate::cache::PathCache;
use crate::config::Config;
use crate::services::{
    CacheService, PathfindingService, RoutingService, SpatialService,
    TacticalService,
};
use crate::state::Metrics;

/// Per-game resources: mmap manager and domain services.
///
/// Each game version (e.g., "tbc", "retail") gets its own bundle with
/// independent navmesh data and service instances.
pub struct GameBundle {
    /// Navigation mesh manager for this game's mmap files.
    pub mmap_manager: Arc<MmapManager>,
    /// Core pathfinding: find, avoid, corridor, check.
    pub pathfinding: Arc<dyn PathfindingService>,
    /// Multi-stop and TSP route optimization.
    pub routing: Arc<dyn RoutingService>,
    /// Low-level navmesh queries: raycast, height, random, move.
    pub spatial: Arc<dyn SpatialService>,
    /// Combat-oriented paths: flee, cover, kite.
    pub tactical: Arc<dyn TacticalService>,
}

/// Shared application state with per-game service bundles.
///
/// Route handlers receive `State<Arc<ServerBlackboard>>` and resolve the
/// appropriate `GameBundle` via `get_game()` before delegating to services.
#[derive(Clone)]
pub struct ServerBlackboard {
    // -- Per-game bundles --
    /// Game bundles keyed by game identifier (e.g., "tbc", "retail").
    pub games: HashMap<String, Arc<GameBundle>>,
    /// Default game identifier when no `?game=` param is provided.
    pub default_game: String,

    // -- Shared infrastructure --
    /// Path result caching (shared across all games).
    pub cache: Arc<dyn CacheService>,
    /// Semaphore for limiting concurrent pathfinding requests.
    pub request_semaphore: Arc<Semaphore>,
    /// Path cache for fast repeated lookups (direct access for handlers).
    pub path_cache: Arc<PathCache>,
    /// Application configuration.
    pub config: Arc<Config>,
    /// Request metrics.
    pub metrics: Arc<Metrics>,
    /// Server start time for uptime tracking.
    pub start_time: Instant,
}

impl ServerBlackboard {
    /// Resolve the game bundle for a request.
    ///
    /// If `game` is `None`, uses `default_game`. Returns an error if the
    /// game identifier is not found.
    pub fn get_game(&self, game: Option<&str>) -> Result<&Arc<GameBundle>, crate::error::AppError> {
        let key = game.unwrap_or(&self.default_game);
        self.games.get(key).ok_or_else(|| {
            let available: Vec<&String> = self.games.keys().collect();
            crate::error::AppError::BadRequest(format!(
                "Unknown game '{}'. Available: {:?}",
                key, available
            ))
        })
    }

    /// Try to acquire a request permit, returning 503 if overloaded.
    pub fn try_acquire_permit(
        &self,
    ) -> Result<tokio::sync::OwnedSemaphorePermit, crate::error::AppError> {
        self.request_semaphore
            .clone()
            .try_acquire_owned()
            .map_err(|_| crate::error::AppError::Overloaded)
    }

    /// Get server uptime in seconds.
    pub fn uptime_secs(&self) -> f64 {
        self.start_time.elapsed().as_secs_f64()
    }

    /// Total number of loaded maps across all games.
    pub fn total_loaded_map_count(&self) -> usize {
        self.games.values().map(|g| g.mmap_manager.loaded_map_count()).sum()
    }

    /// Get loaded maps per game.
    pub fn loaded_maps_by_game(&self) -> HashMap<String, Vec<u32>> {
        self.games
            .iter()
            .map(|(name, bundle)| (name.clone(), bundle.mmap_manager.loaded_maps()))
            .collect()
    }
}
