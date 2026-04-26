use axum::{routing::get, Router};
use tower_http::trace::TraceLayer;

use crate::app_state::AppState;

pub mod admin;
pub mod barrier;
pub mod health;
pub mod lockout;
pub mod role;
pub mod session;
pub mod vendor;

pub fn build_router(app_state: AppState) -> Router {
    Router::new()
        // Health
        .route("/health", get(health::health))
        // Session
        .route("/api/v1/session", get(session::get_session))
        .route("/api/v1/heartbeat", get(session::heartbeat))
        // Barrier
        .route("/api/v1/barrier/enter", get(barrier::barrier_enter))
        .route("/api/v1/barrier/poll", get(barrier::barrier_poll))
        .route("/api/v1/barrier/release", get(barrier::barrier_release))
        // Role
        .route("/api/v1/pull/advance", get(role::pull_advance))
        // Lockout
        .route("/api/v1/lockout/record", get(lockout::record_reset))
        // Vendor
        .route("/api/v1/vendor/request", get(vendor::vendor_request))
        // Admin
        .route("/api/v1/admin/reset", get(admin::reset))
        .with_state(app_state)
        .layer(TraceLayer::new_for_http())
}
