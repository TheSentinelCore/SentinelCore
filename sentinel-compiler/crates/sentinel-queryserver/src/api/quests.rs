/// Quest API endpoints — Volume 4 §7

use axum::{extract::{State, Path, Query}, response::Json};
use serde::Deserialize;
use crate::{AppState, models::*, error::QueryResult};

#[derive(Debug, Deserialize)]
pub struct QuestSearchParams {
    pub query: Option<String>,
    pub zone: Option<String>,
    pub min_level: Option<u32>,
    pub max_level: Option<u32>,
    pub faction: Option<String>,
    pub limit: Option<u32>,
}

#[axum::debug_handler]
pub async fn search(
    State(state): State<AppState>,
    Query(params): Query<QuestSearchParams>,
) -> QueryResult<Json<Vec<QuestSearchResult>>> {
    let limit = params.limit.unwrap_or(50).min(200);
    
    let cache_key = format!("{}::{:?}", crate::cache::keys::QUEST_SEARCH, params);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let results = state.service.quests.search_quests(params, limit).await?;
    state.cache.insert(cache_key, serde_json::to_value(&results)?).await;
    Ok(Json(results))
}

#[axum::debug_handler]
pub async fn details(
    State(state): State<AppState>,
    Path(id): Path<u32>,
) -> QueryResult<Json<QuestDetails>> {
    let cache_key = format!("{}::{}", crate::cache::keys::QUEST_DETAILS, id);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let details = state.service.get_quest_details(id).await?;
    state.cache.insert(cache_key, serde_json::to_value(&details)?).await;
    Ok(Json(details))
}

#[derive(Debug, Deserialize)]
pub struct QuestChainParams {
    pub limit: Option<u32>,
}

#[axum::debug_handler]
pub async fn chain(
    State(state): State<AppState>,
    Path(id): Path<u32>,
    Query(params): Query<QuestChainParams>,
) -> QueryResult<Json<QuestChain>> {
    let limit = params.limit.unwrap_or(50);
    let cache_key = format!("quest_chain::{}:{}", id, limit);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let chain = state.service.get_quest_chain(id, limit).await?;
    state.cache.insert(cache_key, serde_json::to_value(&chain)?).await;
    Ok(Json(chain))
}

#[derive(Debug, Deserialize)]
pub struct NearbyQuestsParams {
    pub zone: String,
    pub x: f32,
    pub y: f32,
    pub radius: f32,
}

#[axum::debug_handler]
pub async fn nearby(
    State(state): State<AppState>,
    Query(params): Query<NearbyQuestsParams>,
) -> QueryResult<Json<Vec<QuestSearchResult>>> {
    let cache_key = format!("{}::{:?}", crate::cache::keys::QUEST_SEARCH, params);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let results = state.service.get_nearby_quests(params).await?;
    state.cache.insert(cache_key, serde_json::to_value(&results)?).await;
    Ok(Json(results))
}

#[derive(Debug, Deserialize)]
pub struct QuestNpcsParams {
    pub relation: Option<String>,
    pub map_id: Option<u32>,
}

#[axum::debug_handler]
pub async fn npcs(
    State(state): State<AppState>,
    Path(id): Path<u32>,
    Query(params): Query<QuestNpcsParams>,
) -> QueryResult<Json<Vec<NpcDetails>>> {
    let relation = params.relation.as_deref().unwrap_or("giver");
    let cache_key = format!("{}::{}:{}", crate::cache::keys::QUEST_NPCS, id, relation);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let npcs = state.service.get_quest_npcs(id, relation, params.map_id).await?;
    state.cache.insert(cache_key, serde_json::to_value(&npcs)?).await;
    Ok(Json(npcs))
}