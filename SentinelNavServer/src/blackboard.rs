//! Server-wide shared state with trait-based service injection.
//!
//! `ServerBlackboard` replaces `AppState` as the handler state type.
//! Services are injected as trait objects, enabling testing and future
//! swappability without changing route handlers.

use std::sync::Arc;
use std::time::Instant;

use mmap_loader::MmapManager;
use tokio::sync::Semaphore;

use crate::cache::PathCache;
use crate::config::Config;
use crate::services::{
    CacheService, PathfindingService, RoutingService, SmoothingService, SpatialService,
    TacticalService,
};
use crate::state::Metrics;

/// Shared application state with injected service implementations.
///
/// Route handlers receive `State<Arc<ServerBlackboard>>` and delegate to
/// the appropriate service trait. The blackboard owns:
///
/// - **Services**: Trait objects for each domain (pathfinding, routing, etc.)
/// - **Infrastructure**: Mesh manager, semaphore, cache, config
/// - **Metrics**: Request counters and timing
///
/// Field names match the former `AppState` so existing `acquire_query!` macro
/// and handler code works without modification.
#[derive(Clone)]
pub struct ServerBlackboard {
    // -- Services (trait objects) --
    /// Core pathfinding: find, avoid, corridor, check.
    pub pathfinding: Arc<dyn PathfindingService>,
    /// Multi-stop and TSP route optimization.
    pub routing: Arc<dyn RoutingService>,
    /// Post-process path smoothing.
    pub smoothing: Arc<dyn SmoothingService>,
    /// Low-level navmesh queries: raycast, height, random, move.
    pub spatial: Arc<dyn SpatialService>,
    /// Combat-oriented paths: flee, cover, kite.
    pub tactical: Arc<dyn TacticalService>,
    /// Path result caching (trait object).
    pub cache: Arc<dyn CacheService>,

    // -- Infrastructure (same field names as former AppState) --
    /// Navigation mesh manager for loading and querying maps.
    pub mmap_manager: Arc<MmapManager>,
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
}
