/// Creature API endpoints — Volume 4 §9

use axum::{extract::{State, Path, Query}, response::Json};
use serde::Deserialize;
use crate::{AppState, models::*, error::QueryResult};

#[derive(Debug, Deserialize)]
pub struct CreatureSearchParams {
    pub name: Option<String>,
    pub family: Option<String>,
    pub faction: Option<String>,
    pub zone: Option<String>,
    pub level_min: Option<u32>,
    pub level_max: Option<u32>,
    pub elite: Option<bool>,
    pub limit: Option<u32>,
}

#[axum::debug_handler]
pub async fn search(
    State(state): State<AppState>,
    Query(params): Query<CreatureSearchParams>,
) -> QueryResult<Json<Vec<CreatureDetails>>> {
    let limit = params.limit.unwrap_or(50).min(200);
    
    let cache_key = format!("{}::{:?}", crate::cache::keys::CREATURE_DETAILS, params);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let results = state.service.search_creatures(params, limit).await?;
    state.cache.insert(cache_key, serde_json::to_value(&results)?).await;
    Ok(Json(results))
}

#[axum::debug_handler]
pub async fn spawns(
    State(state): State<AppState>,
    Path(entry): Path<u32>,
) -> QueryResult<Json<Vec<CreatureSpawn>>> {
    let cache_key = format!("{}::{}", crate::cache::keys::CREATURE_SPAWNS, entry);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let spawns = state.service.get_creature_spawns(entry).await?;
    state.cache.insert(cache_key, serde_json::to_value(&spawns)?).await;
    Ok(Json(spawns))
}