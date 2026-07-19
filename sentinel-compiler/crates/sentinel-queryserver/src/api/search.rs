/// Search Everywhere API endpoints — Volume 4 §20

use axum::{extract::{State, Query}, response::Json};
use serde::Deserialize;
use crate::{AppState, models::*, error::QueryResult};

#[derive(Debug, Deserialize)]
pub struct SearchParams {
    pub query: String,
    pub limit: Option<u32>,
}

#[axum::debug_handler]
pub async fn search_all(
    State(state): State<AppState>,
    Query(params): Query<SearchParams>,
) -> QueryResult<Json<SearchResult>> {
    let limit = params.limit.unwrap_or(20).min(100);
    
    let cache_key = format!("{}::{:?}", crate::cache::keys::SEARCH_ALL, params);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let results = state.service.search_all(&params.query, limit).await?;
    state.cache.insert(cache_key, serde_json::to_value(&results)?).await;
    Ok(Json(results))
}