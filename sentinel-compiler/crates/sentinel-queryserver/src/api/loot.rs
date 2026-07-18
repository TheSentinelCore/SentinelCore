/// Loot Lookup API endpoints — Volume 4 §23

use axum::{extract::{State, Path}, response::Json};
use crate::{AppState, models::*, error::QueryResult};

#[axum::debug_handler]
pub async fn drops(
    State(state): State<AppState>,
    Path(item_id): Path<u32>,
) -> QueryResult<Json<ItemDrops>> {
    let cache_key = format!("{}::{}", crate::cache::keys::ITEM_DROPS, item_id);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let result = state.service.get_item_drops(item_id).await?;
    state.cache.insert(cache_key, serde_json::to_value(&result)?).await;
    Ok(Json(result))
}