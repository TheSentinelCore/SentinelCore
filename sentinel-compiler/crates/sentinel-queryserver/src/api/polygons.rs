/// Polygon Analysis API endpoints — Volume 4 §16

use axum::{extract::{State, Json}, response::Json as ResponseJson};
use serde::Deserialize;
use crate::{AppState, models::*, error::QueryResult};

#[derive(Debug, Deserialize)]
pub struct PolygonAnalysisRequest {
    pub zone: String,
    pub polygon: Vec<[f32; 2]>,
}

#[axum::debug_handler]
pub async fn analyze(
    State(state): State<AppState>,
    Json(request): Json<PolygonAnalysisRequest>,
) -> QueryResult<ResponseJson<PolygonAnalysis>> {
    let cache_key = format!("{}::{:?}", crate::cache::keys::POLYGON_ANALYSIS, request);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(ResponseJson(serde_json::from_value(cached)?));
    }
    
    let result = state.service.analyze_polygon(request).await?;
    state.cache.insert(cache_key, serde_json::to_value(&result)?).await;
    Ok(ResponseJson(result))
}