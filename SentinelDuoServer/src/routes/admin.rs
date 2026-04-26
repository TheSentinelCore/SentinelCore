use axum::{extract::State, Json};
use serde_json::{json, Value};

use crate::state::{SessionState, SharedState};

pub async fn reset(State(state): State<SharedState>) -> Json<Value> {
    let mut session = state.lock().unwrap();
    *session = SessionState::default();
    tracing::info!("session reset via admin endpoint");
    Json(json!({"ok": true}))
}
