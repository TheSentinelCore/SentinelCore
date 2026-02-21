use std::sync::Arc;
use std::time::Instant;

use crate::config::Config;
use crate::models::DatasetManifest;
use crate::services::{
    ContextService, EntityService, FlightMasterService, InnkeeperService, MetaService,
    TrainerService, VendorService,
};
use crate::state::StartupStatus;
use crate::storage::SqliteStore;
use crate::telemetry::MetricsRegistry;

#[derive(Clone)]
pub struct ServerBlackboard {
    pub context: Arc<dyn ContextService>,
    pub vendor: Arc<dyn VendorService>,
    pub trainer: Arc<dyn TrainerService>,
    pub flight_master: Arc<dyn FlightMasterService>,
    pub innkeeper: Arc<dyn InnkeeperService>,
    pub entity: Arc<dyn EntityService>,
    pub meta: Arc<dyn MetaService>,
    pub store: Arc<SqliteStore>,
    pub config: Arc<Config>,
    pub startup_status: StartupStatus,
    pub metrics: Arc<MetricsRegistry>,
    pub start_time: Instant,
    pub manifest: Arc<DatasetManifest>,
}
