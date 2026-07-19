/// Quest Hub Analysis API endpoints — Volume 4 §18

use axum::{extract::{State, Path}, response::Json};
use crate::{AppState, models::*, error::QueryResult};

#[axum::debug_handler]
pub async fn analysis(
    State(state): State<AppState>,
    Path(entry): Path<u32>,
) -> QueryResult<Json<QuestHubAnalysis>> {
    let cache_key = format!("{}::{}", crate::cache::keys::QUEST_HUB_ANALYSIS, entry);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let result = state.service.analyze_quest_hub(entry).await?;
    state.cache.insert(cache_key, serde_json::to_value(&result)?).await;
    Ok(Json(result))
}