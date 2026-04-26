use axum::{
    extract::{Query, State},
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::{error::AppError, state::SharedState};

#[derive(Debug, Deserialize)]
pub struct AdvanceParams {
    pub client_id: String,
}

pub async fn pull_advance(
    State(state): State<SharedState>,
    Query(params): Query<AdvanceParams>,
) -> Result<Json<Value>, AppError> {
    if params.client_id.is_empty() {
        return Err(AppError::InvalidParams("client_id required".into()));
    }

    let mut session = state.lock().unwrap();

    if params.client_id == "mage_a" {
        session.mage_a_advance_ready = true;
    } else if params.client_id == "mage_b" {
        session.mage_b_advance_ready = true;
    } else {
        return Err(AppError::InvalidParams(format!("unknown client_id: {}", params.client_id)));
    }

    // If both ready: increment pull_index, toggle puller_id
    if session.mage_a_advance_ready && session.mage_b_advance_ready {
        session.pull_index += 1;
        session.puller_id = if session.puller_id == "mage_a" {
            "mage_b".to_string()
        } else {
            "mage_a".to_string()
        };
        session.mage_a_advance_ready = false;
        session.mage_b_advance_ready = false;

        tracing::info!(
            pull_index = session.pull_index,
            puller_id = %session.puller_id,
            "pull advanced"
        );
    }

    Ok(Json(json!({
        "new_pull_index": session.pull_index,
        "new_puller_id": session.puller_id,
        "farm_complete": false,  // Lua client decides based on profile
    })))
}
