use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    Extension, Json,
};
use serde::Deserialize;

use crate::blackboard::ServerBlackboard;
use crate::error::AppResult;
use crate::models::{PagedResponse, VendorEntity};
use crate::routes::helpers::{ensure_map_exists, parse_optional_bool};
use crate::storage::repositories::vendor::{VendorListQuery, VendorNearbyQuery};
use crate::telemetry::RequestContext;
use crate::validation::{parse_faction_filter, validate_limit, validate_radius};

#[derive(Debug, Deserialize)]
pub struct VendorListParams {
    pub limit: Option<u32>,
    pub cursor: Option<String>,
    pub require_sell: Option<String>,
    pub require_repair: Option<String>,
    pub faction: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct VendorNearbyParams {
    pub x: f64,
    pub y: f64,
    pub z: Option<f64>,
    pub radius: f64,
    pub limit: Option<u32>,
    pub cursor: Option<String>,
    pub require_sell: Option<String>,
    pub require_repair: Option<String>,
    pub faction: Option<String>,
}

pub async fn list_vendors(
    Path(map_id): Path<i64>,
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
    Query(params): Query<VendorListParams>,
) -> AppResult<Json<PagedResponse<VendorEntity>>> {
    ensure_map_exists(&state, map_id).map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let require_sell = parse_optional_bool(params.require_sell.as_deref(), "require_sell")
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?
        .unwrap_or(false);
    let require_repair = parse_optional_bool(params.require_repair.as_deref(), "require_repair")
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?
        .unwrap_or(false);

    let faction = parse_faction_filter(params.faction.as_deref())
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let limit = validate_limit(params.limit, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let result = state
        .vendor
        .list_vendors(
            map_id,
            VendorListQuery {
                limit,
                cursor: params.cursor,
                dataset_version: state.manifest.dataset_version.clone(),
                require_sell,
                require_repair,
                faction,
            },
        )
        .map_err(|e| e.with_request_id(ctx.request_id))?;

    Ok(Json(result))
}

pub async fn nearby_vendors(
    Path(map_id): Path<i64>,
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
    Query(params): Query<VendorNearbyParams>,
) -> AppResult<Json<PagedResponse<VendorEntity>>> {
    ensure_map_exists(&state, map_id).map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let _ = params.z;

    let require_sell = parse_optional_bool(params.require_sell.as_deref(), "require_sell")
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?
        .unwrap_or(false);
    let require_repair = parse_optional_bool(params.require_repair.as_deref(), "require_repair")
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?
        .unwrap_or(false);

    let faction = parse_faction_filter(params.faction.as_deref())
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let limit = validate_limit(params.limit, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;
    let radius = validate_radius(params.radius, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let result = state
        .vendor
        .nearby_vendors(
            map_id,
            VendorNearbyQuery {
                x: params.x,
                y: params.y,
                radius,
                limit,
                cursor: params.cursor,
                dataset_version: state.manifest.dataset_version.clone(),
                require_sell,
                require_repair,
                faction,
            },
        )
        .map_err(|e| e.with_request_id(ctx.request_id))?;

    Ok(Json(result))
}
