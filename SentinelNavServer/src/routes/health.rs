//! Health check endpoint.

use axum::{extract::State, Json};
use serde::Serialize;
use std::collections::HashMap;
use std::sync::atomic::Ordering;

use std::sync::Arc;

use crate::blackboard::ServerBlackboard;

/// Health check response.
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    /// Server status ("ok" or "error").
    pub status: String,
    /// Sentinel Navigation Server version.
    pub version: String,
    /// Server uptime in seconds.
    pub uptime_secs: f64,
    /// Total number of maps currently loaded across all games.
    pub loaded_map_count: usize,
    /// Loaded map IDs per game (e.g. {"tbc": [0, 1, 530], "retail": [0, 1]}).
    pub loaded_maps: HashMap<String, Vec<u32>>,
    /// Number of cached path entries.
    pub path_cache_size: usize,
    /// Request and cache metrics.
    pub metrics: MetricsResponse,
}

/// Metrics sub-response.
#[derive(Debug, Serialize)]
pub struct MetricsResponse {
    pub total_requests: u64,
    pub failed_requests: u64,
    pub cache_hits: u64,
    pub cache_misses: u64,
}

/// GET /health - Health check endpoint.
///
/// Returns server status, version, uptime, and loaded map information.
pub async fn health_check(State(state): State<Arc<ServerBlackboard>>) -> Json<HealthResponse> {
    let loaded_maps = state.loaded_maps_by_game();
    let loaded_map_count = state.total_loaded_map_count();

    Json(HealthResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        uptime_secs: state.uptime_secs(),
        loaded_map_count,
        loaded_maps,
        path_cache_size: state.path_cache.len(),
        metrics: MetricsResponse {
            total_requests: state.metrics.total_requests.load(Ordering::Relaxed),
            failed_requests: state.metrics.failed_requests.load(Ordering::Relaxed),
            cache_hits: state.path_cache.hit_count(),
            cache_misses: state.path_cache.miss_count(),
        },
    })
}
