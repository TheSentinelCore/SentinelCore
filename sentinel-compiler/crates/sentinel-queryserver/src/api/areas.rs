/// Area Query API endpoints — Volume 4 §15

use axum::{extract::{State, Json}, response::Json as ResponseJson};
use serde::Deserialize;
use crate::{AppState, models::*, error::QueryResult};

#[derive(Debug, Deserialize)]
pub struct AreaQueryRequest {
    pub zone: String,
    pub polygon: Vec<[f32; 2]>,
}

#[axum::debug_handler]
pub async fn query(
    State(state): State<AppState>,
    Json(request): Json<AreaQueryRequest>,
) -> QueryResult<ResponseJson<AreaQueryResult>> {
    let cache_key = format!("{}::{:?}", crate::cache::keys::AREA_QUERY, request);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(ResponseJson(serde_json::from_value(cached)?));
    }
    
    let result = state.service.query_area(request).await?;
    state.cache.insert(cache_key, serde_json::to_value(&result)?).await;
    Ok(ResponseJson(result))
}