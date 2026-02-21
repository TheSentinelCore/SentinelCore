use std::sync::Arc;

use axum::{extract::State, Json};

use crate::blackboard::ServerBlackboard;
use crate::error::AppResult;
use crate::models::HealthResponse;
use crate::state::StartupState;

pub async fn health_check(
    State(state): State<Arc<ServerBlackboard>>,
) -> AppResult<Json<HealthResponse>> {
    let (startup, _) = state.startup_status.snapshot();
    let status = match startup {
        StartupState::Ready => "ok",
        StartupState::Importing => "degraded",
        StartupState::Init | StartupState::Failed => "failed",
    };

    Ok(Json(HealthResponse {
        status: status.to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        uptime_secs: state.start_time.elapsed().as_secs(),
        dataset_version: state.manifest.dataset_version.clone(),
        game_version: "tbc".to_string(),
    }))
}
