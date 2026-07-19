/// Vendor API endpoints — Volume 4 §10

use axum::{extract::{State, Path}, response::Json};
use crate::{AppState, models::*, error::QueryResult};

#[axum::debug_handler]
pub async fn details(
    State(state): State<AppState>,
    Path(entry): Path<u32>,
) -> QueryResult<Json<VendorDetails>> {
    let cache_key = format!("{}::{}", crate::cache::keys::VENDOR_DETAILS, entry);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let vendor = state.service.get_vendor(entry).await?;
    state.cache.insert(cache_key, serde_json::to_value(&vendor)?).await;
    Ok(Json(vendor))
}