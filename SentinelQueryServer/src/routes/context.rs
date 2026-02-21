use std::sync::Arc;

use axum::{extract::Query, extract::State, Extension, Json};

use crate::blackboard::ServerBlackboard;
use crate::error::AppResult;
use crate::models::{ContextResolveRequest, ContextResolveResponse};
use crate::telemetry::RequestContext;

pub async fn resolve_context(
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
    Query(payload): Query<ContextResolveRequest>,
) -> AppResult<Json<ContextResolveResponse>> {
    let result = state
        .context
        .resolve_context(payload)
        .map_err(|e| e.with_request_id(ctx.request_id))?;
    Ok(Json(result))
}
