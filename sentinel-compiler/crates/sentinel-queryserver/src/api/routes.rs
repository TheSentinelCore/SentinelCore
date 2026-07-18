/// Route Analysis API endpoints — Volume 4 §17

use axum::{extract::{State, Json}, response::Json as ResponseJson};
use serde::Deserialize;
use crate::{AppState, models::*, error::QueryResult};
use sentinel_schema::Waypoint;

#[derive(Debug, Deserialize)]
pub struct RouteAnalysisRequest {
    pub waypoints: Vec<Waypoint>,
}

#[axum::debug_handler]
pub async fn analyze(
    State(state): State<AppState>,
    Json(request): Json<RouteAnalysisRequest>,
) -> QueryResult<ResponseJson<RouteAnalysis>> {
    let cache_key = format!("{}::{:?}", crate::cache::keys::ROUTE_ANALYSIS, request);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(ResponseJson(serde_json::from_value(cached)?));
    }
    
    let result = state.service.analyze_route(request).await?;
    state.cache.insert(cache_key, serde_json::to_value(&result)?).await;
    Ok(ResponseJson(result))
}