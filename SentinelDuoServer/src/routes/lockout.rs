use axum::{
    extract::{Query, State},
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::time::Instant;

use crate::{config::Config, error::AppError, state::SharedState};

#[derive(Debug, Deserialize)]
pub struct LockoutParams {
    pub client_id: String,
}

pub async fn record_reset(
    State(state): State<SharedState>,
    State(config): State<Config>,
    Query(params): Query<LockoutParams>,
) -> Result<Json<Value>, AppError> {
    if params.client_id.is_empty() {
        return Err(AppError::InvalidParams("client_id required".into()));
    }

    let mut session = state.lock().unwrap();
    let now = Instant::now();

    // Check if window has expired (> 1 hour since window_start)
    if let Some(window_start) = session.lockout.window_start {
        if now.duration_since(window_start).as_secs() >= 3600 {
            session.lockout.reset_count = 0;
            session.lockout.window_start = Some(now);
            session.lockout.near_limit = false;
        }
    } else {
        session.lockout.window_start = Some(now);
    }

    session.lockout.reset_count += 1;
    session.lockout.near_limit = session.lockout.reset_count >= config.lockout.warn_at;
    let must_wait = session.lockout.reset_count >= config.lockout.max_resets_per_hour;

    let wait_remaining_secs = if must_wait {
        let elapsed = session.lockout.window_start.unwrap().elapsed().as_secs();
        3600u64.saturating_sub(elapsed)
    } else {
        0
    };

    let window_resets_at_secs = if let Some(window_start) = session.lockout.window_start {
        let elapsed = window_start.elapsed().as_secs();
        3600u64.saturating_sub(elapsed)
    } else {
        3600
    };

    tracing::info!(
        client_id = %params.client_id,
        reset_count = session.lockout.reset_count,
        near_limit = session.lockout.near_limit,
        must_wait = must_wait,
        "lockout reset recorded"
    );

    Ok(Json(json!({
        "reset_count": session.lockout.reset_count,
        "near_limit": session.lockout.near_limit,
        "must_wait": must_wait,
        "wait_remaining_secs": wait_remaining_secs,
        "window_resets_at_secs": window_resets_at_secs,
    })))
}
