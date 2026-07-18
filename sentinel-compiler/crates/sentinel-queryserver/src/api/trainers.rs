/// Trainer API endpoints — Volume 4 §11

use axum::{extract::{State, Path}, response::Json};
use crate::{AppState, models::*, error::QueryResult};

#[axum::debug_handler]
pub async fn details(
    State(state): State<AppState>,
    Path(entry): Path<u32>,
) -> QueryResult<Json<TrainerDetails>> {
    let cache_key = format!("{}::{}", crate::cache::keys::TRAINER_DETAILS, entry);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let trainer = state.service.get_trainer(entry).await?;
    state.cache.insert(cache_key, serde_json::to_value(&trainer)?).await;
    Ok(Json(trainer))
}