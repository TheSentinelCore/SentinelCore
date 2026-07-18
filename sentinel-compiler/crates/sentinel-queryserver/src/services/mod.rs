//! Services — Volume 4 §27
//!
//! Business logic layer. All SQLite access runs inside `spawn_blocking`
//! so the `!Send` Connection never crosses an `.await` boundary.

use std::sync::Arc;
use anyhow::Result;
use moka::future::Cache;
use rusqlite::Connection;

mod helpers;
pub mod quests;
pub mod npcs;
pub mod creatures;
pub mod vendors;
pub mod trainers;
pub mod flight;
pub mod mailboxes;
pub mod innkeepers;
pub mod areas;
pub mod routes;
pub mod hubs;
pub mod validation;
pub mod search;
pub mod blueprints;
pub mod grind;
pub mod loot;
pub mod graph;

pub use quests::QuestService;
pub use npcs::NpcService;
pub use creatures::CreatureService;
pub use vendors::VendorService;
pub use trainers::TrainerService;
pub use flight::FlightService;
pub use mailboxes::MailboxService;
pub use innkeepers::InnkeeperService;
pub use areas::AreaService;
pub use routes::RouteService;
pub use hubs::HubService;
pub use validation::ValidationService;
pub use search::SearchService;
pub use blueprints::BlueprintSuggestionService;
pub use grind::GrindSuggestionService;
pub use loot::LootService;
pub use graph::GraphService;

use crate::models::*;

// ---------------------------------------------------------------------------
// Shared state
// ---------------------------------------------------------------------------

/// Shared service state
#[derive(Clone)]
pub struct ServiceState {
    pub db: Arc<tokio::sync::Mutex<Connection>>,
    pub cache: Arc<Cache<String, serde_json::Value>>,
}

impl ServiceState {
    pub fn new(db: Arc<tokio::sync::Mutex<Connection>>) -> Self {
        let cache = Cache::builder()
            .max_capacity(10_000)
            .time_to_live(std::time::Duration::from_secs(60))
            .build();

        Self {
            db,
            cache: Arc::new(cache),
        }
    }
}

// ---------------------------------------------------------------------------
// QueryService — unified facade
// ---------------------------------------------------------------------------

#[derive(Clone)]
pub struct QueryService {
    pub quests: QuestService,
    pub npcs: NpcService,
    pub creatures: CreatureService,
    pub vendors: VendorService,
    pub trainers: TrainerService,
    pub flights: FlightService,
    pub mailboxes: MailboxService,
    pub innkeepers: InnkeeperService,
    pub areas: AreaService,
    pub routes: RouteService,
    pub hubs: HubService,
    pub validation: ValidationService,
    pub search: SearchService,
    pub blueprints: BlueprintSuggestionService,
    pub grind: GrindSuggestionService,
    pub loot: LootService,
    pub graph: GraphService,
}

impl QueryService {
    pub fn new(db: Arc<tokio::sync::Mutex<rusqlite::Connection>>) -> Result<Self> {
        let state = ServiceState::new(db);

        Ok(Self {
            quests: QuestService::new(state.clone()),
            npcs: NpcService::new(state.clone()),
            creatures: CreatureService::new(state.clone()),
            vendors: VendorService::new(state.clone()),
            trainers: TrainerService::new(state.clone()),
            flights: FlightService::new(state.clone()),
            mailboxes: MailboxService::new(state.clone()),
            innkeepers: InnkeeperService::new(state.clone()),
            areas: AreaService::new(state.clone()),
            routes: RouteService::new(state.clone()),
            hubs: HubService::new(state.clone()),
            validation: ValidationService::new(state.clone()),
            search: SearchService::new(state.clone()),
            blueprints: BlueprintSuggestionService::new(state.clone()),
            grind: GrindSuggestionService::new(state.clone()),
            loot: LootService::new(state.clone()),
            graph: GraphService::new(state),
        })
    }

    // Quest API delegations
    pub async fn search_quests(
        &self,
        params: crate::api::quests::QuestSearchParams,
        limit: u32,
    ) -> Result<Vec<QuestSearchResult>> {
        self.quests.search_quests(params, limit).await
    }

    pub async fn get_quest_details(&self, quest_id: u32) -> Result<QuestDetails> {
        self.quests.get_details(quest_id).await
    }

    pub async fn get_quest_chain(&self, quest_id: u32, limit: u32) -> Result<QuestChain> {
        self.quests.get_quest_chain(quest_id, limit).await
    }

    pub async fn get_nearby_quests(
        &self,
        params: crate::api::quests::NearbyQuestsParams,
    ) -> Result<Vec<QuestSearchResult>> {
        self.quests.get_nearby_quests(params).await
    }

    pub async fn get_quest_npcs(
        &self,
        quest_id: u32,
        relation: &str,
        map_id: Option<u32>,
    ) -> Result<Vec<NpcDetails>> {
        self.quests.get_quest_npcs(quest_id, relation, map_id).await
    }

    // NPC API delegations
    pub async fn get_npc(&self, entry: u32) -> Result<NpcDetails> {
        self.npcs.get(entry).await
    }

    pub async fn search_npcs(
        &self,
        params: crate::api::npcs::NpcSearchParams,
        limit: u32,
    ) -> Result<Vec<NpcSearchResult>> {
        self.npcs.search_npcs(params, limit).await
    }

    pub async fn get_nearby_npcs(
        &self,
        params: crate::api::npcs::NearbyNpcsParams,
    ) -> Result<Vec<NpcSearchResult>> {
        self.npcs.get_nearby_npcs(params).await
    }

    // Creature API delegations
    pub async fn search_creatures(
        &self,
        params: crate::api::creatures::CreatureSearchParams,
        limit: u32,
    ) -> Result<Vec<CreatureDetails>> {
        self.creatures.search_creatures(params, limit).await
    }

    pub async fn get_creature_spawns(&self, entry: u32) -> Result<Vec<CreatureSpawn>> {
        self.creatures.get_creature_spawns(entry).await
    }

    // Vendor API delegations
    pub async fn get_vendor(&self, entry: u32) -> Result<VendorDetails> {
        self.vendors.get_vendor(entry).await
    }

    // Trainer API delegations
    pub async fn get_trainer(&self, entry: u32) -> Result<TrainerDetails> {
        self.trainers.get_trainer(entry).await
    }

    // Flight API delegations
    pub async fn get_flight_masters(&self) -> Result<Vec<FlightMaster>> {
        self.flights.get_flight_masters().await
    }

    // Mailbox API delegations
    pub async fn get_mailboxes(&self) -> Result<Vec<Mailbox>> {
        self.mailboxes.get_mailboxes().await
    }

    // Innkeeper API delegations
    pub async fn get_innkeepers(&self) -> Result<Vec<Innkeeper>> {
        self.innkeepers.get_innkeepers().await
    }

    // Area API delegations
    pub async fn query_area(
        &self,
        request: crate::api::areas::AreaQueryRequest,
    ) -> Result<AreaQueryResult> {
        self.areas.query_area(request).await
    }

    pub async fn analyze_polygon(
        &self,
        request: crate::api::polygons::PolygonAnalysisRequest,
    ) -> Result<PolygonAnalysis> {
        self.areas.analyze_polygon(request).await
    }

    // Route API delegations
    pub async fn analyze_route(
        &self,
        request: crate::api::routes::RouteAnalysisRequest,
    ) -> Result<RouteAnalysis> {
        self.routes.analyze_route(request).await
    }

    // Hub API delegations
    pub async fn analyze_quest_hub(&self, entry: u32) -> Result<QuestHubAnalysis> {
        self.hubs.analyze_quest_hub(entry).await
    }

    // Validation API delegations
    pub async fn validate_profile(&self, fragment: serde_json::Value) -> Result<ValidationResult> {
        self.validation.validate_profile(fragment).await
    }

    // Search API delegations
    pub async fn search_all(&self, query: &str, limit: u32) -> Result<SearchResult> {
        self.search.search_all(query, limit).await
    }

    // Blueprint API delegations
    pub async fn suggest_blueprint(
        &self,
        request: crate::api::blueprints::BlueprintSuggestRequest,
    ) -> Result<BlueprintSuggestion> {
        self.blueprints.suggest_blueprint(request).await
    }

    // Grind API delegations
    pub async fn suggest_grind(
        &self,
        request: crate::api::grind::GrindSuggestRequest,
    ) -> Result<GrindSuggestion> {
        self.grind.suggest_grind(request).await
    }

    // Loot API delegations
    pub async fn get_item_drops(&self, item_id: u32) -> Result<ItemDrops> {
        self.loot.get_item_drops(item_id).await
    }

    // Graph API delegations
    pub async fn get_world_graph_node(&self, id: String) -> Result<WorldGraphNode> {
        self.graph.get_node(id).await
    }
}
