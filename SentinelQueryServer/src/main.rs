use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

use sentinel_query_server::blackboard::ServerBlackboard;
use sentinel_query_server::config::Config;
use sentinel_query_server::importer::Importer;
use sentinel_query_server::routes;
use sentinel_query_server::services::{
    DefaultContextService, DefaultEntityService, DefaultFlightMasterService,
    DefaultInnkeeperService, DefaultMetaService, DefaultTrainerService, DefaultVendorService,
};
use sentinel_query_server::state::StartupStatus;
use sentinel_query_server::storage::repositories::context::ContextRepository;
use sentinel_query_server::storage::repositories::entity::EntityRepository;
use sentinel_query_server::storage::repositories::flight_master::FlightMasterRepository;
use sentinel_query_server::storage::repositories::innkeeper::InnkeeperRepository;
use sentinel_query_server::storage::repositories::meta::MetaRepository;
use sentinel_query_server::storage::repositories::trainer::TrainerRepository;
use sentinel_query_server::storage::repositories::vendor::VendorRepository;
use sentinel_query_server::storage::SqliteStore;
use sentinel_query_server::telemetry::MetricsRegistry;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("sentinel_query_server=info".parse()?),
        )
        .init();

    tracing::info!(
        "Sentinel Query Server v{} starting...",
        env!("CARGO_PKG_VERSION")
    );

    let config = Config::load().map_err(|e| anyhow::anyhow!(e.to_string()))?;

    let startup = StartupStatus::new();
    startup.set_importing();

    let importer = Importer::new(config.clone());
    let db_path = match importer.ensure_runtime_db() {
        Ok(path) => path,
        Err(err) => {
            startup.set_failed(err.message.clone());
            return Err(anyhow::anyhow!(err.message));
        }
    };

    let store = Arc::new(SqliteStore::new(db_path));
    let meta_repo = Arc::new(MetaRepository::new(store.clone()));
    let manifest = match meta_repo.get_manifest() {
        Ok(manifest) => manifest,
        Err(err) => {
            startup.set_failed(err.message.clone());
            return Err(anyhow::anyhow!(err.message));
        }
    };

    let context_repo = Arc::new(ContextRepository::new(store.clone()));
    let vendor_repo = Arc::new(VendorRepository::new(store.clone()));
    let trainer_repo = Arc::new(TrainerRepository::new(store.clone()));
    let flight_repo = Arc::new(FlightMasterRepository::new(store.clone()));
    let innkeeper_repo = Arc::new(InnkeeperRepository::new(store.clone()));
    let entity_repo = Arc::new(EntityRepository::new(store.clone()));

    let state = Arc::new(ServerBlackboard {
        context: Arc::new(DefaultContextService::new(context_repo)),
        vendor: Arc::new(DefaultVendorService::new(vendor_repo)),
        trainer: Arc::new(DefaultTrainerService::new(trainer_repo)),
        flight_master: Arc::new(DefaultFlightMasterService::new(flight_repo)),
        innkeeper: Arc::new(DefaultInnkeeperService::new(innkeeper_repo)),
        entity: Arc::new(DefaultEntityService::new(entity_repo)),
        meta: Arc::new(DefaultMetaService::new(meta_repo)),
        store,
        config: Arc::new(config.clone()),
        startup_status: startup.clone(),
        metrics: Arc::new(MetricsRegistry::default()),
        start_time: Instant::now(),
        manifest: Arc::new(manifest),
    });

    startup.set_ready();

    let app = routes::build_router(state.clone());
    let addr: SocketAddr = format!("{}:{}", config.server.host, config.server.port)
        .parse()
        .map_err(|e| anyhow::anyhow!("invalid listen address: {}", e))?;

    tracing::info!("listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => tracing::info!("received Ctrl+C, shutting down"),
        _ = terminate => tracing::info!("received SIGTERM, shutting down"),
    }
}
