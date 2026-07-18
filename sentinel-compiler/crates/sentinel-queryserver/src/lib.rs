//! Sentinel QueryServer — Mangos database semantic query layer
//!
//! Volume 4: QueryServer Architecture
//!
//! Provides stateless, cacheable HTTP API over Mangos TBC SQLite database.
//! The editor never queries SQLite directly — everything goes through QueryServer.
//!
//! See: docs/adr/004-queryserver.md

pub mod api;
pub mod services;
pub mod cache;
pub mod error;
pub mod models;
pub mod sqlite;

use moka::future::Cache;
use rusqlite::Connection;

/// Helper to run blocking database operations in a thread pool
/// This makes the future Send by running the blocking operation in a thread pool
pub async fn run_blocking<F, R>(f: F) -> anyhow::Result<R>
where
    F: FnOnce() -> anyhow::Result<R> + Send + 'static,
    R: Send + 'static,
{
    tokio::task::spawn_blocking(f)
        .await
        .map_err(|e| anyhow::anyhow!("Task join error: {}", e))?
}

/// Get a database connection from the global pool
pub async fn get_db_connection() -> anyhow::Result<std::sync::Arc<tokio::sync::Mutex<Connection>>> {
    // For now, we create a new connection each time
    // In production, you'd want a proper connection pool
    let conn = Connection::open("/home/levi/Projects/SentinelCore/Database/tbcmangos.sqlite")?;
    conn.execute_batch(r#"
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        PRAGMA cache_size = -32768;
        PRAGMA temp_store = MEMORY;
        PRAGMA mmap_size = 268435456;
        PRAGMA page_size = 4096;
    "#)?;
    Ok(std::sync::Arc::new(tokio::sync::Mutex::new(conn)))
}

/// QueryServer application state
#[derive(Clone)]
pub struct AppState {
    pub service: crate::services::QueryService,
    pub cache: Cache<String, serde_json::Value>,
    pub start_time: std::time::Instant,
}

impl AppState {
    pub async fn new(db_path: String) -> anyhow::Result<Self> {
        let conn = Connection::open(&db_path)?;
        // Performance pragmas
        conn.execute_batch(r#"
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA cache_size = -32768;
            PRAGMA temp_store = MEMORY;
            PRAGMA mmap_size = 268435456;
            PRAGMA page_size = 4096;
        "#)?;
        
        let db = std::sync::Arc::new(tokio::sync::Mutex::new(conn));
        let service = crate::services::QueryService::new(db)?;
        let cache = crate::cache::create_cache();
        Ok(Self {
            service,
            cache,
            start_time: std::time::Instant::now(),
        })
    }
}

/// Create the Axum router with all API routes
pub fn create_router(state: AppState) -> axum::Router {
    axum::Router::new()
        .route("/health", axum::routing::get(health))
        // Quest endpoints
        .route("/api/v1/quests/search", axum::routing::get(api::quests::search))
        .route("/api/v1/quests/:id", axum::routing::get(api::quests::details))
        .route("/api/v1/quests/:id/chain", axum::routing::get(api::quests::chain))
        .route("/api/v1/quests/near", axum::routing::get(api::quests::nearby))
        .route("/api/v1/quests/:id/npcs", axum::routing::get(api::quests::npcs))
        // NPC endpoints
        .route("/api/v1/npcs/:entry", axum::routing::get(api::npcs::details))
        .route("/api/v1/npcs/search", axum::routing::get(api::npcs::search))
        .route("/api/v1/npcs/near", axum::routing::get(api::npcs::nearby))
        // Creature endpoints
        .route("/api/v1/creatures/search", axum::routing::get(api::creatures::search))
        .route("/api/v1/creatures/:entry/spawns", axum::routing::get(api::creatures::spawns))
        // Vendor endpoints
        .route("/api/v1/vendors/:entry", axum::routing::get(api::vendors::details))
        // Trainer endpoints
        .route("/api/v1/trainers/:entry", axum::routing::get(api::trainers::details))
        // Flight master endpoints
        .route("/api/v1/flightmasters", axum::routing::get(api::flight::masters))
        // Mailbox endpoints
        .route("/api/v1/mailboxes", axum::routing::get(api::mailboxes::list))
        // Innkeeper endpoints
        .route("/api/v1/innkeepers", axum::routing::get(api::innkeepers::list))
        // Area endpoints
        .route("/api/v1/areas/query", axum::routing::post(api::areas::query))
        // Polygon analysis
        .route("/api/v1/polygons/analyze", axum::routing::post(api::polygons::analyze))
        // Route analysis
        .route("/api/v1/routes/analyze", axum::routing::post(api::routes::analyze))
        // Quest hub analysis
        .route("/api/v1/hubs/:entry", axum::routing::get(api::hubs::analysis))
        // Validation
        .route("/api/v1/validate", axum::routing::post(api::validation::validate))
        // Search everywhere
        .route("/api/v1/search", axum::routing::get(api::search::search_all))
        // Blueprint suggestions
        .route("/api/v1/blueprints/suggest", axum::routing::post(api::blueprints::suggest))
        // Grind suggestions
        .route("/api/v1/grind/suggest", axum::routing::post(api::grind::suggest))
        // Loot lookup
        .route("/api/v1/items/:id/drops", axum::routing::get(api::loot::drops))
        // World graph
        .route("/api/v1/worldgraph/node/:id", axum::routing::get(api::graph::node))
        .with_state(state)
}

/// Health check endpoint
async fn health(axum::extract::State(state): axum::extract::State<AppState>) -> axum::response::Json<crate::models::Health> {
    let uptime = state.start_time.elapsed().as_secs();
    let cache_stats = crate::cache::CacheStats::from_cache(&state.cache);
    
    axum::response::Json(crate::models::Health {
        status: "ok",
        database: "connected".to_string(),
        uptime_sec: uptime,
        cache_stats,
    })
}

/// Prelude for common imports
pub mod prelude {
    pub use crate::{
        AppState, create_router, run_blocking,
        services::{QueryService, QuestService, NpcService, CreatureService, VendorService, TrainerService,
            FlightService, MailboxService, InnkeeperService, AreaService, RouteService,
            HubService, ValidationService, SearchService, BlueprintSuggestionService,
            GrindSuggestionService, LootService, GraphService},
    };
    pub use uuid::Uuid;
    pub use serde::{Serialize, Deserialize};
    pub use anyhow::Result;
    pub use moka::future::Cache;
}