/// NPC API endpoints — Volume 4 §8

use axum::{extract::{State, Path, Query}, response::Json};
use serde::Deserialize;
use crate::{AppState, models::*, error::QueryResult};

#[axum::debug_handler]
pub async fn details(
    State(state): State<AppState>,
    Path(entry): Path<u32>,
) -> QueryResult<Json<NpcDetails>> {
    let cache_key = format!("{}::{}", crate::cache::keys::NPC_DETAILS, entry);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let npc = state.service.get_npc(entry).await?;
    state.cache.insert(cache_key, serde_json::to_value(&npc)?).await;
    Ok(Json(npc))
}

#[derive(Debug, Deserialize)]
pub struct NpcSearchParams {
    pub name: Option<String>,
    pub entry: Option<u32>,
    pub role: Option<String>,
    pub faction: Option<String>,
    pub zone: Option<String>,
    pub limit: Option<u32>,
}

#[axum::debug_handler]
pub async fn search(
    State(state): State<AppState>,
    Query(params): Query<NpcSearchParams>,
) -> QueryResult<Json<Vec<NpcSearchResult>>> {
    let limit = params.limit.unwrap_or(50).min(200);
    
    let cache_key = format!("{}::{:?}", crate::cache::keys::NPC_SEARCH, params);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let results = state.service.search_npcs(params, limit).await?;
    state.cache.insert(cache_key, serde_json::to_value(&results)?).await;
    Ok(Json(results))
}

#[derive(Debug, Deserialize)]
pub struct NearbyNpcsParams {
    pub x: f32,
    pub y: f32,
    pub radius: f32,
    pub zone: Option<String>,
}

#[axum::debug_handler]
pub async fn nearby(
    State(state): State<AppState>,
    Query(params): Query<NearbyNpcsParams>,
) -> QueryResult<Json<Vec<NpcSearchResult>>> {
    let cache_key = format!("{}::{:?}", crate::cache::keys::NPC_NEARBY, params);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let results = state.service.get_nearby_npcs(params).await?;
    state.cache.insert(cache_key, serde_json::to_value(&results)?).await;
    Ok(Json(results))
}