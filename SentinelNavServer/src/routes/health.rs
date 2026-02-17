//! Health check endpoint.

use axum::{extract::State, Json};
use serde::Serialize;

use crate::state::AppState;

/// Health check response.
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    /// Server status ("ok" or "error").
    pub status: String,
    /// NavBuddy version.
    pub version: String,
    /// Server uptime in seconds.
    pub uptime_secs: f64,
    /// Number of maps currently loaded.
    pub loaded_map_count: usize,
    /// List of loaded map IDs.
    pub loaded_maps: Vec<u32>,
    /// Number of cached path entries.
    pub path_cache_size: usize,
}

/// GET /health - Health check endpoint.
///
/// Returns server status, version, uptime, and loaded map information.
pub async fn health_check(State(state): State<AppState>) -> Json<HealthResponse> {
    let loaded_maps = state.mmap_manager.loaded_maps();

    Json(HealthResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        uptime_secs: state.uptime_secs(),
        loaded_map_count: loaded_maps.len(),
        loaded_maps,
        path_cache_size: state.path_cache.len(),
    })
}
