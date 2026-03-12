use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    Extension, Json,
};
use serde::Deserialize;

use crate::blackboard::ServerBlackboard;
use crate::error::AppResult;
use crate::models::UnifiedEntity;
use crate::routes::helpers::{ensure_map_exists, parse_optional_bool};
use crate::storage::repositories::entity::{UnifiedNearbyQuery, UnifiedNearbyResponse};
use crate::telemetry::RequestContext;
use crate::validation::{
    parse_entity_types, parse_faction_filter, parse_trainer_type, validate_limit, validate_radius,
};

#[derive(Debug, Deserialize)]
pub struct UnifiedNearbyParams {
    pub x: f64,
    pub y: f64,
    pub radius: f64,
    pub types: String,
    pub limit: Option<u32>,
    pub cursor: Option<String>,
    pub require_sell: Option<String>,
    pub require_repair: Option<String>,
    pub faction: Option<String>,
    pub trainer_type: Option<String>,
    pub class_id: Option<i64>,
    pub profession_id: Option<i64>,
}

pub async fn nearby_entities(
    Path(map_id): Path<i64>,
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
    Query(params): Query<UnifiedNearbyParams>,
) -> AppResult<Json<UnifiedNearbyResponse>> {
    ensure_map_exists(&state, map_id).map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let limit = validate_limit(params.limit, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;
    let radius = validate_radius(params.radius, &state.config)
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;
    let types =
        parse_entity_types(&params.types).map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let require_sell = parse_optional_bool(params.require_sell.as_deref(), "require_sell")
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?
        .unwrap_or(false);
    let require_repair = parse_optional_bool(params.require_repair.as_deref(), "require_repair")
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?
        .unwrap_or(false);

    let faction = parse_faction_filter(params.faction.as_deref())
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;
    let trainer_type = parse_trainer_type(params.trainer_type.as_deref())
        .map_err(|e| e.with_request_id(ctx.request_id.clone()))?;

    let result = state
        .entity
        .nearby_entities(
            map_id,
            UnifiedNearbyQuery {
                x: params.x,
                y: params.y,
                radius,
                limit,
                cursor: params.cursor,
                dataset_version: state.manifest.dataset_version.clone(),
                types,
                require_sell,
                require_repair,
                faction,
                trainer_type,
                class_id: params.class_id,
                profession_id: params.profession_id,
            },
        )
        .map_err(|e| e.with_request_id(ctx.request_id))?;

    Ok(Json(result))
}

#[allow(dead_code)]
fn _type_for_docs(_entity: UnifiedEntity) {}
