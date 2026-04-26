use axum::{
    extract::{Query, State},
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::{error::AppError, state::SharedState};

#[derive(Debug, Deserialize)]
pub struct VendorParams {
    pub client_id: String,
}

pub async fn vendor_request(
    State(state): State<SharedState>,
    Query(params): Query<VendorParams>,
) -> Result<Json<Value>, AppError> {
    if params.client_id.is_empty() {
        return Err(AppError::InvalidParams("client_id required".into()));
    }

    let mut session = state.lock().unwrap();
    session.vendor_requested_by = Some(params.client_id.clone());

    tracing::info!(client_id = %params.client_id, "vendor break requested");

    Ok(Json(json!({
        "vendor_break_active": true,
        "requested_by": params.client_id,
    })))
}
