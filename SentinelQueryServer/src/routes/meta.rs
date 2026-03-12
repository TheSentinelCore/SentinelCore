use std::sync::Arc;

use axum::{extract::State, Extension, Json};

use crate::blackboard::ServerBlackboard;
use crate::error::AppResult;
use crate::models::DatasetManifest;
use crate::telemetry::RequestContext;

pub async fn dataset_meta(
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
) -> AppResult<Json<DatasetManifest>> {
    let manifest = state
        .meta
        .get_manifest()
        .map_err(|e| e.with_request_id(ctx.request_id))?;
    Ok(Json(manifest))
}
