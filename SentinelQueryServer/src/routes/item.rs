use std::sync::Arc;

use axum::extract::{Query, State};
use axum::{Extension, Json};
use serde::Deserialize;

use crate::blackboard::ServerBlackboard;
use crate::error::{AppError, AppResult};
use crate::models::ItemListResponse;
use crate::telemetry::RequestContext;

#[derive(Debug, Deserialize)]
pub struct ItemQueryParams {
    pub ids: String,
}

pub async fn get_items(
    State(state): State<Arc<ServerBlackboard>>,
    Extension(ctx): Extension<RequestContext>,
    Query(params): Query<ItemQueryParams>,
) -> AppResult<Json<ItemListResponse>> {
    let ids: Vec<i64> = params
        .ids
        .split(',')
        .filter_map(|s| s.trim().parse::<i64>().ok())
        .collect();

    if ids.is_empty() {
        return Err(
            AppError::invalid_params("ids parameter must contain at least one valid item id")
                .with_request_id(ctx.request_id),
        );
    }

    if ids.len() > 200 {
        return Err(
            AppError::invalid_params("maximum 200 item ids per request")
                .with_request_id(ctx.request_id),
        );
    }

    let items = state
        .item
        .get_items_by_ids(&ids)
        .map_err(|e| e.with_request_id(ctx.request_id))?;

    Ok(Json(ItemListResponse {
        count: items.len(),
        items,
    }))
}
