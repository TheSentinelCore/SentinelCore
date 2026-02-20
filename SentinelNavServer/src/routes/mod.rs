//! HTTP route handlers.

pub mod health;
pub mod intelligence;
pub mod path;
pub mod spatial;
pub mod tactical;

use std::sync::Arc;

use axum::{routing::get, Router};
use tower_http::trace::TraceLayer;

use crate::blackboard::ServerBlackboard;

/// Build the application router with all endpoints.
pub fn build_router(state: Arc<ServerBlackboard>) -> Router {
    Router::new()
        // Health check
        .route("/health", get(health::health_check))
        // Pathfinding endpoints
        .route("/api/v1/path", get(path::find_path))
        .route("/api/v1/path-random", get(path::find_path_random))
        // Path validation endpoints
        .route(
            "/api/v1/path/validate-snap",
            get(path::validate_path_snap),
        )
        .route(
            "/api/v1/path/validate-surface",
            get(path::validate_path_surface),
        )
        // Intelligence endpoints
        .route("/api/v1/path-multi", get(intelligence::path_multi))
        .route("/api/v1/path-tsp", get(intelligence::path_tsp))
        .route("/api/v1/path-avoid", get(intelligence::path_avoid))
        .route("/api/v1/path/check", get(intelligence::path_check))
        .route("/api/v1/path/corridor", get(intelligence::path_corridor))
        // Tactical endpoints
        .route("/api/v1/tactical/flee", get(tactical::flee))
        .route("/api/v1/tactical/los", get(tactical::los_cover))
        .route("/api/v1/tactical/kite", get(tactical::kite))
        // Spatial query endpoints
        .route("/api/v1/move", get(spatial::move_along_surface))
        .route("/api/v1/raycast", get(spatial::raycast))
        .route("/api/v1/random", get(spatial::random_point))
        .route("/api/v1/height", get(spatial::get_height))
        .route("/api/v1/heights", get(spatial::get_heights))
        .route("/api/v1/explore", get(spatial::explore_polygon))
        .route("/api/v1/explore-route", get(intelligence::explore_route))
        // Middleware
        .layer(TraceLayer::new_for_http())
        // Application state
        .with_state(state)
}
