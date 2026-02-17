//! Sentinel Navigation Server - High-performance navigation server for WoW pathfinding.
//!
//! This server provides HTTP endpoints for pathfinding using TrinityCore
//! navigation mesh files (mmaps).

use std::net::SocketAddr;
use std::time::Duration;

use tower_http::timeout::TimeoutLayer;

mod cache;
mod config;
mod error;
mod pipeline;
mod routes;
mod state;
mod validation;

use config::Config;
use state::AppState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize logging with multiple directives
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("sentinel_nav_server=info".parse()?)
                .add_directive("tc_mmap=info".parse()?)
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

    // Create application state (triggers map preloading if configured)
    let state = AppState::new(config.clone())?;
    tracing::info!(
        "Application state initialized, {} maps preloaded",
        state.mmap_manager.loaded_map_count()
    );

    // Build router with timeout middleware
    let app = routes::build_router(state)
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
