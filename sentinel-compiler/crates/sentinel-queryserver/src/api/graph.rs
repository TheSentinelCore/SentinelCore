/// World Graph API endpoints — Volume 4 §24

use axum::{extract::{State, Path}, response::Json};
use crate::{AppState, models::*, error::QueryResult};

#[axum::debug_handler]
pub async fn node(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> QueryResult<Json<WorldGraphNode>> {
    let cache_key = format!("{}::{}", crate::cache::keys::WORLD_GRAPH, id);
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let result = state.service.get_world_graph_node(id).await?;
    state.cache.insert(cache_key, serde_json::to_value(&result)?).await;
    Ok(Json(result))
}