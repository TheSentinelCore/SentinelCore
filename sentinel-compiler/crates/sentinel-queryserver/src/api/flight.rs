/// Flight Master API endpoints — Volume 4 §12

use axum::{extract::State, response::Json};
use crate::{AppState, models::*, error::QueryResult};

#[axum::debug_handler]
pub async fn masters(
    State(state): State<AppState>,
) -> QueryResult<Json<Vec<FlightMaster>>> {
    let cache_key = crate::cache::keys::FLIGHT_MASTERS.to_string();
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let masters = state.service.get_flight_masters().await?;
    state.cache.insert(cache_key, serde_json::to_value(&masters)?).await;
    Ok(Json(masters))
}