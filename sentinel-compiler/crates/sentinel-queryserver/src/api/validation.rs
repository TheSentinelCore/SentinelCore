/// Validation API endpoints — Volume 4 §19

use axum::{extract::{State, Json}, response::Json as ResponseJson};
use crate::{AppState, models::*, error::QueryResult};

#[axum::debug_handler]
pub async fn validate(
    State(state): State<AppState>,
    Json(fragment): Json<serde_json::Value>,
) -> QueryResult<ResponseJson<ValidationResult>> {
    let result = state.service.validate_profile(fragment).await?;
    Ok(ResponseJson(result))
}