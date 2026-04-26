use axum::{
    extract::{Query, State},
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::time::Instant;

use crate::{
    config::Config,
    error::AppError,
    state::{BarrierState, SharedState},
};

const VALID_BARRIERS: &[&str] = &[
    "enter_instance",
    "pull_start",
    "ice_block_up",
    "ice_block_cancel",
    "pull_complete",
    "loot_complete",
    "ready_to_exit",
    "ready_to_reset",
    "ready_to_vendor",
    "vendor_complete",
    "return_complete",
];

#[derive(Debug, Deserialize)]
pub struct BarrierParams {
    pub client_id: String,
    pub name: String,
}

pub async fn barrier_enter(
    State(state): State<SharedState>,
    Query(params): Query<BarrierParams>,
) -> Result<Json<Value>, AppError> {
    if params.client_id.is_empty() {
        return Err(AppError::InvalidParams("client_id required".into()));
    }
    if !VALID_BARRIERS.contains(&params.name.as_str()) {
        return Err(AppError::InvalidParams(format!("unknown barrier: {}", params.name)));
    }

    let mut session = state.lock().unwrap();

    let barrier = session.barriers.entry(params.name.clone()).or_insert_with(|| {
        BarrierState {
            name: params.name.clone(),
            mage_a_ready: false,
            mage_b_ready: false,
            entered_at: None,
        }
    });

    // Set entered_at on first entry
    if barrier.entered_at.is_none() {
        barrier.entered_at = Some(Instant::now());
    }

    if params.client_id == "mage_a" {
        barrier.mage_a_ready = true;
    } else if params.client_id == "mage_b" {
        barrier.mage_b_ready = true;
    }

    let both_ready = barrier.both_ready();
    let partner_ready = if params.client_id == "mage_a" { barrier.mage_b_ready } else { barrier.mage_a_ready };

    tracing::info!(
        client_id = %params.client_id,
        barrier = %params.name,
        both_ready = both_ready,
        "barrier enter"
    );

    Ok(Json(json!({
        "barrier": params.name,
        "your_ready": true,
        "partner_ready": partner_ready,
        "both_ready": both_ready,
        "waiting_ms": 0u64,
    })))
}

pub async fn barrier_poll(
    State(state): State<SharedState>,
    State(config): State<Config>,
    Query(params): Query<BarrierParams>,
) -> Result<Json<Value>, AppError> {
    if params.client_id.is_empty() {
        return Err(AppError::InvalidParams("client_id required".into()));
    }

    let session = state.lock().unwrap();

    let (both_ready, partner_ready, waiting_ms, your_ready) = if let Some(barrier) = session.barriers.get(&params.name) {
        let your_ready = if params.client_id == "mage_a" { barrier.mage_a_ready } else { barrier.mage_b_ready };
        let partner_ready = if params.client_id == "mage_a" { barrier.mage_b_ready } else { barrier.mage_a_ready };
        (barrier.both_ready(), partner_ready, barrier.waiting_ms(), your_ready)
    } else {
        (false, false, 0, false)
    };

    // Check for partner disconnection timeout
    let partner_id = if params.client_id == "mage_a" { "mage_b" } else { "mage_a" };
    let partner_state = if partner_id == "mage_a" { &session.mage_a } else { &session.mage_b };
    let partner_disconnected = !partner_state.connected
        && waiting_ms > config.session.barrier_timeout_ms;

    Ok(Json(json!({
        "barrier": params.name,
        "your_ready": your_ready,
        "partner_ready": partner_ready,
        "both_ready": both_ready,
        "waiting_ms": waiting_ms,
        "partner_disconnected": partner_disconnected,
    })))
}

pub async fn barrier_release(
    State(state): State<SharedState>,
    Query(params): Query<BarrierParams>,
) -> Result<Json<Value>, AppError> {
    if params.client_id.is_empty() {
        return Err(AppError::InvalidParams("client_id required".into()));
    }

    let mut session = state.lock().unwrap();

    if let Some(barrier) = session.barriers.get_mut(&params.name) {
        if params.client_id == "mage_a" {
            barrier.mage_a_ready = false;
        } else if params.client_id == "mage_b" {
            barrier.mage_b_ready = false;
        }

        // If both cleared, remove the barrier entry
        if !barrier.mage_a_ready && !barrier.mage_b_ready {
            session.barriers.remove(&params.name);
        }
    }

    Ok(Json(json!({"ok": true})))
}
