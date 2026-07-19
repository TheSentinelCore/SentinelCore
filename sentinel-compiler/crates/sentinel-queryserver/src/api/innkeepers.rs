/// Innkeeper API endpoints — Volume 4 §14

use axum::{extract::State, response::Json};
use crate::{AppState, models::*, error::QueryResult};

#[axum::debug_handler]
pub async fn list(
    State(state): State<AppState>,
) -> QueryResult<Json<Vec<Innkeeper>>> {
    let cache_key = crate::cache::keys::INNKEEPERS.to_string();
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let innkeepers = state.service.get_innkeepers().await?;
    state.cache.insert(cache_key, serde_json::to_value(&innkeepers)?).await;
    Ok(Json(innkeepers))
}