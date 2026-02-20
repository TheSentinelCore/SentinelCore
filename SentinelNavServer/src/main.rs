//! Sentinel Navigation Server - High-performance navigation server for WoW pathfinding.
//!
//! This server provides HTTP endpoints for pathfinding using CMaNGOS-generated
//! navigation mesh files (mmaps).

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::sync::Semaphore;
use tower_http::timeout::TimeoutLayer;

mod blackboard;
mod cache;
mod config;
mod error;
mod pipeline;
mod routes;
mod services;
mod state;
mod validation;

use blackboard::ServerBlackboard;
use cache::PathCache;
use config::Config;
use services::cache_impl::MokaCache;
use services::pathfinding::DetourPathfinder;
use services::routing::DetourRouter;

use services::spatial::DetourSpatial;
use services::tactical::DetourTactical;
use state::Metrics;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize logging with multiple directives
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("sentinel_nav_server=info".parse()?)
                .add_directive("mmap_loader=info".parse()?)
                .add_directive("detour=warn".parse()?),
        )
        .init();

    tracing::info!(
        "Sentinel Navigation Server v{} starting...",
        env!("CARGO_PKG_VERSION")
    );

    // Load configuration
    let config = Config::load()?;
    tracing::info!(
        "Configuration loaded: host={}, port={}, mmap_path={:?}",
        config.server.host,
        config.server.port,
        config.navmesh.mmap_path
    );

    // Create shared infrastructure
    let mmap_manager = Arc::new(mmap_loader::MmapManager::new(
        &config.navmesh.mmap_path,
        config.pathfinding.query_pool_size,
        config.pathfinding.max_query_nodes,
    ));

    tracing::info!(
        "MmapManager created: pool_size={}, max_query_nodes={}",
        config.pathfinding.query_pool_size,
        config.pathfinding.max_query_nodes,
    );

    // Preload configured maps
    for &map_id in &config.navmesh.preload_maps {
        tracing::info!("Preloading map {}", map_id);
        match mmap_manager.get_or_load_mesh(map_id) {
            Ok(_) => tracing::info!("Successfully preloaded map {}", map_id),
            Err(e) => tracing::warn!("Failed to preload map {}: {}", map_id, e),
        }
    }

    let path_cache = Arc::new(PathCache::new());

    // Build concrete service implementations
    let pathfinder: Arc<dyn services::PathfindingService> =
        Arc::new(DetourPathfinder::new(mmap_manager.clone()));
    let router: Arc<dyn services::RoutingService> =
        Arc::new(DetourRouter::new(mmap_manager.clone()));
    let spatial: Arc<dyn services::SpatialService> =
        Arc::new(DetourSpatial::new(mmap_manager.clone()));
    let tactical: Arc<dyn services::TacticalService> =
        Arc::new(DetourTactical::new(mmap_manager.clone()));
    let cache: Arc<dyn services::CacheService> =
        Arc::new(MokaCache::new(path_cache.clone()));

    // Assemble the ServerBlackboard
    let blackboard = Arc::new(ServerBlackboard {
        pathfinding: pathfinder,
        routing: router,
        spatial,
        tactical,
        cache,
        mmap_manager: mmap_manager.clone(),
        request_semaphore: Arc::new(Semaphore::new(config.server.max_concurrent_requests)),
        path_cache,
        config: Arc::new(config.clone()),
        metrics: Arc::new(Metrics::new()),
        start_time: Instant::now(),
    });

    tracing::info!(
        "ServerBlackboard initialized, {} maps preloaded",
        mmap_manager.loaded_map_count()
    );

    // Build router with timeout middleware
    let app = routes::build_router(blackboard)
        .layer(TimeoutLayer::new(Duration::from_secs(30)));

    // Start server
    let addr: SocketAddr = format!("{}:{}", config.server.host, config.server.port)
        .parse()
        .map_err(|e| anyhow::anyhow!(
            "Invalid listen address '{}:{}': {}",
            config.server.host, config.server.port, e
        ))?;

    tracing::info!("Listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    tracing::info!("Server shutdown complete");
    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("Failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => tracing::info!("Received Ctrl+C, shutting down..."),
        _ = terminate => tracing::info!("Received SIGTERM, shutting down..."),
    }
}
