use std::sync::{Arc, Mutex};

use sentinel_duo_coord_server::{
    app_state::AppState,
    config::Config,
    routes,
    state::SessionState,
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info".into()),
        )
        .init();

    let config = Config::load()?;
    let addr = format!("{}:{}", config.server.host, config.server.port);

    let session_state = Arc::new(Mutex::new(SessionState::default()));

    let app_state = AppState {
        session: session_state,
        config: config.clone(),
    };

    let router = routes::build_router(app_state);

    tracing::info!("SentinelDuoCoordServer listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, router).await?;

    Ok(())
}
