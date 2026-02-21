use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    Extension, Json,
};

use crate::blackboard::ServerBlackboard;
use crate::error::AppResult;
use crate::models::{PagedResponse, UtilityEntity};
use crate::routes::flight_master::{UtilityListParams, UtilityNearbyParams};
use crate::routes::helpers::ensure_map_exists;
use crate::storage::repositories::flight_master::{UtilityListQuery, UtilityNearbyQuery};
use crate::telemetry::RequestContext;
use crate::validation::{validate_limit, validate_radius};

pub async fn list_innkeepers(
    Path(map_id): Path<i64>,
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
    Query(params): Query<UtilityListParams>,
) -> AppResult<Json<PagedResponse<UtilityEntity>>> {
    ensure_map_exists(&state, map_id).map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let limit = validate_limit(params.limit, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let result = state
        .innkeeper
        .list_innkeepers(
            map_id,
            UtilityListQuery {
                limit,
                cursor: params.cursor,
                dataset_version: state.manifest.dataset_version.clone(),
            },
        )
        .map_err(|e| e.with_request_id(ctx.request_id))?;

    Ok(Json(result))
}

pub async fn nearby_innkeepers(
    Path(map_id): Path<i64>,
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
    Query(params): Query<UtilityNearbyParams>,
) -> AppResult<Json<PagedResponse<UtilityEntity>>> {
    ensure_map_exists(&state, map_id).map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let limit = validate_limit(params.limit, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;
    let radius = validate_radius(params.radius, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let result = state
        .innkeeper
        .nearby_innkeepers(
            map_id,
            UtilityNearbyQuery {
                x: params.x,
                y: params.y,
                radius,
                limit,
                cursor: params.cursor,
                dataset_version: state.manifest.dataset_version.clone(),
            },
        )
        .map_err(|e| e.with_request_id(ctx.request_id))?;

    Ok(Json(result))
}
