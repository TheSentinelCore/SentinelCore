/// Blueprint Suggestions API endpoints — Volume 4 §21

use axum::{extract::{State, Json}, response::Json as ResponseJson};
use serde::Deserialize;
use crate::{AppState, models::*, error::QueryResult};

#[derive(Debug, Deserialize)]
pub struct BlueprintSuggestRequest {
    pub npcs: Vec<u32>,
    pub quests: Vec<u32>,
    pub vendors: Vec<u32>,
}

#[axum::debug_handler]
pub async fn suggest(
    State(state): State<AppState>,
    Json(request): Json<BlueprintSuggestRequest>,
) -> QueryResult<ResponseJson<BlueprintSuggestion>> {
    let cache_key = format!("{}::{:?}", crate::cache::keys::BLUEPRINT_SUGGEST, request);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(ResponseJson(serde_json::from_value(cached)?));
    }
    
    let result = state.service.suggest_blueprint(request).await?;
    state.cache.insert(cache_key, serde_json::to_value(&result)?).await;
    Ok(ResponseJson(result))
}