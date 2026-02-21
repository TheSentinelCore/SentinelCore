use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    Extension, Json,
};
use serde::Deserialize;

use crate::blackboard::ServerBlackboard;
use crate::error::AppResult;
use crate::models::{PagedResponse, TrainerDetail, TrainerEntity, TrainerSpell};
use crate::routes::helpers::ensure_map_exists;
use crate::storage::repositories::trainer::{TrainerListQuery, TrainerNearbyQuery};
use crate::telemetry::RequestContext;
use crate::validation::{parse_trainer_type, validate_limit, validate_radius};

#[derive(Debug, Deserialize)]
pub struct TrainerListParams {
    pub trainer_type: Option<String>,
    pub class_id: Option<i64>,
    pub profession_id: Option<i64>,
    pub limit: Option<u32>,
    pub cursor: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct TrainerNearbyParams {
    pub x: f64,
    pub y: f64,
    pub radius: f64,
    pub trainer_type: Option<String>,
    pub class_id: Option<i64>,
    pub profession_id: Option<i64>,
    pub limit: Option<u32>,
    pub cursor: Option<String>,
}

pub async fn list_trainers(
    Path(map_id): Path<i64>,
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
    Query(params): Query<TrainerListParams>,
) -> AppResult<Json<PagedResponse<TrainerEntity>>> {
    ensure_map_exists(&state, map_id).map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let trainer_type = parse_trainer_type(params.trainer_type.as_deref())
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;
    let limit = validate_limit(params.limit, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let result = state
        .trainer
        .list_trainers(
            map_id,
            TrainerListQuery {
                limit,
                cursor: params.cursor,
                dataset_version: state.manifest.dataset_version.clone(),
                trainer_type,
                class_id: params.class_id,
                profession_id: params.profession_id,
            },
        )
        .map_err(|e| e.with_request_id(ctx.request_id))?;

    Ok(Json(result))
}

pub async fn nearby_trainers(
    Path(map_id): Path<i64>,
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
    Query(params): Query<TrainerNearbyParams>,
) -> AppResult<Json<PagedResponse<TrainerEntity>>> {
    ensure_map_exists(&state, map_id).map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let trainer_type = parse_trainer_type(params.trainer_type.as_deref())
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;
    let limit = validate_limit(params.limit, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;
    let radius = validate_radius(params.radius, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let result = state
        .trainer
        .nearby_trainers(
            map_id,
            TrainerNearbyQuery {
                x: params.x,
                y: params.y,
                radius,
                limit,
                cursor: params.cursor,
                dataset_version: state.manifest.dataset_version.clone(),
                trainer_type,
                class_id: params.class_id,
                profession_id: params.profession_id,
            },
        )
        .map_err(|e| e.with_request_id(ctx.request_id))?;

    Ok(Json(result))
}

pub async fn trainer_detail(
    Path(entry): Path<i64>,
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
) -> AppResult<Json<TrainerDetail>> {
    let result = state
        .trainer
        .trainer_detail(entry)
        .map_err(|e| e.with_request_id(ctx.request_id))?;
    Ok(Json(result))
}

pub async fn trainer_spells(
    Path(entry): Path<i64>,
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
) -> AppResult<Json<Vec<TrainerSpell>>> {
    let result = state
        .trainer
        .trainer_spells(entry)
        .map_err(|e| e.with_request_id(ctx.request_id))?;
    Ok(Json(result))
}
