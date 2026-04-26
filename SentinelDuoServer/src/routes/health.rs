use axum::{extract::State, Json};
use serde_json::{json, Value};

use crate::state::SharedState;

pub async fn health(State(state): State<SharedState>) -> Json<Value> {
    let session = state.lock().unwrap();
    Json(json!({
        "status": "ok",
        "uptime_secs": session.uptime_secs(),
        "session_phase": session.phase,
        "clients_connected": session.clients_connected(),
        "pull_index": session.pull_index,
        "reset_count": session.lockout.reset_count,
        "near_lockout_limit": session.lockout.near_limit,
    }))
}
