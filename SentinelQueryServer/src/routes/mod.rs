pub mod context;
pub mod entities;
pub mod flight_master;
pub mod health;
pub mod helpers;
pub mod innkeeper;
pub mod meta;
pub mod middleware;
pub mod trainer;
pub mod vendor;

use std::sync::Arc;

use axum::{routing::get, Router};

use crate::blackboard::ServerBlackboard;

pub fn build_router(state: Arc<ServerBlackboard>) -> Router {
    Router::new()
        .route("/health", get(health::health_check))
        .route("/api/v1/meta/dataset", get(meta::dataset_meta))
        .route("/api/v1/context/resolve", get(context::resolve_context))
        .route("/api/v1/maps/{map_id}/vendors", get(vendor::list_vendors))
        .route(
            "/api/v1/maps/{map_id}/vendors/nearby",
            get(vendor::nearby_vendors),
        )
        .route(
            "/api/v1/maps/{map_id}/trainers",
            get(trainer::list_trainers),
        )
        .route(
            "/api/v1/maps/{map_id}/trainers/nearby",
            get(trainer::nearby_trainers),
        )
        .route("/api/v1/trainers/{entry}", get(trainer::trainer_detail))
        .route(
            "/api/v1/trainers/{entry}/spells",
            get(trainer::trainer_spells),
        )
        .route(
            "/api/v1/maps/{map_id}/flight-masters",
            get(flight_master::list_flight_masters),
        )
        .route(
            "/api/v1/maps/{map_id}/flight-masters/nearby",
            get(flight_master::nearby_flight_masters),
        )
        .route(
            "/api/v1/maps/{map_id}/innkeepers",
            get(innkeeper::list_innkeepers),
        )
        .route(
            "/api/v1/maps/{map_id}/innkeepers/nearby",
            get(innkeeper::nearby_innkeepers),
        )
        .route(
            "/api/v1/maps/{map_id}/entities/nearby",
            get(entities::nearby_entities),
        )
        .layer(axum::middleware::from_fn_with_state(
            state.clone(),
            middleware::request_tracking,
        ))
        .with_state(state)
}
