use sentinel_queryserver::{AppState, create_router};
use std::net::SocketAddr;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,sentinel_queryserver=debug".parse().unwrap()),
        )
        .init();

    // Configuration from environment variables
    let db_path = std::env::var("SENTINEL_DB_PATH")
        .unwrap_or_else(|_| "./tbcmangos.sqlite".to_string());

    let bind_addr: SocketAddr = std::env::var("SENTINEL_BIND")
        .unwrap_or_else(|_| "127.0.0.1:3000".to_string())
        .parse()?;

    tracing::info!("Starting Sentinel QueryServer");
    tracing::info!("  Database: {}", db_path);
    tracing::info!("  Bind: {}", bind_addr);

    // Initialize application state
    let state = AppState::new(db_path).await?;

    // Build router with CORS for local development
    let app = create_router(state)
        .layer(
            tower_http::cors::CorsLayer::permissive()
                .allow_methods([
                    axum::http::Method::GET,
                    axum::http::Method::POST,
                    axum::http::Method::OPTIONS,
                ])
                .allow_origin(tower_http::cors::Any),
        )
        .layer(tower_http::trace::TraceLayer::new_for_http());

    // Start server
    let listener = tokio::net::TcpListener::bind(bind_addr).await?;
    tracing::info!("Listening on {}", bind_addr);

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    tracing::info!("Server shut down gracefully");
    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = tokio::signal::ctrl_c();
    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .expect("failed to install SIGTERM handler");

    tokio::select! {
        _ = ctrl_c => {
            tracing::info!("Received SIGINT, shutting down...");
        }
        _ = sigterm.recv() => {
            tracing::info!("Received SIGTERM, shutting down...");
        }
    }
}
