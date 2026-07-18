/// Grind Suggestions API endpoints — Volume 4 §22

use axum::{extract::{State, Json}, response::Json as ResponseJson};
use serde::Deserialize;
use crate::{AppState, models::*, error::QueryResult};

#[derive(Debug, Deserialize)]
pub struct GrindSuggestRequest {
    pub polygon: Vec<[f32; 2]>,
    pub zone: String,
}

#[axum::debug_handler]
pub async fn suggest(
    State(state): State<AppState>,
    Json(request): Json<GrindSuggestRequest>,
) -> QueryResult<ResponseJson<GrindSuggestion>> {
    let cache_key = format!("{}::{:?}", crate::cache::keys::GRIND_SUGGEST, request);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(ResponseJson(serde_json::from_value(cached)?));
    }
    
    let result = state.service.suggest_grind(request).await?;
    state.cache.insert(cache_key, serde_json::to_value(&result)?).await;
    Ok(ResponseJson(result))
}