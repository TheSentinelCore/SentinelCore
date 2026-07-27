use axum::{
    extract::Extension,
    routing::{get, post},
    Router,
};
use std::net::SocketAddr;

mod db;
mod handlers;
mod resolve;
mod search;
mod zone_names;

use db::Db;

#[tokio::main]
async fn main() {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Open the database (readonly)
    let db_path = std::env::var("SENTINEL_DB")
        .unwrap_or_else(|_| "./tbcmangos.sqlite".to_string());
    let db = Db::new(&db_path);

    // Build the router
    let app = Router::new()
        .route("/quests/search", get(handlers::search_quests))
        .route("/quest/:id", get(handlers::get_quest))
        .route("/quest/:id/chain", get(handlers::get_quest_chain))
        .route("/quest/:id/objectives", get(handlers::get_quest_objectives))
        .route("/npc/search", get(handlers::search_npcs))
        .route("/npc/:entry", get(handlers::get_npc))
        .route("/vendor/:entry", get(handlers::get_vendor))
        .route("/trainer/:entry", get(handlers::get_trainer))
        .route("/flight/:entry", get(handlers::get_flight))
        .route("/object/:entry", get(handlers::get_object))
        .route("/item/:item", get(handlers::get_item))
        .route("/item/:item/sources", get(handlers::get_item_sources))
        .route("/creatures/polygon", get(handlers::creatures_polygon))
        .route("/search", get(handlers::search))
        .route("/spawns/:type/:entry", get(handlers::get_spawns))
        .route("/resolve", post(handlers::resolve))
        .route("/validate", post(handlers::validate))
        .route("/travel/estimate", post(handlers::travel_estimate))
        .layer(Extension(db))
        .fallback(handler_404);

    // Run it
    let addr = SocketAddr::from(([127, 0, 0, 1], 3030));
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    tracing::info!("listening on {}", addr);
    axum::serve(listener, app).await.unwrap();
}

async fn handler_404() -> impl axum::response::IntoResponse {
    (axum::http::StatusCode::NOT_FOUND, "Not found")
}